
import 'package:flutter/services.dart';

import 'metrics_codec.dart';
import 'models.dart';
import 'source_events.dart';

class SmartSpectraException implements Exception {
  const SmartSpectraException({
    required this.code,
    required this.message,
    this.retryable = false,
  });

  final int code;
  final String message;
  final bool retryable;

  @override
  String toString() => 'SmartSpectraException($code): $message';
}

class SmartSpectraSource {
  SmartSpectraSource({
    this.onMetrics,
    this.onStatus,
    this.onValidation,
    this.onError,
  });

  static const MethodChannel _channel =
      MethodChannel('breathe_garden/smartspectra');

  final MetricsCallback? onMetrics;
  final StatusCallback? onStatus;
  final ValidationCallback? onValidation;
  final SourceErrorCallback? onError;

  bool _handlerSet = false;

  Future<void> start({
    required String apiKey,
    required String dataDirectory,
    String? cameraId,
    int? deviceIndex,
    int width = 1280,
    int height = 720,
    int fps = 30,
  }) async {
    _setHandler();
    final arguments = <String, Object?>{
      'apiKey': apiKey,
      'dataDirectory': dataDirectory,
      'cameraId': cameraId,
      'deviceIndex': deviceIndex,
      'width': width,
      'height': height,
      'fps': fps,
      'requestedMetrics': <int>[
        ...breathingMetrics,
        ...cardioMetrics,
      ],
      'enableTelemetry': false,
      'logLevel': 2,
    };

    try {
      await _channel.invokeMethod<Object?>('start', arguments);
    } on PlatformException catch (error) {
      final code = int.tryParse(error.code) ?? 100;
      final retryable = _retryableFromDetails(error.details);
      onError?.call(code, error.message ?? '', retryable);
      throw SmartSpectraException(
        code: code,
        message: error.message ?? '',
        retryable: retryable,
      );
    } on MissingPluginException {
      const code = 100;
      const message =
          'The SmartSpectra bridge is unavailable. Build with SMARTSPECTRA_SDK_DIR set to the extracted Windows SDK.';
      onError?.call(code, message, false);
      throw const SmartSpectraException(code: code, message: message);
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _channel.invokeMethod<void>('dispose');
    } on PlatformException {
      // The native session may already be gone.
    } on MissingPluginException {
      // Nothing to dispose when the bridge is not built in.
    }
    if (_handlerSet) {
      _channel.setMethodCallHandler(null);
      _handlerSet = false;
    }
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'status':
        final status = _asInt(call.arguments);
        if (status != null) onStatus?.call(status);
        break;
      case 'validation':
        final args = _asMap(call.arguments);
        onValidation?.call(
          _asInt(args['code']) ?? 0,
          _asString(args['hint']),
          _asInt(args['timestampUs']) ?? 0,
        );
        break;
      case 'metrics':
        final args = _asMap(call.arguments);
        final bytes = _asBytes(args['bytes']);
        if (bytes != null) {
          onMetrics?.call(
            MetricsCodec.decode(bytes),
            DateTime.now().millisecondsSinceEpoch,
          );
        }
        break;
      case 'error':
        final args = _asMap(call.arguments);
        onError?.call(
          _asInt(args['code']) ?? 0,
          _asString(args['message']),
          args['retryable'] == true,
        );
        break;
      case 'videoOutput':
        return null;
      default:
        return null;
    }
  }

  void _setHandler() {
    if (_handlerSet) return;
    _channel.setMethodCallHandler(_handleCall);
    _handlerSet = true;
  }

  static bool _retryableFromDetails(Object? details) {
    if (details is bool) return details;
    if (details is Map) return details['retryable'] == true;
    return false;
  }

  static Map<Object?, Object?> _asMap(Object? value) {
    if (value is Map<Object?, Object?>) return value;
    if (value is Map) return value.cast<Object?, Object?>();
    return const <Object?, Object?>{};
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static String _asString(Object? value) {
    return value is String ? value : '';
  }

  static Uint8List? _asBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }
}
