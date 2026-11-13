import assert from 'node:assert/strict';
import test from 'node:test';

import { HRV_MIN_SESSION_MS, SignalEngine } from '../src/renderer/signals/engine.mjs';

const T0 = 1_000_000;
const toMicros = (ms) => ms * 1000;

function measurement(value, { confidence = 60, stable = true, at = T0 } = {}) {
  return { value, confidence, stable, timestamp: toMicros(at) };
}

function hrv(rmssd, { confidence = 60, stable = true, at = T0 } = {}) {
  return { rmssd, confidence, stable, timestamp: toMicros(at) };
}

function createEngine() {
  return new SignalEngine({ now: () => T0, staleMs: 7000 });
}

test('ingests stable breathing and pulse measurements', () => {
  const engine = createEngine();
  engine.startSession(T0);
  engine.ingestMetrics({
    breathing: { rate: [measurement(15)] },
    cardio: { pulseRate: [measurement(70)] },
  }, T0);

  const snapshot = engine.getSnapshot(T0);
  assert.equal(snapshot.breathing.value, 15);
  assert.equal(snapshot.breathing.valid, true);
  assert.equal(snapshot.breathing.confidence, 60);
  assert.equal(snapshot.pulse.value, 70);
  assert.equal(snapshot.pulse.valid, true);
  assert.equal(snapshot.hasSignal, true);
  assert.equal(snapshot.hasVisualSignal, true);
  assert.equal(snapshot.durationMs, 0);
});

test('requires the stable confidence threshold for valid values', () => {
  const engine = createEngine();
  engine.startSession(T0);
  engine.ingestMetrics({
    breathing: { rate: [measurement(15, { confidence: 44 })] },
  }, T0);

  const snapshot = engine.getSnapshot(T0);
  assert.equal(snapshot.breathing.valid, false);
  assert.equal(snapshot.breathing.value, null);
  assert.equal(snapshot.breathing.visualValue, 15);
  assert.equal(snapshot.breathing.stable, false);
});

test('gates out-of-range values while keeping a visual signal', () => {
  const engine = createEngine();
  engine.startSession(T0);
  engine.ingestMetrics({
    breathing: { rate: [measurement(55)] },
  }, T0);

  const snapshot = engine.getSnapshot(T0);
  assert.equal(snapshot.breathing.valid, false);
  assert.equal(snapshot.breathing.value, null);
  assert.equal(snapshot.breathing.visualValue, 55);
  assert.equal(snapshot.breathing.visualNormalized, 1);
});

test('marks metrics stale after the freshness window', () => {
  const engine = createEngine();
  engine.startSession(T0);
  engine.ingestMetrics({
    breathing: { rate: [measurement(15)] },
  }, T0);

  const snapshot = engine.getSnapshot(T0 + 8000);
  assert.equal(snapshot.breathing.fresh, false);
  assert.equal(snapshot.breathing.valid, false);
  assert.equal(snapshot.breathing.visualValue, null);
  assert.equal(snapshot.hasSignal, false);
  assert.equal(snapshot.hasVisualSignal, false);
});

test('keeps normalized trace history for the landscape', () => {
  const engine = createEngine();
  engine.startSession(T0);
  engine.ingestMetrics({
    breathing: {
      upperTrace: [
        { value: 10 },
        { value: 20 },
        { value: 30 },
      ],
    },
    cardio: {
      arterialPressureTrace: [
        { value: 4 },
        { value: 8 },
      ],
    },
  }, T0);

  const snapshot = engine.getSnapshot(T0);
  assert.deepEqual(snapshot.traces.breathing, [0, 0.5, 1]);
  assert.deepEqual(snapshot.traces.pulse, [0, 1]);
});

test('summarizes stable samples and withholds HRV until 60 seconds', () => {
  const engine = createEngine();
  engine.startSession(T0);
  engine.ingestMetrics({
    breathing: { rate: [measurement(15), measurement(17)] },
    cardio: {
      pulseRate: [measurement(70), measurement(74)],
      hrv: [hrv(42)],
    },
  }, T0);

  const early = engine.getSummary(T0 + HRV_MIN_SESSION_MS - 1);
  assert.equal(early.breathingAvg, 16);
  assert.equal(early.pulseAvg, 72);
  assert.equal(early.hrvEligible, false);
  assert.equal(early.hrvRmssd, null);

  engine.ingestMetrics({
    cardio: { hrv: [hrv(42, { at: T0 + HRV_MIN_SESSION_MS })] },
  }, T0 + HRV_MIN_SESSION_MS);

  const eligible = engine.getSummary(T0 + HRV_MIN_SESSION_MS);
  assert.equal(eligible.hrvEligible, true);
  assert.equal(eligible.hrvRmssd, 42);
  assert.equal(eligible.hasData, true);
});

test('returns a quiet snapshot before any measurements', () => {
  const engine = createEngine();
  engine.startSession(T0);

  const snapshot = engine.getSnapshot(T0 + 1000);
  assert.equal(snapshot.breathing.value, null);
  assert.equal(snapshot.pulse.value, null);
  assert.equal(snapshot.hrv.value, null);
  assert.equal(snapshot.hasSignal, false);
  assert.equal(snapshot.durationMs, 1000);
  assert.deepEqual(snapshot.traces.breathing, []);
  assert.deepEqual(snapshot.traces.pulse, []);
});

test('reset clears session data', () => {
  const engine = createEngine();
  engine.startSession(T0);
  engine.ingestMetrics({ breathing: { rate: [measurement(15)] } }, T0);
  engine.reset();

  const snapshot = engine.getSnapshot(T0);
  assert.equal(snapshot.breathing.value, null);
  assert.equal(snapshot.durationMs, 0);
  assert.equal(snapshot.hasSignal, false);
});
