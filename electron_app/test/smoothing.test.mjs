import assert from 'node:assert/strict';
import test from 'node:test';

import {
  clamp,
  ema,
  isFresh,
  normalizeRange,
  normalizeTrace,
  selectLatest,
  toNumber,
} from '../src/renderer/signals/smoothing.mjs';

test('clamp keeps values inside the range', () => {
  assert.equal(clamp(-2, 0, 10), 0);
  assert.equal(clamp(12, 0, 10), 10);
  assert.equal(clamp(5, 0, 10), 5);
});

test('ema returns the next value when there is no previous value', () => {
  assert.equal(ema(null, 12), 12);
  assert.equal(ema(Number.NaN, 12), 12);
});

test('ema smooths toward the next value', () => {
  const result = ema(10, 20, 0.25);
  assert.equal(result, 12.5);
  assert.equal(ema(10, Number.NaN, 0.25), 10);
});

test('normalizeRange clamps and rejects invalid ranges', () => {
  assert.equal(normalizeRange(25, 5, 45), 0.5);
  assert.equal(normalizeRange(0, 5, 45), 0);
  assert.equal(normalizeRange(50, 5, 45), 1);
  assert.equal(normalizeRange(25, 5, 5), null);
  assert.equal(normalizeRange(Number.NaN, 5, 45), null);
});

test('isFresh handles timestamps and stale windows', () => {
  assert.equal(isFresh(1_000, 2_000, 1_500), true);
  assert.equal(isFresh(1_000, 3_000, 1_500), false);
  assert.equal(isFresh(null, 2_000, 1_500), false);
});

test('toNumber accepts numbers, bigint, and Long-like objects', () => {
  assert.equal(toNumber(42), 42);
  assert.equal(toNumber(7n), 7);
  assert.equal(toNumber({ toNumber: () => 3.5 }), 3.5);
  assert.equal(toNumber({ toNumber: () => Number.NaN }), null);
  assert.equal(toNumber({ low: 5, high: 0 }), 5);
  assert.equal(toNumber('12'), null);
});

test('selectLatest skips invalid samples', () => {
  const latest = selectLatest([
    { value: 10 },
    { value: null },
    { value: { toNumber: () => 18 } },
  ]);
  assert.equal(latest.value, 18);
  assert.equal(selectLatest([]), null);
});

test('normalizeTrace normalizes values and applies the limit', () => {
  assert.deepEqual(normalizeTrace([{ value: 10 }, { value: 20 }, { value: 30 }]), [0, 0.5, 1]);
  assert.deepEqual(normalizeTrace([{ value: 5 }, { value: 5 }]), [0.5, 0.5]);
  assert.deepEqual(normalizeTrace([{ value: 1 }, { value: 2 }, { value: 3 }], 2), [0.5, 1]);
  assert.deepEqual(normalizeTrace([]), []);
});
