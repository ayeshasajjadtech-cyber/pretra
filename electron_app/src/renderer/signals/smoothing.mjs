export const DEFAULT_STALE_MS = 7000;

export function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

export function toNumber(value) {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'bigint') return Number(value);
  if (value && typeof value === 'object') {
    if (typeof value.toNumber === 'function') {
      try {
        const number = value.toNumber();
        return Number.isFinite(number) ? number : null;
      } catch {
        return null;
      }
    }
    if (typeof value.low === 'number' && typeof value.high === 'number') {
      return Number(BigInt(value.high) << 32n | BigInt(value.low >>> 0));
    }
  }
  return null;
}

export function ema(previous, next, alpha = 0.22) {
  if (!Number.isFinite(next)) return previous;
  if (!Number.isFinite(previous)) return next;
  return previous + (next - previous) * clamp(alpha, 0, 1);
}

export function normalizeRange(value, min, max) {
  if (!Number.isFinite(value) || max <= min) return null;
  return clamp((value - min) / (max - min), 0, 1);
}

export function isFresh(timestampMs, nowMs = Date.now(), staleMs = DEFAULT_STALE_MS) {
  return Number.isFinite(timestampMs) && nowMs - timestampMs <= staleMs;
}

export function selectLatest(samples) {
  if (!Array.isArray(samples) || samples.length === 0) return null;

  for (let index = samples.length - 1; index >= 0; index -= 1) {
    const sample = samples[index];
    const value = toNumber(sample?.value);
    if (value !== null) return { sample, value };
  }

  return null;
}

export function normalizeTrace(samples, limit = 160) {
  if (!Array.isArray(samples)) return [];

  const values = samples
    .map((sample) => toNumber(sample?.value))
    .filter((value) => value !== null);

  if (values.length === 0) return [];

  let min = Infinity;
  let max = -Infinity;
  for (const value of values) {
    if (value < min) min = value;
    if (value > max) max = value;
  }

  const span = max - min;
  const normalized = values.map((value) => (span === 0 ? 0.5 : (value - min) / span));
  return normalized.slice(-limit);
}
