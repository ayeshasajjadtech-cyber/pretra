// lib/src/ffi/smartspectra_bindings.dart
// Presage SmartSpectra C-API FFI Bindings conforming to smartspectra_capi.h

import 'dart:ffi';
import 'package:ffi/ffi.dart';

// Opaque tokens
final class SmartSpectraSession extends Opaque {}

final class SmartSpectraCameraList extends Opaque {}

/// Error structure populated by SmartSpectra C-API
final class SmartSpectraError extends Struct {
  @Int32()
  external int code;

  @Array(512)
  external Array<Uint8> message;

  @Int32()
  external int retryable;

  String get errorMessage {
    final bytes = <int>[];
    for (var i = 0; i < 512; i++) {
      final b = message[i];
      if (b == 0) break;
      bytes.add(b);
    }
    return String.fromCharCodes(bytes);
  }
}

/// Configuration structure passed to smartspectra_session_create
final class SmartSpectraConfig extends Struct {
  external Pointer<Utf8> apiKey;
  external Pointer<Int32> requestedMetrics;
  @Int32()
  external int requestedMetricsLen;
  @Int32()
  external int enableAccumulatedOutput;
  @Int32()
  external int logLevel;
  @Uint32()
  external int structSize;
  @Int32()
  external int disableTelemetry;
  @Int32()
  external int reserved0;
}

/// Camera options structure for legacy/direct camera start
final class SmartSpectraCameraOptions extends Struct {
  @Int32()
  external int deviceIndex;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Int32()
  external int fps;
  @Int32()
  external int frameTransform;
}

// Native callback typedefs
typedef NativeStatusCb = Void Function(UintPtr handle, Int32 status);
typedef NativeValidationCb =
    Void Function(
      UintPtr handle,
      Int32 code,
      Pointer<Utf8> hint,
      Int64 timestampUs,
    );
typedef NativeMetricsCb =
    Void Function(
      UintPtr handle,
      Pointer<Uint8> protoBytes,
      Int32 protoLen,
      Int64 timestampUs,
    );
typedef NativeErrorCb =
    Void Function(
      UintPtr handle,
      Int32 code,
      Pointer<Utf8> message,
      Int32 retryable,
    );
typedef NativeVideoOutputCb =
    Void Function(
      UintPtr handle,
      Pointer<Uint8> data,
      Int32 width,
      Int32 height,
      Int32 strideBytes,
      Int32 pixelFormat,
      Int64 timestampUs,
    );

/// Callback table structure passed to smartspectra_session_create
final class SmartSpectraCallbacks extends Struct {
  external Pointer<NativeFunction<NativeStatusCb>> onStatus;
  external Pointer<NativeFunction<NativeValidationCb>> onValidation;
  external Pointer<NativeFunction<NativeMetricsCb>> onMetrics;
  external Pointer<NativeFunction<NativeErrorCb>> onError;
  external Pointer<Void> onFrame;
  external Pointer<Void> onAccumulatedMetrics;
  external Pointer<Void> onInsight;
  external Pointer<NativeFunction<NativeVideoOutputCb>> onVideoOutput;
}

// Function typedefs
typedef _PreconfigureC =
    Int32 Function(
      Pointer<Utf8> dir,
      Pointer<Utf8> devId,
      Pointer<SmartSpectraError> err,
    );
typedef PreconfigureFunction =
    int Function(
      Pointer<Utf8> dir,
      Pointer<Utf8> devId,
      Pointer<SmartSpectraError> err,
    );

typedef _SessionCreateC =
    Pointer<SmartSpectraSession> Function(
      Pointer<SmartSpectraConfig> cfg,
      UintPtr handle,
      Pointer<SmartSpectraCallbacks> cbs,
      Pointer<SmartSpectraError> err,
    );
typedef SessionCreateFunction =
    Pointer<SmartSpectraSession> Function(
      Pointer<SmartSpectraConfig> cfg,
      int handle,
      Pointer<SmartSpectraCallbacks> cbs,
      Pointer<SmartSpectraError> err,
    );

typedef _SessionStartCameraC =
    Int32 Function(
      Pointer<SmartSpectraSession> sess,
      Pointer<SmartSpectraCameraOptions> opts,
      Pointer<SmartSpectraError> err,
    );
typedef SessionStartCameraFunction =
    int Function(
      Pointer<SmartSpectraSession> sess,
      Pointer<SmartSpectraCameraOptions> opts,
      Pointer<SmartSpectraError> err,
    );

typedef _SessionStartSelectedCameraC =
    Int32 Function(
      Pointer<SmartSpectraSession> sess,
      Int32 selectionKind,
      Pointer<Utf8> cameraId,
      Pointer<Void> opts,
      Pointer<SmartSpectraError> err,
    );
typedef SessionStartSelectedCameraFunction =
    int Function(
      Pointer<SmartSpectraSession> sess,
      int selectionKind,
      Pointer<Utf8> cameraId,
      Pointer<Void> opts,
      Pointer<SmartSpectraError> err,
    );

typedef _SessionStopC = Void Function(Pointer<SmartSpectraSession> sess);
typedef SessionStopFunction = void Function(Pointer<SmartSpectraSession> sess);

typedef _SessionDestroyC = Void Function(Pointer<SmartSpectraSession> sess);
typedef SessionDestroyFunction =
    void Function(Pointer<SmartSpectraSession> sess);

class SmartSpectraFfiBindings {
  SmartSpectraFfiBindings(DynamicLibrary lib) {
    preconfigure = lib.lookupFunction<_PreconfigureC, PreconfigureFunction>(
      'smartspectra_preconfigure',
    );
    sessionCreate = lib.lookupFunction<_SessionCreateC, SessionCreateFunction>(
      'smartspectra_session_create',
    );
    sessionStartCamera = lib
        .lookupFunction<_SessionStartCameraC, SessionStartCameraFunction>(
          'smartspectra_session_start_camera',
        );
    sessionStartSelectedCamera = lib
        .lookupFunction<
          _SessionStartSelectedCameraC,
          SessionStartSelectedCameraFunction
        >('smartspectra_session_start_selected_camera');
    sessionStop = lib.lookupFunction<_SessionStopC, SessionStopFunction>(
      'smartspectra_session_stop',
    );
    sessionDestroy = lib
        .lookupFunction<_SessionDestroyC, SessionDestroyFunction>(
          'smartspectra_session_destroy',
        );
  }

  late final PreconfigureFunction preconfigure;
  late final SessionCreateFunction sessionCreate;
  late final SessionStartCameraFunction sessionStartCamera;
  late final SessionStartSelectedCameraFunction sessionStartSelectedCamera;
  late final SessionStopFunction sessionStop;
  late final SessionDestroyFunction sessionDestroy;
}

typedef _SetVideoListenerC = Void Function(Pointer<Void> listener);
typedef SetVideoListenerFunction = void Function(Pointer<Void> listener);
typedef _FreeVideoFrameC = Void Function(Pointer<Uint8> data);
typedef FreeVideoFrameFunction = void Function(Pointer<Uint8> data);
typedef _SetCallbackListenerC = Void Function(Pointer<Void> listener);
typedef SetCallbackListenerFunction = void Function(Pointer<Void> listener);

/// Runner relays keep SDK callback buffers alive until Dart's asynchronous
/// listeners have copied them.
class SmartSpectraCallbackRelayBindings {
  SmartSpectraCallbackRelayBindings(DynamicLibrary process)
    : setVideoListener = process
          .lookupFunction<_SetVideoListenerC, SetVideoListenerFunction>(
            'pretra_set_video_output_listener',
          ),
      setMetricsListener = process
          .lookupFunction<_SetCallbackListenerC, SetCallbackListenerFunction>(
            'pretra_set_metrics_listener',
          ),
      setValidationListener = process
          .lookupFunction<_SetCallbackListenerC, SetCallbackListenerFunction>(
            'pretra_set_validation_listener',
          ),
      setErrorListener = process
          .lookupFunction<_SetCallbackListenerC, SetCallbackListenerFunction>(
            'pretra_set_error_listener',
          ),
      freeFrame = process
          .lookupFunction<_FreeVideoFrameC, FreeVideoFrameFunction>(
            'pretra_free_video_frame',
          ),
      videoOutputCallback = process.lookup<NativeFunction<NativeVideoOutputCb>>(
        'pretra_video_output_relay',
      ),
      metricsCallback = process.lookup<NativeFunction<NativeMetricsCb>>(
        'pretra_metrics_relay',
      ),
      validationCallback = process.lookup<NativeFunction<NativeValidationCb>>(
        'pretra_validation_relay',
      ),
      errorCallback = process.lookup<NativeFunction<NativeErrorCb>>(
        'pretra_error_relay',
      );

  final SetVideoListenerFunction setVideoListener;
  final SetCallbackListenerFunction setMetricsListener;
  final SetCallbackListenerFunction setValidationListener;
  final SetCallbackListenerFunction setErrorListener;
  final FreeVideoFrameFunction freeFrame;
  final Pointer<NativeFunction<NativeVideoOutputCb>> videoOutputCallback;
  final Pointer<NativeFunction<NativeMetricsCb>> metricsCallback;
  final Pointer<NativeFunction<NativeValidationCb>> validationCallback;
  final Pointer<NativeFunction<NativeErrorCb>> errorCallback;
}
