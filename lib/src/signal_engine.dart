import 'dart:math' as math;

import 'models.dart';
import 'smoothing.dart';

const double breathingMin = 5;
const double breathingMax = 40;
const double pulseMin = 40;
const double pulseMax = 110;
const int hrvMinSessionMs = 60000;

const double breathingStableConfidence = 45;
const double pulseStableConfidence = 40;
const double hrvStableConfidence = 50;

const int historyLimit = 48;
const int summaryLimit = 20000;
const int engineTraceLimit = 220;
const double engineEmaAlpha = 0.2;

class _LastSample {
  const _LastSample({
    required this.value,
    required this.confidence,
    required this.stable,
    required this.timestampMs,
  });

  final double value;
  final double confidence;
  final bool stable;
  final int timestampMs;
}

class _HistorySample {
  const _HistorySample({
    required this.value,
    required this.confidence,
    required this.stable,
    required this.timestampMs,
  });

  final double value;
  final double confidence;
  final bool stable;
  final int timestampMs;
}

class _MetricState {
  _LastSample? last;
  double? smoothed;
  final List<_HistorySample> history = <_HistorySample>[];
  final List<double> stableHistory = <double>[];
}

class SignalEngine {
  SignalEngine({int Function()? now, this.staleMs = defaultStaleMs})
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _now;
  final int staleMs;

  int? _sessionStartedAt;
  int? _lastIngestAt;
  final _MetricState _breathing = _MetricState();
  final _MetricState _pulse = _MetricState();
  final _MetricState _hrv = _MetricState();
  final List<double> _breathingTrace = <double>[];
  final List<double> _pulseTrace = <double>[];

  void reset() {
    _sessionStartedAt = null;
    _lastIngestAt = null;
    _resetMetric(_breathing);
    _resetMetric(_pulse);
    _resetMetric(_hrv);
    _breathingTrace.clear();
    _pulseTrace.clear();
  }

  void startSession([int? now]) {
    reset();
    _sessionStartedAt = now ?? _now();
  }

  void ingestMetrics(DecodedMetrics decoded, [int? receivedAt]) {
    final at = receivedAt ?? _now();
    _ingestMeasurements(
      _breathing,
      decoded.breathingRate,
      at,
      breathingStableConfidence,
      breathingMin,
      breathingMax,
    );
    _ingestMeasurements(
      _pulse,
      decoded.pulseRate,
      at,
      pulseStableConfidence,
      pulseMin,
      pulseMax,
    );
    _ingestHrv(decoded.hrv, at);

    final breathingTrace = decoded.breathingTrace.isNotEmpty
        ? decoded.breathingTrace
        : const <MeasurementSample>[];
    _ingestTrace(_breathingTrace, breathingTrace);
    _ingestTrace(_pulseTrace, decoded.pulseTrace);
    _lastIngestAt = at;
  }

  EngineSnapshot getSnapshot([int? now]) {
    final at = now ?? _now();
    final breathing = _metricSnapshot(
      _breathing,
      at,
      breathingMin,
      breathingMax,
      breathingStableConfidence,
    );
    final pulse = _metricSnapshot(
      _pulse,
      at,
      pulseMin,
      pulseMax,
      pulseStableConfidence,
    );
    final hrv = _hrvSnapshot(at);
    final durationMs =
        _sessionStartedAt == null ? 0 : math.max(0, at - _sessionStartedAt!);

    return EngineSnapshot(
      breathing: breathing,
      pulse: pulse,
      hrv: hrv,
      traces: TraceSet(
        breathing: _normalizeSeries(_breathingTrace),
        pulse: _normalizeSeries(_pulseTrace),
      ),
      durationMs: durationMs,
      hasSignal: breathing.valid || pulse.valid,
      hasVisualSignal:
          breathing.visualValue != null || pulse.visualValue != null,
    );
  }

  VisualState getVisualState([int? now]) {
    final snapshot = getSnapshot(now);
    final confidence = math.max(
      snapshot.breathing.confidence,
      snapshot.pulse.confidence,
    );

    return VisualState(
      active: snapshot.hasSignal || snapshot.hasVisualSignal,
      breathing:
          snapshot.breathing.visualNormalized ?? snapshot.breathing.normalized,
      pulse: snapshot.pulse.visualNormalized ?? snapshot.pulse.normalized,
      breathingRate:
          snapshot.breathing.value ?? snapshot.breathing.visualValue,
      pulseRate: snapshot.pulse.value ?? snapshot.pulse.visualValue,
      confidence: confidence,
      stale: !snapshot.breathing.fresh && !snapshot.pulse.fresh,
      traces: snapshot.traces,
    );
  }

  SessionSummary getSummary([int? now, bool simulated = false]) {
    final at = now ?? _now();
    final durationMs =
        _sessionStartedAt == null ? 0 : math.max(0, at - _sessionStartedAt!);

    final breathingAvg = _average(
      _breathing.stableHistory.where(
        (value) => value >= breathingMin && value <= breathingMax,
      ),
    );
    final pulseAvg = _average(
      _pulse.stableHistory.where(
        (value) => value >= pulseMin && value <= pulseMax,
      ),
    );
    final hrvEligible = durationMs >= hrvMinSessionMs;
    final hrvRmssd =
        hrvEligible ? _average(_hrv.stableHistory) : null;

    return SessionSummary(
      durationMs: durationMs,
      breathingAvg: breathingAvg,
      pulseAvg: pulseAvg,
      hrvRmssd: hrvRmssd,
      hrvEligible: hrvEligible,
      sampleCounts: <String, int>{
        'breathing': _breathing.stableHistory.length,
        'pulse': _pulse.stableHistory.length,
        'hrv': _hrv.stableHistory.length,
      },
      hasData:
          breathingAvg != null || pulseAvg != null || hrvRmssd != null,
      simulated: simulated,
    );
  }

  int? get lastIngestAt => _lastIngestAt;

  void _resetMetric(_MetricState state) {
    state.last = null;
    state.smoothed = null;
    state.history.clear();
    state.stableHistory.clear();
  }

  void _ingestMeasurements(
    _MetricState state,
    List<MeasurementSample> samples,
    int receivedAt,
    double threshold,
    double min,
    double max,
  ) {
    for (final sample in samples) {
      final value = sample.value;
      if (value == null || !value.isFinite) continue;

      final confidence = _finiteOrZero(sample.confidence);
      final timestampMs = sample.timestampUs == null
          ? receivedAt
          : (sample.timestampUs! / 1000).round();
      final stable = sample.stable == true ||
          (sample.stable == null && confidence >= threshold);

      state.last = _LastSample(
        value: value,
        confidence: confidence,
        stable: stable,
        timestampMs: timestampMs,
      );
      final accepted = stable &&
          confidence >= threshold &&
          value >= min &&
          value <= max;
      if (accepted) {
        state.smoothed = ema(state.smoothed, value, engineEmaAlpha);
      }
      state.history.add(
        _HistorySample(
          value: value,
          confidence: confidence,
          stable: stable,
          timestampMs: timestampMs,
        ),
      );
      if (state.history.length > historyLimit) {
        state.history.removeAt(0);
      }

      if (accepted) {
        state.stableHistory.add(value);
        if (state.stableHistory.length > summaryLimit) {
          state.stableHistory.removeAt(0);
        }
      }
    }
  }

  void _ingestHrv(List<HrvSample> samples, int receivedAt) {
    for (final sample in samples) {
      final value = sample.rmssd;
      if (value == null || !value.isFinite) continue;

      final confidence = _finiteOrZero(sample.confidence);
      final timestampMs = sample.timestampUs == null
          ? receivedAt
          : (sample.timestampUs! / 1000).round();
      final stable = sample.stable == true ||
          (sample.stable == null && confidence >= hrvStableConfidence);

      _hrv.last = _LastSample(
        value: value,
        confidence: confidence,
        stable: stable,
        timestampMs: timestampMs,
      );

      if (stable && confidence >= hrvStableConfidence) {
        _hrv.stableHistory.add(value);
        if (_hrv.stableHistory.length > summaryLimit) {
          _hrv.stableHistory.removeAt(0);
        }
      }
    }
  }

  void _ingestTrace(List<double> target, List<MeasurementSample> samples) {
    for (final sample in samples) {
      final value = sample.value;
      if (value != null && value.isFinite) {
        target.add(value);
      }
    }
    if (target.length > engineTraceLimit) {
      target.removeRange(0, target.length - engineTraceLimit);
    }
  }

  MetricSnapshot _metricSnapshot(
    _MetricState state,
    int now,
    double min,
    double max,
    double threshold,
  ) {
    final last = state.last;
    final fresh =
        last != null && isFresh(last.timestampMs, now, staleMs);
    final confidence = last?.confidence ?? 0;
    final stable = (last?.stable ?? false) && confidence >= threshold;
    final inRange =
        last != null && last.value >= min && last.value <= max;
    final valid = fresh && stable && inRange;
    final visualValue =
        fresh && confidence >= 20 ? state.smoothed : null;
    final value = valid ? state.smoothed : null;

    final sparkline = state.history
        .where((entry) => entry.stable && entry.confidence >= threshold)
        .map((entry) => normalizeRange(entry.value, min, max))
        .whereType<double>()
        .toList(growable: false);
    final tail = sparkline.length > 40
        ? sparkline.sublist(sparkline.length - 40)
        : sparkline;

    return MetricSnapshot(
      value: value,
      visualValue: visualValue,
      rawValue: last?.value,
      confidence: confidence,
      stable: stable,
      fresh: fresh,
      valid: valid,
      ageMs: last == null ? null : math.max(0, now - last.timestampMs),
      threshold: threshold,
      normalized: value == null ? null : normalizeRange(value, min, max),
      visualNormalized: visualValue == null
          ? null
          : normalizeRange(visualValue, min, max),
      sparkline: tail,
    );
  }

  HrvSnapshot _hrvSnapshot(int now) {
    final last = _hrv.last;
    final fresh =
        last != null && isFresh(last.timestampMs, now, staleMs);
    final confidence = last?.confidence ?? 0;
    final stable =
        (last?.stable ?? false) && confidence >= hrvStableConfidence;
    final durationMs =
        _sessionStartedAt == null ? 0 : math.max(0, now - _sessionStartedAt!);
    final eligible = durationMs >= hrvMinSessionMs;
    final valid = eligible && fresh && stable;

    return HrvSnapshot(
      value: valid ? last.value : null,
      confidence: confidence,
      stable: stable,
      fresh: fresh,
      eligible: eligible,
      ageMs: last == null ? null : math.max(0, now - last.timestampMs),
      threshold: hrvStableConfidence,
    );
  }

  static double _finiteOrZero(double? value) {
    if (value == null || !value.isFinite) return 0;
    return value;
  }

  static double? _average(Iterable<double> values) {
    var count = 0;
    var sum = 0.0;
    for (final value in values) {
      sum += value;
      count++;
    }
    if (count == 0) return null;
    return (sum / count * 10).round() / 10;
  }

  static List<double> _normalizeSeries(List<double> values) {
    if (values.isEmpty) return const <double>[];
    var min = double.infinity;
    var max = double.negativeInfinity;
    for (final value in values) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    final span = max - min;
    if (span == 0) return List<double>.filled(values.length, 0.5);
    return values
        .map((value) => (value - min) / span)
        .toList(growable: false);
  }
}
