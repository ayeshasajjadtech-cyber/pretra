import 'dart:math' as math;

import 'models.dart';

const int defaultStaleMs = 7000;
const int traceLimit = 220;
const double defaultEmaAlpha = 0.22;

double clamp(double value, double min, double max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

double? ema(double? previous, double next, [double alpha = defaultEmaAlpha]) {
  if (!next.isFinite) return previous;
  if (previous == null || !previous.isFinite) return next;
  return previous + alpha * (next - previous);
}

double? normalizeRange(double? value, double min, double max) {
  if (value == null || !value.isFinite || !min.isFinite || !max.isFinite) {
    return null;
  }
  if (max <= min) return null;
  return clamp((value - min) / (max - min), 0, 1);
}

bool isFresh(int? timestampMs, int nowMs, int staleMs) {
  if (timestampMs == null) return false;
  final age = nowMs - timestampMs;
  return age >= 0 && age <= staleMs;
}

MeasurementSample? selectLatest(Iterable<MeasurementSample> samples) {
  MeasurementSample? latest;
  for (final sample in samples) {
    if (sample.value == null || !sample.value!.isFinite) continue;
    latest = sample;
  }
  return latest;
}

List<double> normalizeTrace(
  Iterable<MeasurementSample> samples, [
  int limit = traceLimit,
]) {
  final values = samples
      .map((sample) => sample.value)
      .whereType<double>()
      .where((value) => value.isFinite)
      .toList(growable: false);
  final tail = values.length > limit
      ? values.sublist(values.length - limit)
      : values;
  if (tail.isEmpty) return const <double>[];
  final min = tail.reduce(math.min);
  final max = tail.reduce(math.max);
  if (max == min) {
    return List<double>.filled(tail.length, 0.5);
  }
  return tail
      .map((value) => clamp((value - min) / (max - min), 0, 1))
      .toList(growable: false);
}
