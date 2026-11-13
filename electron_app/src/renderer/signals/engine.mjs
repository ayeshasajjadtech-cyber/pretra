import {
  DEFAULT_STALE_MS,
  ema,
  isFresh,
  normalizeRange,
  toNumber,
} from './smoothing.mjs';

export const BREATHING_RANGE = Object.freeze({ min: 5, max: 40 });
export const PULSE_RANGE = Object.freeze({ min: 40, max: 110 });
export const HRV_MIN_SESSION_MS = 60_000;

const STABLE_CONFIDENCE = Object.freeze({
  breathing: 45,
  pulse: 40,
  hrv: 50,
});

const HISTORY_LIMIT = 48;
const SUMMARY_LIMIT = 20_000;
const TRACE_LIMIT = 220;

function createMetricState() {
  return {
    last: null,
    smoothed: null,
    history: [],
    stableHistory: [],
  };
}

function average(values) {
  if (!values.length) return null;
  let sum = 0;
  for (const value of values) sum += value;
  return Math.round((sum / values.length) * 10) / 10;
}

function normalizeSeries(values) {
  if (values.length === 0) return [];
  let min = Infinity;
  let max = -Infinity;
  for (const value of values) {
    if (value < min) min = value;
    if (value > max) max = value;
  }
  const span = max - min;
  return values.map((value) => (span === 0 ? 0.5 : (value - min) / span));
}

export class SignalEngine {
  constructor({ now = () => Date.now(), staleMs = DEFAULT_STALE_MS } = {}) {
    this.now = now;
    this.staleMs = staleMs;
    this.sessionStartedAt = null;
    this.lastIngestAt = null;
    this.metrics = {
      breathing: createMetricState(),
      pulse: createMetricState(),
      hrv: createMetricState(),
    };
    this.traces = {
      breathingTrace: [],
      pulseTrace: [],
    };
  }

  reset() {
    this.sessionStartedAt = null;
    this.lastIngestAt = null;
    this.metrics = {
      breathing: createMetricState(),
      pulse: createMetricState(),
      hrv: createMetricState(),
    };
    this.traces = {
      breathingTrace: [],
      pulseTrace: [],
    };
  }

  startSession(now = this.now()) {
    this.reset();
    this.sessionStartedAt = now;
  }

  ingestMetrics(decoded, receivedAt = this.now()) {
    if (!decoded || typeof decoded !== 'object') return;

    const breathing = decoded.breathing;
    const cardio = decoded.cardio;

    if (Array.isArray(breathing?.rate)) {
      this._ingestMeasurements('breathing', breathing.rate, receivedAt);
    }

    if (Array.isArray(cardio?.pulseRate)) {
      this._ingestMeasurements('pulse', cardio.pulseRate, receivedAt);
    }

    if (Array.isArray(cardio?.hrv)) {
      this._ingestHrv(cardio.hrv, receivedAt);
    }

    const breathingTrace = Array.isArray(breathing?.upperTrace) && breathing.upperTrace.length
      ? breathing.upperTrace
      : breathing?.lowerTrace;
    if (Array.isArray(breathingTrace)) {
      this._ingestTrace('breathingTrace', breathingTrace);
    }

    if (Array.isArray(cardio?.arterialPressureTrace)) {
      this._ingestTrace('pulseTrace', cardio.arterialPressureTrace);
    }

    this.lastIngestAt = receivedAt;
  }

  getSnapshot(now = this.now()) {
    const breathing = this._metricSnapshot('breathing', now, BREATHING_RANGE);
    const pulse = this._metricSnapshot('pulse', now, PULSE_RANGE);
    const hrv = this._hrvSnapshot(now);
    const durationMs = this.sessionStartedAt === null
      ? 0
      : Math.max(0, now - this.sessionStartedAt);

    return {
      breathing,
      pulse,
      hrv,
      traces: {
        breathing: normalizeSeries(this.traces.breathingTrace),
        pulse: normalizeSeries(this.traces.pulseTrace),
      },
      durationMs,
      hasSignal: breathing.valid || pulse.valid,
      hasVisualSignal: breathing.visualValue !== null || pulse.visualValue !== null,
    };
  }

  getVisualState(now = this.now()) {
    const snapshot = this.getSnapshot(now);
    const confidence = Math.max(snapshot.breathing.confidence, snapshot.pulse.confidence);

    return {
      active: snapshot.hasSignal || snapshot.hasVisualSignal,
      breathing: snapshot.breathing.visualNormalized ?? snapshot.breathing.normalized,
      pulse: snapshot.pulse.visualNormalized ?? snapshot.pulse.normalized,
      breathingRate: snapshot.breathing.value ?? snapshot.breathing.visualValue,
      pulseRate: snapshot.pulse.value ?? snapshot.pulse.visualValue,
      confidence,
      stale: !snapshot.breathing.fresh && !snapshot.pulse.fresh,
      traces: snapshot.traces,
    };
  }

  getSummary(now = this.now()) {
    const durationMs = this.sessionStartedAt === null
      ? 0
      : Math.max(0, now - this.sessionStartedAt);

    const breathingAvg = average(this.metrics.breathing.stableHistory.filter(
      (value) => value >= BREATHING_RANGE.min && value <= BREATHING_RANGE.max,
    ));
    const pulseAvg = average(this.metrics.pulse.stableHistory.filter(
      (value) => value >= PULSE_RANGE.min && value <= PULSE_RANGE.max,
    ));
    const hrvEligible = durationMs >= HRV_MIN_SESSION_MS;
    const hrvRmssd = hrvEligible ? average(this.metrics.hrv.stableHistory) : null;

    return {
      durationMs,
      breathingAvg,
      pulseAvg,
      hrvRmssd,
      hrvEligible,
      sampleCounts: {
        breathing: this.metrics.breathing.stableHistory.length,
        pulse: this.metrics.pulse.stableHistory.length,
        hrv: this.metrics.hrv.stableHistory.length,
      },
      hasData: breathingAvg !== null || pulseAvg !== null || hrvRmssd !== null,
    };
  }

  _ingestMeasurements(kind, samples, receivedAt) {
    const state = this.metrics[kind];
    const threshold = STABLE_CONFIDENCE[kind];

    for (const sample of samples) {
      const value = toNumber(sample?.value);
      if (value === null) continue;

      const confidence = toNumber(sample?.confidence) ?? 0;
      const timestampUs = toNumber(sample?.timestamp);
      const timestampMs = timestampUs === null ? receivedAt : Math.round(timestampUs / 1000);
      const stable = sample?.stable === true
        || (sample?.stable == null && confidence >= threshold);

      state.last = {
        value,
        confidence,
        stable,
        timestampMs,
      };
      state.smoothed = ema(state.smoothed, value, 0.2);
      state.history.push({ value, confidence, stable, timestampMs });
      if (state.history.length > HISTORY_LIMIT) state.history.shift();

      if (stable && confidence >= threshold) {
        state.stableHistory.push(value);
        if (state.stableHistory.length > SUMMARY_LIMIT) state.stableHistory.shift();
      }
    }
  }

  _ingestHrv(samples, receivedAt) {
    const state = this.metrics.hrv;
    const threshold = STABLE_CONFIDENCE.hrv;

    for (const sample of samples) {
      const value = toNumber(sample?.rmssd);
      if (value === null) continue;

      const confidence = toNumber(sample?.confidence) ?? 0;
      const timestampUs = toNumber(sample?.timestamp);
      const timestampMs = timestampUs === null ? receivedAt : Math.round(timestampUs / 1000);
      const stable = sample?.stable === true
        || (sample?.stable == null && confidence >= threshold);

      state.last = {
        value,
        confidence,
        stable,
        timestampMs,
      };

      if (stable && confidence >= threshold) {
        state.stableHistory.push(value);
        if (state.stableHistory.length > SUMMARY_LIMIT) state.stableHistory.shift();
      }
    }
  }

  _ingestTrace(kind, samples) {
    const target = this.traces[kind];
    for (const sample of samples) {
      const value = toNumber(sample?.value);
      if (value !== null) target.push(value);
    }
    if (target.length > TRACE_LIMIT) target.splice(0, target.length - TRACE_LIMIT);
  }

  _metricSnapshot(kind, now, range) {
    const state = this.metrics[kind];
    const last = state.last;
    const threshold = STABLE_CONFIDENCE[kind];
    const fresh = Boolean(last) && isFresh(last.timestampMs, now, this.staleMs);
    const confidence = last?.confidence ?? 0;
    const stable = Boolean(last?.stable) && confidence >= threshold;
    const inRange = Boolean(last)
      && last.value >= range.min
      && last.value <= range.max;
    const valid = fresh && stable && inRange;
    const visualValue = fresh && confidence >= 20 ? state.smoothed : null;
    const value = valid ? state.smoothed : null;

    return {
      value,
      visualValue,
      rawValue: last?.value ?? null,
      confidence,
      stable,
      fresh,
      valid,
      ageMs: last ? Math.max(0, now - last.timestampMs) : null,
      threshold,
      normalized: value === null ? null : normalizeRange(value, range.min, range.max),
      visualNormalized: visualValue === null ? null : normalizeRange(visualValue, range.min, range.max),
      sparkline: state.history
        .filter((entry) => entry.stable && entry.confidence >= threshold)
        .map((entry) => normalizeRange(entry.value, range.min, range.max))
        .filter((entry) => entry !== null)
        .slice(-40),
    };
  }

  _hrvSnapshot(now) {
    const state = this.metrics.hrv;
    const last = state.last;
    const fresh = Boolean(last) && isFresh(last.timestampMs, now, this.staleMs);
    const confidence = last?.confidence ?? 0;
    const stable = Boolean(last?.stable) && confidence >= STABLE_CONFIDENCE.hrv;
    const durationMs = this.sessionStartedAt === null
      ? 0
      : Math.max(0, now - this.sessionStartedAt);
    const eligible = durationMs >= HRV_MIN_SESSION_MS;
    const valid = eligible && fresh && stable;

    return {
      value: valid ? last.value : null,
      confidence,
      stable,
      fresh,
      eligible,
      ageMs: last ? Math.max(0, now - last.timestampMs) : null,
      threshold: STABLE_CONFIDENCE.hrv,
    };
  }
}
