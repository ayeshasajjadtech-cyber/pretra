import 'dart:async';
import 'dart:math' as math;

import 'models.dart';
import 'source_events.dart';

const int simulatedTickMs = 250;
const int simulatedStartingStatus = 2;
const int simulatedRunningStatus = 3;

class SimulatedSource {
  SimulatedSource({
    this.onMetrics,
    this.onStatus,
    this.onValidation,
    this.onError,
  });

  final MetricsCallback? onMetrics;
  final StatusCallback? onStatus;
  final ValidationCallback? onValidation;
  final SourceErrorCallback? onError;

  Timer? _tickTimer;
  Timer? _statusTimer;
  int _startedAtMs = 0;
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _startedAtMs = DateTime.now().millisecondsSinceEpoch;
    onStatus?.call(simulatedStartingStatus);
    _statusTimer = Timer(const Duration(milliseconds: 800), () {
      if (!_running) return;
      onStatus?.call(simulatedRunningStatus);
      onValidation?.call(
        0,
        '',
        DateTime.now().millisecondsSinceEpoch * 1000,
      );
    });
    _tickTimer = Timer.periodic(
      const Duration(milliseconds: simulatedTickMs),
      (_) => _tick(),
    );
  }

  Future<void> stop() async {
    _running = false;
    _statusTimer?.cancel();
    _tickTimer?.cancel();
    _statusTimer = null;
    _tickTimer = null;
  }

  Future<void> dispose() async {
    await stop();
  }

  void _tick() {
    if (!_running) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final seconds = (nowMs - _startedAtMs) / 1000;
    final confidence = 78 + math.sin(seconds / 4) * 8;
    final timestampUs = nowMs * 1000;

    final breathing = 14.5 +
        math.sin(seconds / 3.2) * 3 +
        math.sin(seconds / 7.4) * 1.2;
    final pulse = 68 +
        math.sin(seconds / 2.1) * 7 +
        math.sin(seconds / 0.83) * 2.5;

    final breathingTrace = <MeasurementSample>[];
    for (var i = 5; i >= 0; i--) {
      final traceSeconds = seconds - i * (simulatedTickMs / 1000);
      breathingTrace.add(
        MeasurementSample(
          value: math.sin(traceSeconds / 2.4),
          timestampUs: timestampUs - i * simulatedTickMs * 1000,
        ),
      );
    }

    final pulseTrace = <MeasurementSample>[];
    for (var i = 5; i >= 0; i--) {
      final traceSeconds = seconds - i * (simulatedTickMs / 1000);
      pulseTrace.add(
        MeasurementSample(
          value: math.sin(traceSeconds / 0.9) * 0.8,
          confidence: confidence,
          stable: true,
          timestampUs: timestampUs - i * simulatedTickMs * 1000,
        ),
      );
    }

    final hrv = <HrvSample>[];
    if (seconds >= 60) {
      hrv.add(
        HrvSample(
          rmssd: 42 + math.sin(seconds / 11) * 5,
          confidence: confidence,
          stable: true,
          timestampUs: timestampUs,
        ),
      );
    }

    onMetrics?.call(
      DecodedMetrics(
        breathingRate: <MeasurementSample>[
          MeasurementSample(
            value: breathing,
            confidence: confidence,
            stable: true,
            timestampUs: timestampUs,
          ),
        ],
        breathingTrace: breathingTrace,
        pulseRate: <MeasurementSample>[
          MeasurementSample(
            value: pulse,
            confidence: confidence,
            stable: true,
            timestampUs: timestampUs,
          ),
        ],
        pulseTrace: pulseTrace,
        hrv: hrv,
      ),
      nowMs,
    );
  }
}
