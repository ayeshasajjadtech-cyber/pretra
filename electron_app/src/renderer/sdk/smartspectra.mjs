import {
  SmartSpectraSDK,
  breathingMetrics,
  cardioMetrics,
} from '@smartspectra/node-sdk/renderer';
import { decodeMetrics } from '@smartspectra/node-sdk/messages';

export const SMARTSPECTRA_SOURCE = 'smartspectra';

export function createSmartSpectraSource({
  apiKey,
  onMetrics,
  onStatus,
  onValidation,
  onStream,
  onError,
  onLog = () => {},
} = {}) {
  if (typeof apiKey !== 'string' || apiKey.trim().length === 0) {
    const error = new Error('SMARTSPECTRA_API_KEY is missing from .env');
    error.code = 'NO_API_KEY';
    throw error;
  }

  let sdk = null;
  let started = false;
  let starting = false;

  function createSdk() {
    const instance = new SmartSpectraSDK({
      apiKey: apiKey.trim(),
      requestedMetrics: [...breathingMetrics, ...cardioMetrics],
      enableAccumulatedOutput: false,
      enableTelemetry: false,
    });

    instance.on('processingStatus', (status) => {
      onStatus?.(status);
    });

    instance.on('validationStatus', (code, timestampUs, hint) => {
      onValidation?.(code, timestampUs, hint);
    });

    instance.on('metrics', (buffer) => {
      try {
        const decoded = decodeMetrics(buffer);
        onMetrics?.(decoded, Date.now());
      } catch (error) {
        onLog('warn', `Could not decode metrics: ${error?.message || error}`);
      }
    });

    instance.on('streamAvailable', (stream) => {
      onStream?.(stream);
    });

    instance.on('error', (code, message, retryable) => {
      onError?.({ code, message, retryable });
    });

    return instance;
  }

  return {
    kind: SMARTSPECTRA_SOURCE,
    simulated: false,

    async start() {
      if (started || starting) return;
      starting = true;
      try {
        if (!sdk) sdk = createSdk();
        await sdk.start();
        started = true;
      } finally {
        starting = false;
      }
    },

    async stop() {
      if (!sdk) return;
      try {
        await sdk.stop();
      } finally {
        started = false;
      }
    },

    destroy() {
      if (!sdk) return;
      try {
        sdk.destroy();
      } catch (error) {
        onLog('warn', `SDK destroy failed: ${error?.message || error}`);
      } finally {
        sdk = null;
        started = false;
      }
    },

    get isRunning() {
      return started;
    },
  };
}
