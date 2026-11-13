// lib/src/engine/lighting_recovery_engine.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../ffi/smartspectra_bridge.dart';

enum RecoveryPromptState {
  hidden,
  lowLightWarning,
  repositionGuidance,
  generalInterruption,
}

class LightingRecoveryEngine extends ChangeNotifier {
  LightingRecoveryEngine({required Stream<QualityControlEvent> qcStream}) {
    _subscription = qcStream.listen(_processQcEvent);
  }

  late final StreamSubscription<QualityControlEvent> _subscription;

  RecoveryPromptState _promptState = RecoveryPromptState.hidden;
  RecoveryPromptState get promptState => _promptState;

  String _guidanceMessage = '';
  String get guidanceMessage => _guidanceMessage;

  // Keep the most recent SDK quality state even before the overlay's
  // consecutive-event threshold is reached. The session panel can then explain
  // why a metric is waiting without showing a stale generic warm-up message.
  QualityControlStatus? _latestQualityStatus;
  QualityControlStatus? get latestQualityStatus => _latestQualityStatus;

  int _consecutiveFailures = 0;
  int _consecutiveSuccesses = 0;

  static const int _activationThreshold = 3;
  static const int _recoveryThreshold = 4;

  void _processQcEvent(QualityControlEvent event) {
    _latestQualityStatus = event.status;
    if (event.status == QualityControlStatus.optimal) {
      _consecutiveSuccesses++;
      _consecutiveFailures = 0;

      if (_consecutiveSuccesses >= _recoveryThreshold &&
          _promptState != RecoveryPromptState.hidden) {
        _setPrompt(RecoveryPromptState.hidden, '');
      }
    } else {
      _consecutiveFailures++;
      _consecutiveSuccesses = 0;

      if (_consecutiveFailures >= _activationThreshold) {
        switch (event.status) {
          case QualityControlStatus.tooDark:
            _setPrompt(
              RecoveryPromptState.lowLightWarning,
              'Lighting is too dim for camera pulse sensing. Please brighten your room or face your desk lamp.',
            );
            break;
          case QualityControlStatus.tooBright:
            _setPrompt(
              RecoveryPromptState.lowLightWarning,
              'Direct glare detected on face. Please soften overhead or back lighting.',
            );
            break;
          case QualityControlStatus.noFace:
          case QualityControlStatus.offCenter:
            _setPrompt(
              RecoveryPromptState.repositionGuidance,
              'Align your face within the camera frame.',
            );
            break;
          case QualityControlStatus.chestNotVisible:
            _setPrompt(
              RecoveryPromptState.repositionGuidance,
              'Ensure upper chest is visible to track natural breathing expansion.',
            );
            break;
          default:
            _setPrompt(
              RecoveryPromptState.generalInterruption,
              event.status.userGuidance,
            );
        }
      }
    }
  }

  void _setPrompt(RecoveryPromptState state, String message) {
    if (_promptState != state || _guidanceMessage != message) {
      _promptState = state;
      _guidanceMessage = message;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
