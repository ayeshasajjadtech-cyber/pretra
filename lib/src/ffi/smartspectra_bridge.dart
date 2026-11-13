// lib/src/ffi/smartspectra_bridge.dart

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'smartspectra_bindings.dart';
import '../metrics_codec.dart';
import '../models.dart';

enum QualityControlStatus {
  optimal(0, 'Signal conditions optimal'),
  noFace(1, 'Align your face in front of the camera'),
  multipleFaces(2, 'Multiple faces detected. Please ensure solo framing'),
  offCenter(3, 'Center your head inside the guide frame'),
  tooDark(5, 'Lighting too dim. Please increase ambient light'),
  tooBright(6, 'Lighting too direct or glare detected'),
  chestNotVisible(
    7,
    'Ensure your upper chest is visible for respiration tracking',
  ),
  cameraTuning(10, 'Camera auto-adjusting focus and exposure'),
  frameRateLow(11, 'Camera frame rate is currently low'),
  excessiveMotion(12, 'Please remain steady for consistent cadence'),
  unknown(-1, 'The SDK reported an unrecognized quality state');

  const QualityControlStatus(this.code, this.userGuidance);
  final int code;
  final String userGuidance;

  static QualityControlStatus fromCode(int code) {
    return QualityControlStatus.values.firstWhere(
      (e) => e.code == code,
      orElse: () => QualityControlStatus.unknown,
    );
  }
}

class QualityControlEvent {
  const QualityControlEvent({
    required this.status,
    required this.hint,
    required this.timestampUs,
  });

  final QualityControlStatus status;
  final String hint;
  final int timestampUs;
}

/// Copied frame data from the SDK's borrowed video-output callback buffer.
class CameraVideoFrame {
  const CameraVideoFrame({
    required this.width,
    required this.height,
    required this.strideBytes,
    required this.pixelFormat,
    required this.bytes,
    required this.timestampUs,
  });

  final int width;
  final int height;
  final int strideBytes;
  final int pixelFormat;
  final Uint8List bytes;
  final int timestampUs;
}

class SmartSpectraBridge {
  SmartSpectraBridge({String? dllPath}) : _customDllPath = dllPath;

  final String? _customDllPath;

  SmartSpectraFfiBindings? _bindings;
  SmartSpectraCallbackRelayBindings? _videoRelay;
  Pointer<SmartSpectraSession>? _session;

  // Native thread-safe callback handles
  NativeCallable<NativeStatusCb>? _statusCallable;
  NativeCallable<NativeValidationCb>? _validationCallable;
  NativeCallable<NativeMetricsCb>? _metricsCallable;
  NativeCallable<NativeErrorCb>? _errorCallable;
  NativeCallable<NativeVideoOutputCb>? _videoCallable;

  final _telemetryController = StreamController<DecodedMetrics>.broadcast();
  final _qcController = StreamController<QualityControlEvent>.broadcast();
  final _statusController = StreamController<int>.broadcast();
  final _nativeErrorController = StreamController<String>.broadcast();
  final _videoController = StreamController<CameraVideoFrame>.broadcast();

  Stream<DecodedMetrics> get telemetryStream => _telemetryController.stream;
  Stream<QualityControlEvent> get qualityControlStream => _qcController.stream;
  Stream<int> get statusStream => _statusController.stream;
  Stream<String> get nativeErrorStream => _nativeErrorController.stream;
  Stream<CameraVideoFrame> get videoFrameStream => _videoController.stream;

  bool _isInitialized = false;
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  static String resolveDllPath([String? override]) {
    if (override != null && File(override).existsSync()) {
      return override;
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$exeDir\\smartspectra_capi.dll',
      // Source-tree lookup is useful for `flutter run`; the CMake install rule
      // copies this whole native folder beside the executable for deployment.
      '$exeDir\\windows\\runner\\native\\smartspectra_capi.dll',
      'windows\\runner\\native\\smartspectra_capi.dll',
      'build\\windows\\x64\\runner\\Debug\\smartspectra_capi.dll',
      'build\\windows\\x64\\runner\\Release\\smartspectra_capi.dll',
      'electron_app\\node_modules\\@smartspectra\\node-sdk-win32-x64\\smartspectra_capi.dll',
    ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return File(candidate).absolute.path;
      }
    }

    return 'smartspectra_capi.dll';
  }

  static String resolveGraphDir([String? override]) {
    if (override != null && Directory(override).existsSync()) {
      return override;
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$exeDir\\graph',
      'windows\\runner\\native\\graph',
      'build\\windows\\x64\\runner\\Debug\\graph',
      'build\\windows\\x64\\runner\\Release\\graph',
      'electron_app\\node_modules\\@smartspectra\\node-sdk-win32-x64\\graph',
    ];

    for (final candidate in candidates) {
      if (Directory(candidate).existsSync()) {
        return Directory(candidate).absolute.path;
      }
    }

    return exeDir;
  }

  void initialize() {
    if (_isInitialized) return;
    final resolvedPath = resolveDllPath(_customDllPath);
    try {
      final lib = DynamicLibrary.open(resolvedPath);
      _bindings = SmartSpectraFfiBindings(lib);
      _videoRelay = SmartSpectraCallbackRelayBindings(DynamicLibrary.process());
    } on ArgumentError catch (error) {
      throw StateError(
        'Unable to load SmartSpectra from "$resolvedPath". Confirm the SDK '
        'DLL and its dependent DLLs are beside the application executable. '
        'Windows loader detail: $error',
      );
    }
    _isInitialized = true;
  }

  Future<void> start({
    required String apiKey,
    int width = 1280,
    int height = 720,
    int fps = 30,
  }) async {
    if (_isRunning) return;
    initialize();

    final bindings = _bindings!;
    final localAppData =
        Platform.environment['LOCALAPPDATA'] ?? Directory.current.path;
    final cacheDir = Directory('$localAppData\\Presage\\SmartSpectra');
    try {
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
    } catch (_) {}
    final cachePath = cacheDir.existsSync()
        ? cacheDir.path
        : Directory.current.path;

    using((arena) {
      final err = arena<SmartSpectraError>();
      final dirPtr = cachePath.toNativeUtf8(allocator: arena);
      final devIdPtr = 'pretra-flutter-win'.toNativeUtf8(allocator: arena);

      // Best-effort preconfigure with cache directory
      bindings.preconfigure(dirPtr, devIdPtr, err);

      // Create thread-safe NativeCallable.listener
      _statusCallable = NativeCallable<NativeStatusCb>.listener(_handleStatus);
      _validationCallable = NativeCallable<NativeValidationCb>.listener(
        _handleValidation,
      );
      _metricsCallable = NativeCallable<NativeMetricsCb>.listener(
        _handleMetrics,
      );
      _errorCallable = NativeCallable<NativeErrorCb>.listener(_handleError);
      _videoCallable = NativeCallable<NativeVideoOutputCb>.listener(
        _handleVideoOutput,
      );
      _videoRelay!.setVideoListener(
        _videoCallable!.nativeFunction.cast<Void>(),
      );
      _videoRelay!.setMetricsListener(
        _metricsCallable!.nativeFunction.cast<Void>(),
      );
      _videoRelay!.setValidationListener(
        _validationCallable!.nativeFunction.cast<Void>(),
      );
      _videoRelay!.setErrorListener(
        _errorCallable!.nativeFunction.cast<Void>(),
      );

      final callbacks = arena<SmartSpectraCallbacks>();
      callbacks.ref.onStatus = _statusCallable!.nativeFunction;
      callbacks.ref.onValidation = _videoRelay!.validationCallback;
      callbacks.ref.onMetrics = _videoRelay!.metricsCallback;
      callbacks.ref.onError = _videoRelay!.errorCallback;
      callbacks.ref.onFrame = nullptr;
      callbacks.ref.onAccumulatedMetrics = nullptr;
      callbacks.ref.onInsight = nullptr;
      callbacks.ref.onVideoOutput = _videoRelay!.videoOutputCallback;

      // 1. Try Breathing + Cardio (0..7, 15..17)
      const fullMetrics = [0, 1, 2, 3, 5, 7, 15, 16, 17];
      final metricsPtr = arena<Int32>(fullMetrics.length);
      for (var i = 0; i < fullMetrics.length; i++) {
        metricsPtr[i] = fullMetrics[i];
      }

      final config = arena<SmartSpectraConfig>();
      config.ref.apiKey = apiKey.trim().toNativeUtf8(allocator: arena);
      config.ref.requestedMetrics = metricsPtr;
      config.ref.requestedMetricsLen = fullMetrics.length;
      config.ref.enableAccumulatedOutput = 0;
      config.ref.logLevel = 2; // Warning
      config.ref.structSize = 40; // Exact C-ABI struct size
      config.ref.disableTelemetry = 1; // Privacy-first local processing
      config.ref.reserved0 = 0;

      _session = bindings.sessionCreate(config, 0, callbacks, err);

      // 2. If entitlement failed, fallback to Breathing-only
      if (_session == null || _session == nullptr) {
        debugPrint(
          '[SmartSpectra] Full metrics creation notice: ${err.ref.errorMessage}. Retrying with breathing-only...',
        );
        const breathingOnly = [0, 1, 2, 3, 5, 7];
        final breathingPtr = arena<Int32>(breathingOnly.length);
        for (var i = 0; i < breathingOnly.length; i++) {
          breathingPtr[i] = breathingOnly[i];
        }
        config.ref.requestedMetrics = breathingPtr;
        config.ref.requestedMetricsLen = breathingOnly.length;
        _session = bindings.sessionCreate(config, 0, callbacks, err);
      }

      if (_session == null || _session == nullptr) {
        throw Exception(
          'SmartSpectra session creation failed: ${err.ref.errorMessage}',
        );
      }

      // 3. Start Camera via native auto-negotiation
      final camRes = bindings.sessionStartSelectedCamera(
        _session!,
        0,
        nullptr,
        nullptr,
        err,
      );
      if (camRes != 0) {
        throw Exception(
          'SmartSpectra camera start failed: ${err.ref.errorMessage}',
        );
      }

      _isRunning = true;
    });
  }

  void _handleStatus(int handle, int status) {
    if (!_statusController.isClosed) _statusController.add(status);
  }

  void _handleValidation(
    int handle,
    int code,
    Pointer<Utf8> hintPtr,
    int timestampUs,
  ) {
    try {
      final hint = hintPtr != nullptr ? hintPtr.toDartString() : '';
      final event = QualityControlEvent(
        status: QualityControlStatus.fromCode(code),
        hint: hint,
        timestampUs: timestampUs,
      );
      if (!_qcController.isClosed) _qcController.add(event);
    } finally {
      if (hintPtr != nullptr) _videoRelay?.freeFrame(hintPtr.cast<Uint8>());
    }
  }

  void _handleMetrics(
    int handle,
    Pointer<Uint8> bytesPtr,
    int length,
    int timestampUs,
  ) {
    if (bytesPtr == nullptr) return;
    try {
      if (length <= 0 || length > 64 * 1024 * 1024) return;
      final bytes = Uint8List.fromList(bytesPtr.asTypedList(length));
      final decoded = MetricsCodec.decode(bytes);
      if (!_telemetryController.isClosed) _telemetryController.add(decoded);
    } finally {
      _videoRelay?.freeFrame(bytesPtr);
    }
  }

  void _handleError(int handle, int code, Pointer<Utf8> msgPtr, int retryable) {
    try {
      final msg = msgPtr != nullptr ? msgPtr.toDartString() : 'Unknown';
      debugPrint('[PreTra Native Error $code] $msg (retryable: $retryable)');
      if (!_nativeErrorController.isClosed) {
        _nativeErrorController.add('SDK error $code: $msg');
      }
    } finally {
      if (msgPtr != nullptr) _videoRelay?.freeFrame(msgPtr.cast<Uint8>());
    }
  }

  void _handleVideoOutput(
    int handle,
    Pointer<Uint8> data,
    int width,
    int height,
    int strideBytes,
    int pixelFormat,
    int timestampUs,
  ) {
    if (data == nullptr) return;
    try {
      if (width <= 0 || height <= 0 || width > 4096 || height > 4096) return;

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastVideoFrameAtMs < 66) return;
      _lastVideoFrameAtMs = nowMs;

      final isNv = pixelFormat == 4 || pixelFormat == 5;
      final bytesPerPixel = (pixelFormat == 0 || pixelFormat == 1)
          ? 3
          : (pixelFormat == 2 || pixelFormat == 3)
          ? 4
          : 1;
      final minimumStride = isNv
          ? ((width + 1) ~/ 2) * 2
          : width * bytesPerPixel;
      if (pixelFormat < 0 || pixelFormat > 5 || strideBytes < minimumStride) {
        return;
      }
      final byteLength =
          strideBytes * height + (isNv ? strideBytes * ((height + 1) ~/ 2) : 0);
      if (byteLength <= 0 || byteLength > 64 * 1024 * 1024) return;

      final bytes = Uint8List.fromList(data.asTypedList(byteLength));
      if (pixelFormat == 0 || pixelFormat == 1 || isNv) {
        final rgba = Uint8List(width * height * 4);
        for (var y = 0; y < height; y++) {
          final sourceRow = y * strideBytes;
          final targetRow = y * width * 4;
          for (var x = 0; x < width; x++) {
            final target = targetRow + x * 4;
            if (isNv) {
              final chromaRow = strideBytes * height + (y ~/ 2) * strideBytes;
              final chroma = chromaRow + (x ~/ 2) * 2;
              final yValue = bytes[sourceRow + x] - 16;
              final u = bytes[chroma + (pixelFormat == 4 ? 0 : 1)] - 128;
              final v = bytes[chroma + (pixelFormat == 4 ? 1 : 0)] - 128;
              final luminance = yValue < 0 ? 0 : yValue;
              rgba[target] = ((298 * luminance + 409 * v + 128) >> 8)
                  .clamp(0, 255)
                  .toInt();
              rgba[target +
                  1] = ((298 * luminance - 100 * u - 208 * v + 128) >> 8)
                  .clamp(0, 255)
                  .toInt();
              rgba[target + 2] = ((298 * luminance + 516 * u + 128) >> 8)
                  .clamp(0, 255)
                  .toInt();
            } else {
              final source = sourceRow + x * 3;
              if (pixelFormat == 0) {
                rgba[target] = bytes[source];
                rgba[target + 1] = bytes[source + 1];
                rgba[target + 2] = bytes[source + 2];
              } else {
                rgba[target] = bytes[source + 2];
                rgba[target + 1] = bytes[source + 1];
                rgba[target + 2] = bytes[source];
              }
            }
            rgba[target + 3] = 255;
          }
        }
        if (!_videoController.isClosed) {
          _videoController.add(
            CameraVideoFrame(
              width: width,
              height: height,
              strideBytes: width * 4,
              pixelFormat: 2,
              bytes: rgba,
              timestampUs: timestampUs,
            ),
          );
        }
        return;
      }

      if (!_videoController.isClosed) {
        _videoController.add(
          CameraVideoFrame(
            width: width,
            height: height,
            strideBytes: strideBytes,
            pixelFormat: pixelFormat,
            bytes: bytes,
            timestampUs: timestampUs,
          ),
        );
      }
    } finally {
      _videoRelay?.freeFrame(data);
    }
  }

  int _lastVideoFrameAtMs = 0;

  Future<void> stop() async {
    _isRunning = false;
    _videoRelay?.setVideoListener(nullptr);
    _videoRelay?.setMetricsListener(nullptr);
    _videoRelay?.setValidationListener(nullptr);
    _videoRelay?.setErrorListener(nullptr);

    if (_session != null && _session != nullptr) {
      _bindings?.sessionStop(_session!);
      _bindings?.sessionDestroy(_session!);
      _session = null;
    }

    // NativeCallable.listener returns to C immediately and queues Dart work.
    // Give already-relayed callbacks a turn to copy and release their buffers
    // before invalidating the listener trampolines.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    _statusCallable?.close();
    _validationCallable?.close();
    _metricsCallable?.close();
    _errorCallable?.close();
    _videoCallable?.close();
    _statusCallable = null;
    _validationCallable = null;
    _metricsCallable = null;
    _errorCallable = null;
    _videoCallable = null;
  }

  Future<void> dispose() async {
    await stop();
    await _telemetryController.close();
    await _qcController.close();
    await _statusController.close();
    await _nativeErrorController.close();
    await _videoController.close();
  }
}
