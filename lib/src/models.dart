import 'dart:convert';

const List<int> breathingMetrics = <int>[0, 1, 2, 3, 4, 5, 6, 7];

const List<int> cardioMetrics = <int>[15, 16, 17];

class MeasurementSample {
  const MeasurementSample({
    required this.value,
    this.confidence,
    this.stable,
    this.timestampUs,
  });

  final double? value;
  final double? confidence;
  final bool? stable;
  final int? timestampUs;
}

class HrvSample {
  const HrvSample({
    required this.rmssd,
    this.confidence,
    this.stable,
    this.timestampUs,
  });

  final double? rmssd;
  final double? confidence;
  final bool? stable;
  final int? timestampUs;
}

class DecodedMetrics {
  const DecodedMetrics({
    this.breathingRate = const <MeasurementSample>[],
    this.breathingTrace = const <MeasurementSample>[],
    this.pulseRate = const <MeasurementSample>[],
    this.pulseTrace = const <MeasurementSample>[],
    this.hrv = const <HrvSample>[],
  });

  final List<MeasurementSample> breathingRate;
  final List<MeasurementSample> breathingTrace;
  final List<MeasurementSample> pulseRate;
  final List<MeasurementSample> pulseTrace;
  final List<HrvSample> hrv;
}

class MetricSnapshot {
  const MetricSnapshot({
    required this.value,
    required this.visualValue,
    required this.rawValue,
    required this.confidence,
    required this.stable,
    required this.fresh,
    required this.valid,
    required this.ageMs,
    required this.threshold,
    required this.normalized,
    required this.visualNormalized,
    required this.sparkline,
  });

  final double? value;
  final double? visualValue;
  final double? rawValue;
  final double confidence;
  final bool stable;
  final bool fresh;
  final bool valid;
  final int? ageMs;
  final double threshold;
  final double? normalized;
  final double? visualNormalized;
  final List<double> sparkline;
}

class HrvSnapshot {
  const HrvSnapshot({
    required this.value,
    required this.confidence,
    required this.stable,
    required this.fresh,
    required this.eligible,
    required this.ageMs,
    required this.threshold,
  });

  final double? value;
  final double confidence;
  final bool stable;
  final bool fresh;
  final bool eligible;
  final int? ageMs;
  final double threshold;
}

class TraceSet {
  const TraceSet({required this.breathing, required this.pulse});

  final List<double> breathing;
  final List<double> pulse;
}

class EngineSnapshot {
  const EngineSnapshot({
    required this.breathing,
    required this.pulse,
    required this.hrv,
    required this.traces,
    required this.durationMs,
    required this.hasSignal,
    required this.hasVisualSignal,
  });

  final MetricSnapshot breathing;
  final MetricSnapshot pulse;
  final HrvSnapshot hrv;
  final TraceSet traces;
  final int durationMs;
  final bool hasSignal;
  final bool hasVisualSignal;
}

class VisualState {
  const VisualState({
    required this.active,
    required this.breathing,
    required this.pulse,
    required this.breathingRate,
    required this.pulseRate,
    required this.confidence,
    required this.stale,
    required this.traces,
  });

  final bool active;
  final double? breathing;
  final double? pulse;
  final double? breathingRate;
  final double? pulseRate;
  final double confidence;
  final bool stale;
  final TraceSet traces;
}

class SessionSummary {
  const SessionSummary({
    required this.durationMs,
    required this.breathingAvg,
    required this.pulseAvg,
    required this.hrvRmssd,
    required this.hrvEligible,
    required this.sampleCounts,
    required this.hasData,
    required this.simulated,
  });

  final int durationMs;
  final double? breathingAvg;
  final double? pulseAvg;
  final double? hrvRmssd;
  final bool hrvEligible;
  final Map<String, int> sampleCounts;
  final bool hasData;
  final bool simulated;
}

class TelemetryPoint {
  const TelemetryPoint({
    required this.elapsedSec,
    required this.timestampIso,
    this.breathingRate,
    this.pulseRate,
    required this.signalQuality,
    required this.confidence,
  });

  final int elapsedSec;
  final String timestampIso;
  final double? breathingRate;
  final double? pulseRate;
  final double signalQuality;
  final double confidence;

  Map<String, Object?> toJson() => <String, Object?>{
    'elapsedSec': elapsedSec,
    'timestampIso': timestampIso,
    'breathingRate': breathingRate,
    'pulseRate': pulseRate,
    'signalQuality': signalQuality,
    'confidence': confidence,
  };

  static TelemetryPoint? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final elapsed = value['elapsedSec'];
    final ts = value['timestampIso'];
    if (elapsed is! num || ts is! String) return null;
    double? asDouble(Object? o) => o is num ? o.toDouble() : null;
    return TelemetryPoint(
      elapsedSec: elapsed.toInt(),
      timestampIso: ts,
      breathingRate: asDouble(value['breathingRate']),
      pulseRate: asDouble(value['pulseRate']),
      signalQuality: asDouble(value['signalQuality']) ?? 0.0,
      confidence: asDouble(value['confidence']) ?? 0.0,
    );
  }
}

class SavedSummary {
  const SavedSummary({
    required this.id,
    this.recordNumber = '',
    required this.savedAt,
    required this.durationMs,
    required this.breathingAvg,
    required this.pulseAvg,
    required this.hrvRmssd,
    required this.appVersion,
    this.signalQualityAvg,
    this.isLiveCamera = false,
    this.previewReceived = false,
    this.status = 'completed',
    this.sampleCount,
    this.telemetryPoints = const <TelemetryPoint>[],
  });

  final String id;

  /// Automatically assigned local record number. It does not identify a person.
  final String recordNumber;
  final DateTime savedAt;
  final int durationMs;
  final double? breathingAvg;
  final double? pulseAvg;
  final double? hrvRmssd;
  final String appVersion;
  final double? signalQualityAvg;
  final bool isLiveCamera;
  final bool previewReceived;
  final String status;
  final int? sampleCount;
  final List<TelemetryPoint> telemetryPoints;

  int get telemetryCount => sampleCount ?? telemetryPoints.length;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'recordNumber': recordNumber,
    'savedAt': savedAt.toIso8601String(),
    'durationMs': durationMs,
    'breathingAvg': breathingAvg,
    'pulseAvg': pulseAvg,
    'hrvRmssd': hrvRmssd,
    'appVersion': appVersion,
    'signalQualityAvg': signalQualityAvg,
    'isLiveCamera': isLiveCamera,
    'previewReceived': previewReceived,
    'status': status,
    'sampleCount': telemetryCount,
    'telemetryPoints': telemetryPoints
        .map((p) => p.toJson())
        .toList(growable: false),
  };

  static SavedSummary? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final id = value['id'];
    final savedAt = value['savedAt'];
    final durationMs = value['durationMs'];
    if (id is! String || savedAt is! String || durationMs is! num) {
      return null;
    }
    final parsed = DateTime.tryParse(savedAt);
    if (parsed == null) return null;

    double? asDouble(Object? number) =>
        number is num ? number.toDouble() : null;

    final rawPoints = value['telemetryPoints'];
    final points = rawPoints is List
        ? rawPoints
              .map(TelemetryPoint.fromJson)
              .whereType<TelemetryPoint>()
              .toList()
        : const <TelemetryPoint>[];
    final rawRecordNumber = value['recordNumber'] ?? value['participantId'];

    return SavedSummary(
      id: id,
      recordNumber: rawRecordNumber is String ? rawRecordNumber : '',
      savedAt: parsed,
      durationMs: durationMs.toInt(),
      breathingAvg: asDouble(value['breathingAvg']),
      pulseAvg: asDouble(value['pulseAvg']),
      hrvRmssd: asDouble(value['hrvRmssd']),
      appVersion: value['appVersion'] is String
          ? value['appVersion']! as String
          : '',
      signalQualityAvg: asDouble(value['signalQualityAvg']),
      isLiveCamera: value['isLiveCamera'] == true,
      previewReceived: value['previewReceived'] == true,
      status: value['status'] is String
          ? value['status']! as String
          : 'completed',
      sampleCount: value['sampleCount'] is num
          ? (value['sampleCount']! as num).toInt()
          : points.length,
      telemetryPoints: points,
    );
  }

  String encode() => jsonEncode(toJson());
}

class ValidationStatus {
  const ValidationStatus({
    required this.code,
    required this.hint,
    required this.timestampUs,
    required this.receivedAtMs,
  });

  final int code;
  final String hint;
  final int timestampUs;
  final int receivedAtMs;
}

class AppError {
  const AppError({
    required this.title,
    required this.message,
    required this.retryable,
    this.fatal = false,
    this.code,
  });

  final String title;
  final String message;
  final bool retryable;
  final bool fatal;
  final int? code;
}

class ValidationInfo {
  const ValidationInfo({
    required this.code,
    required this.message,
    required this.level,
  });

  final int code;
  final String message;
  final String level;
}

enum AppPhase { consent, starting, calibrating, active, stopping, summary }

const Set<AppPhase> livePhases = <AppPhase>{
  AppPhase.starting,
  AppPhase.calibrating,
  AppPhase.active,
  AppPhase.stopping,
};
