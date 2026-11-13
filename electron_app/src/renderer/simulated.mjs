export const SIMULATED_SOURCE = 'simulated';

const PROCESSING_STATUS_STARTING = 2;
const PROCESSING_STATUS_RUNNING = 3;
const TICK_MS = 250;

function measurement(value, timestampUs, confidence, stable = true) {
  return { value, confidence, stable, timestamp: timestampUs };
}

export function createSimulatedSource({
  onMetrics,
  onStatus,
  onValidation,
} = {}) {
  let started = false;
  let startedAt = 0;
  let statusTimer = null;
  let validationTimer = null;
  let tickTimer = null;

  function stopInternal() {
    started = false;
    if (statusTimer) clearTimeout(statusTimer);
    if (validationTimer) clearTimeout(validationTimer);
    if (tickTimer) clearInterval(tickTimer);
    statusTimer = null;
    validationTimer = null;
    tickTimer = null;
  }

  function emitTick() {
    if (!started) return;

    const now = Date.now();
    const elapsedSec = (now - startedAt) / 1000;
    const timestampUs = now * 1000;

    const breathingRate = 14 + Math.sin(elapsedSec / 6.4) * 2.4 + Math.sin(elapsedSec / 2.1) * 0.7;
    const pulseRate = 72 + Math.sin(elapsedSec / 4.2) * 4.1 + Math.sin(elapsedSec / 1.6) * 1.2;
    const breathingWave = Math.sin(elapsedSec * 1.55);
    const pulseWave = Math.sin(elapsedSec * 7.3);

    const decoded = {
      breathing: {
        rate: [measurement(breathingRate, timestampUs, 88, true)],
        upperTrace: [
          measurement(breathingWave * 0.9 + 0.1, timestampUs, 88, true),
        ],
      },
      cardio: {
        pulseRate: [measurement(pulseRate, timestampUs, 86, true)],
        arterialPressureTrace: [
          measurement(pulseWave * 0.8, timestampUs, 86, true),
        ],
        hrv: elapsedSec >= 60
          ? [{
              rmssd: 42 + Math.sin(elapsedSec / 11) * 4,
              meanNn: 830,
              sdnn: 48,
              baevsky: 62,
              confidence: 72,
              stable: true,
              timestamp: timestampUs,
            }]
          : [],
      },
    };

    onMetrics?.(decoded, now);
  }

  return {
    kind: SIMULATED_SOURCE,
    simulated: true,

    async start() {
      if (started) return;
      started = true;
      startedAt = Date.now();

      onStatus?.(PROCESSING_STATUS_STARTING);

      statusTimer = setTimeout(() => {
        if (!started) return;
        onStatus?.(PROCESSING_STATUS_RUNNING);
      }, 320);

      validationTimer = setTimeout(() => {
        if (!started) return;
        onValidation?.(0, Date.now() * 1000, 'Simulated signal looks good.');
      }, 500);

      tickTimer = setInterval(emitTick, TICK_MS);
      emitTick();
    },

    async stop() {
      stopInternal();
    },

    destroy() {
      stopInternal();
    },

    get isRunning() {
      return started;
    },
  };
}
