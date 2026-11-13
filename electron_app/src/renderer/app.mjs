import { createSmartSpectraSource } from './sdk/smartspectra.mjs';
import { describeSdkError, describeValidation } from './sdk/error-messages.mjs';
import { SignalEngine } from './signals/engine.mjs';
import { clamp } from './signals/smoothing.mjs';
import { createLandscape } from './visual/landscape.mjs';
import { createSimulatedSource } from './simulated.mjs';

const STORAGE_KEY = 'breatheGarden.savedSummaries.v1';
const LIVE_STATES = new Set(['starting', 'calibrating', 'active', 'stopping']);

const $ = (id) => document.getElementById(id);

const els = {
  landscape: $('landscape'),
  consentPanel: $('consentPanel'),
  consentCheckbox: $('consentCheckbox'),
  consentNotice: $('consentNotice'),
  startBtn: $('startBtn'),
  sessionPanel: $('sessionPanel'),
  sessionTimer: $('sessionTimer'),
  breathingValue: $('breathingValue'),
  breathingState: $('breathingState'),
  breathingConfidence: $('breathingConfidence'),
  breathingSpark: $('breathingSpark'),
  pulseValue: $('pulseValue'),
  pulseState: $('pulseState'),
  pulseConfidence: $('pulseConfidence'),
  pulseSpark: $('pulseSpark'),
  signalQuality: $('signalQuality'),
  validationHint: $('validationHint'),
  previewPanel: $('previewPanel'),
  previewVideo: $('previewVideo'),
  calibrationPanel: $('calibrationPanel'),
  calibrationTitle: $('calibrationTitle'),
  calibrationMessage: $('calibrationMessage'),
  simulatedBanner: $('simulatedBanner'),
  cameraState: $('cameraState'),
  cameraStateText: $('cameraStateText'),
  stopCameraBtn: $('stopCameraBtn'),
  savedSessionsBtn: $('savedSessionsBtn'),
  savedCount: $('savedCount'),
  errorBanner: $('errorBanner'),
  errorTitle: $('errorTitle'),
  errorMessage: $('errorMessage'),
  errorRetryBtn: $('errorRetryBtn'),
  errorDismissBtn: $('errorDismissBtn'),
  toast: $('toast'),
  summaryDialog: $('summaryDialog'),
  summaryDuration: $('summaryDuration'),
  summaryBreathing: $('summaryBreathing'),
  summaryPulse: $('summaryPulse'),
  summaryHrvRow: $('summaryHrvRow'),
  summaryHrv: $('summaryHrv'),
  summaryNote: $('summaryNote'),
  summarySaveBtn: $('summarySaveBtn'),
  summaryDiscardBtn: $('summaryDiscardBtn'),
  summaryAgainBtn: $('summaryAgainBtn'),
  savedDialog: $('savedDialog'),
  savedList: $('savedList'),
  savedClearBtn: $('savedClearBtn'),
  savedCloseBtn: $('savedCloseBtn'),
};

const engine = new SignalEngine();
const landscape = createLandscape(els.landscape);

let config = {
  apiKey: '',
  appVersion: '',
  hasApiKey: false,
  isDev: false,
  platform: '',
  sdkLoadError: '',
  smoke: false,
};
let isDev = false;
let simulatedRequested = false;
let source = null;
let appState = 'consent';
let sessionStartedAt = null;
let sessionEndedAt = null;
let simulated = false;
let hasStream = false;
let currentStatus = null;
let lastValidation = null;
let lastError = null;
let noSignalSince = null;
let isStarting = false;
let stopRequested = false;
let uiTimer = null;
let toastTimer = null;
let summary = null;
let savedSummaries = [];
let savedThisSummary = false;
let lastSavedId = null;
let lastStartOptions = { simulated: false };

function formatNumber(value, digits = 1) {
  if (!Number.isFinite(value)) return '—';
  const text = value.toFixed(digits);
  return text.endsWith('.0') ? text.slice(0, -2) : text;
}

function formatDuration(durationMs) {
  const totalSeconds = Math.max(0, Math.floor((Number.isFinite(durationMs) ? durationMs : 0) / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (hours > 0) {
    return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  }
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

function formatSavedDate(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Unknown date';
  try {
    return date.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
  } catch {
    return date.toLocaleString();
  }
}

function showToast(message) {
  els.toast.textContent = message;
  els.toast.hidden = false;
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    els.toast.hidden = true;
    toastTimer = null;
  }, 3200);
}

function showConsentNotice(message, isError = false) {
  if (!message) {
    els.consentNotice.hidden = true;
    els.consentNotice.textContent = '';
    els.consentNotice.classList.remove('is-error');
    return;
  }

  els.consentNotice.hidden = false;
  els.consentNotice.textContent = message;
  els.consentNotice.classList.toggle('is-error', isError);
}

function showError({ title, message, retryable = false }) {
  lastError = { title, message, retryable, at: Date.now() };
  els.errorTitle.textContent = title;
  els.errorMessage.textContent = message;
  els.errorBanner.hidden = false;
  els.errorRetryBtn.hidden = !retryable || appState !== 'consent';
}

function hideError() {
  lastError = null;
  els.errorBanner.hidden = true;
  els.errorRetryBtn.hidden = true;
}

function updateStartButton() {
  const liveAllowed = simulatedRequested || (config.hasApiKey && !config.sdkLoadError);
  els.startBtn.disabled = !(
    appState === 'consent'
    && els.consentCheckbox.checked
    && liveAllowed
    && !isStarting
  );
}

function updateSavedButton() {
  const count = savedSummaries.length;
  els.savedSessionsBtn.hidden = count === 0;
  els.savedCount.textContent = String(count);
  els.savedClearBtn.disabled = count === 0;
}

function syncPanels() {
  const live = LIVE_STATES.has(appState);
  els.consentPanel.hidden = live || appState === 'summary';
  els.sessionPanel.hidden = !live;
  els.calibrationPanel.hidden = !(
    appState === 'starting'
    || appState === 'calibrating'
    || appState === 'stopping'
  );
  els.simulatedBanner.hidden = !(simulated && live);
  els.previewPanel.hidden = !(hasStream && live);
}

function updateCameraUI() {
  els.cameraState.classList.remove('is-active', 'is-simulated', 'is-error');

  let text = 'Camera off';
  if (simulated && LIVE_STATES.has(appState)) {
    text = 'Simulated session';
    els.cameraState.classList.add('is-simulated');
  } else if (appState === 'starting') {
    text = 'Starting camera';
  } else if (appState === 'stopping') {
    text = 'Stopping camera';
  } else if (hasStream && LIVE_STATES.has(appState)) {
    text = 'Camera active';
    els.cameraState.classList.add('is-active');
  } else if (lastError && appState === 'consent') {
    text = 'Camera issue';
    els.cameraState.classList.add('is-error');
  }

  els.cameraStateText.textContent = text;
  els.stopCameraBtn.disabled = !['starting', 'calibrating', 'active'].includes(appState);
  if (lastError) {
    els.errorRetryBtn.hidden = !lastError.retryable || appState !== 'consent';
  }
}

function updateCalibrationCopy() {
  if (appState === 'starting') {
    els.calibrationTitle.textContent = 'Waking up the garden';
    els.calibrationMessage.textContent = 'Allow camera access if prompted. This can take a few seconds.';
    return;
  }

  if (appState === 'stopping') {
    els.calibrationTitle.textContent = 'Closing the garden';
    els.calibrationMessage.textContent = 'Releasing the camera and preparing your summary.';
    return;
  }

  if (appState === 'calibrating') {
    els.calibrationTitle.textContent = simulated ? 'Simulated signal is warming up' : 'Finding your rhythm';
    if (lastValidation) {
      const validation = describeValidation(lastValidation.code, lastValidation.hint);
      els.calibrationMessage.textContent = validation.code === 0
        ? 'Signal looks good. Keep still while the first readings settle.'
        : validation.message;
    } else {
      els.calibrationMessage.textContent = 'Sit comfortably, face the camera, and breathe naturally.';
    }
    return;
  }

  els.calibrationTitle.textContent = 'Finding your rhythm';
  els.calibrationMessage.textContent = 'Sit comfortably, face the camera, and breathe naturally.';
}

function defaultValidationMessage() {
  if (appState === 'starting') return 'Allow camera access if prompted.';
  if (appState === 'stopping') return 'Releasing the camera.';
  if (appState === 'active') return 'Reading your rhythm. Breathe naturally.';
  return 'Sit comfortably, face the camera, and breathe naturally.';
}

function updateValidationUI() {
  if (lastValidation) {
    const validation = describeValidation(lastValidation.code, lastValidation.hint);
    els.validationHint.textContent = validation.message;
  } else {
    els.validationHint.textContent = defaultValidationMessage();
  }
}

function updateSignalQuality(snapshot) {
  let label = 'Waiting for camera';
  let level = '';

  if (appState === 'starting') {
    label = simulated ? 'Starting simulated signal' : 'Starting camera';
  } else if (appState === 'stopping') {
    label = 'Stopping camera';
  } else if (snapshot.breathing.valid && snapshot.pulse.valid) {
    label = 'Breathing + pulse stable';
    level = 'is-good';
  } else if (snapshot.breathing.valid) {
    label = 'Breathing stable';
    level = 'is-good';
  } else if (snapshot.pulse.valid) {
    label = 'Pulse stable';
    level = 'is-good';
  } else if (snapshot.hasVisualSignal) {
    label = 'Signal settling';
    level = 'is-warn';
  } else if (currentStatus === 3) {
    label = 'Waiting for a clear view';
    level = 'is-warn';
  }

  els.signalQuality.textContent = label;
  els.signalQuality.className = `signal-quality${level ? ` ${level}` : ''}`;
}

function drawSparkline(canvas, values, color) {
  const rect = canvas.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return;

  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const pixelWidth = Math.max(1, Math.round(rect.width * dpr));
  const pixelHeight = Math.max(1, Math.round(rect.height * dpr));
  if (canvas.width !== pixelWidth || canvas.height !== pixelHeight) {
    canvas.width = pixelWidth;
    canvas.height = pixelHeight;
  }

  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, rect.width, rect.height);

  const paddingX = 3;
  const paddingY = 5;
  const width = Math.max(1, rect.width - paddingX * 2);
  const height = Math.max(1, rect.height - paddingY * 2);

  ctx.save();
  ctx.strokeStyle = 'rgba(199, 232, 215, 0.12)';
  ctx.lineWidth = 1;
  ctx.setLineDash([3, 4]);
  ctx.beginPath();
  ctx.moveTo(paddingX, paddingY + height * 0.5);
  ctx.lineTo(paddingX + width, paddingY + height * 0.5);
  ctx.stroke();
  ctx.restore();

  if (values.length < 2) return;

  const points = values.map((value, index) => {
    const x = paddingX + (index / (values.length - 1)) * width;
    const y = paddingY + (1 - clamp(value, 0, 1)) * height;
    return [x, y];
  });

  const gradient = ctx.createLinearGradient(0, paddingY, 0, paddingY + height);
  gradient.addColorStop(0, color.replace('0.9', '0.2'));
  gradient.addColorStop(1, color.replace('0.9', '0'));

  ctx.beginPath();
  for (let index = 0; index < points.length; index += 1) {
    const [x, y] = points[index];
    if (index === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.lineTo(paddingX + width, paddingY + height);
  ctx.lineTo(paddingX, paddingY + height);
  ctx.closePath();
  ctx.fillStyle = gradient;
  ctx.fill();

  ctx.beginPath();
  for (let index = 0; index < points.length; index += 1) {
    const [x, y] = points[index];
    if (index === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.strokeStyle = color;
  ctx.lineWidth = 1.6;
  ctx.lineJoin = 'round';
  ctx.lineCap = 'round';
  ctx.stroke();
}

function updateMetricUI(kind, metric) {
  const isBreathing = kind === 'breathing';
  const valueEl = isBreathing ? els.breathingValue : els.pulseValue;
  const stateEl = isBreathing ? els.breathingState : els.pulseState;
  const confidenceEl = isBreathing ? els.breathingConfidence : els.pulseConfidence;
  const sparkEl = isBreathing ? els.breathingSpark : els.pulseSpark;
  const digits = isBreathing ? 1 : 0;

  valueEl.textContent = metric.valid ? formatNumber(metric.value, digits) : '—';
  confidenceEl.style.width = `${clamp(metric.confidence, 0, 100)}%`;

  stateEl.className = 'metric-state';
  if (metric.valid) {
    stateEl.textContent = 'stable';
    stateEl.classList.add('is-good');
  } else if (metric.fresh) {
    stateEl.textContent = 'settling';
    stateEl.classList.add('is-low');
  } else if (metric.ageMs !== null) {
    stateEl.textContent = 'stale';
    stateEl.classList.add('is-stale');
  } else {
    stateEl.textContent = 'waiting';
  }

  drawSparkline(
    sparkEl,
    metric.sparkline,
    isBreathing ? 'rgba(139, 230, 176, 0.9)' : 'rgba(255, 156, 125, 0.9)',
  );
}

function resetMetricUI() {
  els.sessionTimer.textContent = '00:00';
  els.breathingValue.textContent = '—';
  els.pulseValue.textContent = '—';
  els.breathingState.textContent = 'waiting';
  els.pulseState.textContent = 'waiting';
  els.breathingState.className = 'metric-state';
  els.pulseState.className = 'metric-state';
  els.breathingConfidence.style.width = '0%';
  els.pulseConfidence.style.width = '0%';
  els.signalQuality.textContent = 'Waiting for camera';
  els.signalQuality.className = 'signal-quality';
  els.validationHint.textContent = defaultValidationMessage();
  drawSparkline(els.breathingSpark, [], 'rgba(139, 230, 176, 0.9)');
  drawSparkline(els.pulseSpark, [], 'rgba(255, 156, 125, 0.9)');
}

function updateLandscape(now) {
  const visual = engine.getVisualState(now);
  landscape.setSignal({
    active: visual.active,
    simulated,
    breathing: visual.breathing,
    pulse: visual.pulse,
    breathingRate: visual.breathingRate,
    pulseRate: visual.pulseRate,
    confidence: visual.confidence,
  });
}

function updateLiveUI() {
  if (!LIVE_STATES.has(appState)) return;

  const now = Date.now();
  if (lastValidation && now - lastValidation.at > 12_000) {
    lastValidation = null;
  }

  const snapshot = engine.getSnapshot(now);

  updateMetricUI('breathing', snapshot.breathing);
  updateMetricUI('pulse', snapshot.pulse);
  els.sessionTimer.textContent = formatDuration(snapshot.durationMs);
  updateSignalQuality(snapshot);
  updateValidationUI();
  updateLandscape(now);

  if (appState === 'calibrating' && snapshot.hasSignal) {
    appState = 'active';
    noSignalSince = null;
  } else if (appState === 'active' && !snapshot.hasSignal) {
    if (noSignalSince === null) noSignalSince = now;
    if (now - noSignalSince > 2_500) {
      appState = 'calibrating';
      noSignalSince = null;
    }
  } else if (snapshot.hasSignal) {
    noSignalSince = null;
  }

  updateCalibrationCopy();
  syncPanels();
  updateCameraUI();
}

function startUiTicker() {
  if (uiTimer) return;
  uiTimer = setInterval(updateLiveUI, 200);
  updateLiveUI();
}

function stopUiTicker() {
  if (uiTimer) clearInterval(uiTimer);
  uiTimer = null;
}

function releasePreview() {
  const stream = els.previewVideo.srcObject;
  if (stream) {
    for (const track of stream.getTracks()) {
      try {
        track.stop();
      } catch {
        // The SDK may already have stopped the track.
      }
    }
  }
  els.previewVideo.srcObject = null;
  els.previewPanel.hidden = true;
}

function resetToConsent({ uncheck = true, focus = false } = {}) {
  if (els.summaryDialog.open) els.summaryDialog.close();

  stopUiTicker();
  releasePreview();
  engine.reset();

  appState = 'consent';
  source = null;
  sessionStartedAt = null;
  sessionEndedAt = null;
  simulated = false;
  hasStream = false;
  currentStatus = null;
  lastValidation = null;
  noSignalSince = null;
  isStarting = false;
  stopRequested = false;
  summary = null;
  savedThisSummary = false;
  lastSavedId = null;

  if (uncheck) els.consentCheckbox.checked = false;

  resetMetricUI();
  landscape.setMode('ambient');
  landscape.setSignal({
    active: false,
    simulated: false,
    breathing: null,
    pulse: null,
    breathingRate: null,
    pulseRate: null,
    confidence: 0,
  });

  syncPanels();
  updateCameraUI();
  updateStartButton();

  if (focus) {
    if (els.startBtn.disabled) els.consentCheckbox.focus();
    else els.startBtn.focus();
  }
}

function showSummary(result) {
  appState = 'summary';
  summary = result;
  savedThisSummary = false;
  lastSavedId = null;

  syncPanels();
  updateCameraUI();
  landscape.setMode('summary');
  landscape.setSignal({
    active: false,
    simulated: false,
    breathing: null,
    pulse: null,
    breathingRate: null,
    pulseRate: null,
    confidence: 0,
  });

  fillSummaryDialog(result);
  if (!els.summaryDialog.open) els.summaryDialog.showModal();
}

function fillSummaryDialog(result) {
  const hrvAvailable = Boolean(result.hrvEligible && result.hrvRmssd !== null);

  els.summaryDuration.textContent = formatDuration(result.durationMs);
  els.summaryBreathing.textContent = formatNumber(result.breathingAvg, 1);
  els.summaryPulse.textContent = formatNumber(result.pulseAvg, 0);
  els.summaryHrv.textContent = hrvAvailable ? formatNumber(result.hrvRmssd, 1) : '—';
  els.summaryHrvRow.hidden = !hrvAvailable;

  if (result.simulated) {
    els.summaryNote.textContent = 'This was a simulated development session. It cannot be saved.';
  } else if (!result.hasData) {
    els.summaryNote.textContent = 'No stable readings were captured, so there is nothing to save.';
  } else if (!result.hrvEligible) {
    els.summaryNote.textContent = 'HRV is included only in summaries after 60 seconds of stable pulse data.';
  } else if (hrvAvailable) {
    els.summaryNote.textContent = 'A short, private record. Not a medical assessment.';
  } else {
    els.summaryNote.textContent = 'HRV was not stable enough to include in this summary.';
  }

  const canSave = Boolean(result.hasData && !result.simulated);
  els.summarySaveBtn.disabled = !canSave;
  els.summarySaveBtn.textContent = canSave ? 'Save locally' : 'Nothing to save';
}

function finishSession() {
  stopUiTicker();
  releasePreview();

  const wasSimulated = simulated;
  const endedAt = Date.now();
  const result = engine.getSummary(endedAt);
  summary = { ...result, simulated: wasSimulated };

  sessionEndedAt = endedAt;
  hasStream = false;
  currentStatus = null;
  noSignalSince = null;
  simulated = false;
  stopRequested = false;

  updateCameraUI();

  if (summary.hasData || summary.durationMs >= 2_000) {
    showSummary(summary);
  } else {
    resetToConsent({ uncheck: true });
    if (!lastError) showToast('Camera stopped. No stable readings were captured.');
  }
}

async function startSession({ simulated: useSimulated = false } = {}) {
  if (appState !== 'consent' || isStarting) return;
  if (!els.consentCheckbox.checked) {
    updateStartButton();
    return;
  }

  if (!useSimulated && (!config.hasApiKey || config.sdkLoadError)) {
    showError({
      title: 'Live camera is not ready',
      message: config.sdkLoadError
        ? `The SmartSpectra SDK could not load: ${config.sdkLoadError}`
        : 'Add SMARTSPECTRA_API_KEY to your .env file and restart Breathe Garden.',
      retryable: false,
    });
    return;
  }

  isStarting = true;
  stopRequested = false;
  lastStartOptions = { simulated: useSimulated };
  hideError();

  appState = 'starting';
  simulated = useSimulated;
  hasStream = false;
  currentStatus = null;
  lastValidation = null;
  noSignalSince = null;
  summary = null;
  savedThisSummary = false;
  lastSavedId = null;
  sessionEndedAt = null;
  sessionStartedAt = Date.now();
  engine.startSession(sessionStartedAt);

  resetMetricUI();
  updateStartButton();
  syncPanels();
  updateCameraUI();
  updateCalibrationCopy();
  landscape.setMode('calibrating');
  startUiTicker();

  try {
    if (useSimulated) {
      source = createSimulatedSource({
        onMetrics: handleMetrics,
        onStatus: handleStatus,
        onValidation: handleValidation,
      });
    } else {
      source = createSmartSpectraSource({
        apiKey: config.apiKey,
        onMetrics: handleMetrics,
        onStatus: handleStatus,
        onValidation: handleValidation,
        onStream: handleStream,
        onError: handleSdkError,
        onLog: (level, message) => {
          const log = level === 'warn' ? console.warn : console.log;
          log(`[breathe-garden] ${message}`);
        },
      });
    }

    await source.start();

    if (stopRequested || appState !== 'starting') {
      try {
        await source?.stop();
      } catch {
        // The session was stopped while starting.
      }
      try {
        source?.destroy();
      } catch {
        // Already torn down.
      }
      source = null;
      return;
    }

    appState = 'calibrating';
    updateCalibrationCopy();
    syncPanels();
    updateCameraUI();
  } catch (error) {
    if (stopRequested || appState !== 'starting') {
      try {
        source?.destroy();
      } catch {
        // Already torn down.
      }
      source = null;
      return;
    }
    handleStartFailure(error);
  } finally {
    isStarting = false;
    updateStartButton();
  }
}

function handleStartFailure(error) {
  try {
    source?.destroy();
  } catch {
    // Already torn down.
  }
  source = null;

  resetToConsent({ uncheck: false });
  const described = describeStartError(error);
  showError(described);
  updateCameraUI();
}

function describeStartError(error) {
  const code = error?.code;
  const message = error?.message || String(error);

  if (code === 'NO_API_KEY') {
    return {
      title: 'API key missing',
      message: 'Add SMARTSPECTRA_API_KEY to your .env file and restart Breathe Garden.',
      retryable: false,
    };
  }

  if (typeof code === 'number') {
    const info = describeSdkError(code, message, error?.retryable);
    return {
      title: info.title,
      message: info.message,
      retryable: ![2, 3, 4].includes(code),
    };
  }

  if (code === 'SMARTSPECTRA_IPC_TIMEOUT') {
    return {
      title: 'The SDK did not respond',
      message: 'The main process did not acknowledge the start request. Restart Breathe Garden and try again.',
      retryable: true,
    };
  }

  if (error?.name === 'NotAllowedError' || /permission/i.test(message)) {
    return {
      title: 'Camera permission was not granted',
      message: 'Allow camera access in the system prompt or app settings, then try again.',
      retryable: true,
    };
  }

  if (error?.name === 'NotFoundError' || /no .*camera|device not found/i.test(message)) {
    return {
      title: 'No camera found',
      message: 'Connect a camera or choose a different device, then try again.',
      retryable: true,
    };
  }

  if (error?.name === 'NotReadableError' || /could not start|in use|busy/i.test(message)) {
    return {
      title: 'Camera is busy',
      message: 'Another app may be using the camera. Close it and try again.',
      retryable: true,
    };
  }

  return {
    title: 'The session could not start',
    message,
    retryable: true,
  };
}

function handleMetrics(decoded, receivedAt) {
  if (!LIVE_STATES.has(appState)) return;
  engine.ingestMetrics(decoded, receivedAt);
}

function handleStatus(status) {
  currentStatus = status;
  if (LIVE_STATES.has(appState)) updateLiveUI();
}

function handleValidation(code, timestampUs, hint) {
  lastValidation = {
    code,
    timestampUs,
    hint: hint || '',
    at: Date.now(),
  };
  if (LIVE_STATES.has(appState)) updateLiveUI();
}

function handleStream(stream) {
  hasStream = Boolean(stream);
  els.previewVideo.srcObject = stream || null;
  if (stream) {
    const playPromise = els.previewVideo.play();
    if (playPromise?.catch) {
      playPromise.catch((error) => {
        console.warn('[breathe-garden] Preview playback failed:', error?.message || error);
      });
    }
  }
  syncPanels();
  updateCameraUI();
}

function handleSdkError({ code, message, retryable }) {
  const info = describeSdkError(code, message, retryable);
  showError({
    title: info.title,
    message: info.message,
    retryable: false,
  });

  if (info.fatal && ['starting', 'calibrating', 'active'].includes(appState)) {
    setTimeout(() => {
      if (['starting', 'calibrating', 'active'].includes(appState)) {
        stopSession({ reason: 'error' });
      }
    }, 0);
  }
}

async function stopSession({ reason = 'user' } = {}) {
  if (!['starting', 'calibrating', 'active'].includes(appState)) return;

  stopRequested = true;
  appState = 'stopping';
  syncPanels();
  updateCameraUI();
  updateStartButton();

  const currentSource = source;

  try {
    if (currentSource) await currentSource.stop();
  } catch (error) {
    console.warn('[breathe-garden] SDK stop failed:', error?.message || error);
    showError({
      title: 'The camera did not stop cleanly',
      message: 'The preview was released, but if the camera indicator stays on, close Breathe Garden.',
      retryable: false,
    });
  } finally {
    try {
      currentSource?.destroy();
    } catch {
      // Already torn down.
    }
    if (source === currentSource) source = null;
    releasePreview();
    finishSession(reason);
  }
}

function saveCurrentSummary() {
  if (!summary || summary.simulated || !summary.hasData || savedThisSummary) return;

  const entry = {
    id: globalThis.crypto?.randomUUID?.()
      || `breathe-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    savedAt: new Date().toISOString(),
    durationMs: Math.round(summary.durationMs),
    breathingAvg: summary.breathingAvg,
    pulseAvg: summary.pulseAvg,
    hrvRmssd: summary.hrvRmssd,
    appVersion: config.appVersion || '',
  };

  const previous = savedSummaries;
  savedSummaries = [entry, ...savedSummaries].slice(0, 50);

  if (!persistSavedSummaries()) {
    savedSummaries = previous;
    showError({
      title: 'Could not save locally',
      message: 'Local storage is unavailable or full. Nothing was saved.',
      retryable: false,
    });
    return;
  }

  savedThisSummary = true;
  lastSavedId = entry.id;
  updateSavedButton();
  renderSavedSessions();

  els.summarySaveBtn.disabled = true;
  els.summarySaveBtn.textContent = 'Saved locally';
  els.summaryNote.textContent = 'Saved on this device. Delete it any time from Saved sessions.';
}

function loadSavedSummaries() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((entry) => (
        entry
        && typeof entry.id === 'string'
        && typeof entry.savedAt === 'string'
        && Number.isFinite(entry.durationMs)
      ))
      .slice(0, 50);
  } catch (error) {
    console.warn('[breathe-garden] Could not read saved summaries:', error?.message || error);
    return [];
  }
}

function persistSavedSummaries() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(savedSummaries));
    return true;
  } catch (error) {
    console.warn('[breathe-garden] Could not persist saved summaries:', error?.message || error);
    return false;
  }
}

function renderSavedSessions() {
  els.savedList.replaceChildren();

  if (savedSummaries.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'saved-empty';
    empty.textContent = 'No saved summaries yet.';
    els.savedList.append(empty);
    els.savedClearBtn.disabled = true;
    return;
  }

  for (const entry of savedSummaries) {
    const item = document.createElement('div');
    item.className = 'saved-item';

    const copy = document.createElement('div');
    const heading = document.createElement('strong');
    heading.textContent = `${formatNumber(entry.breathingAvg, 1)} br/min · ${formatNumber(entry.pulseAvg, 0)} BPM`;
    const details = document.createElement('p');
    const hrv = Number.isFinite(entry.hrvRmssd) ? ` · HRV ${formatNumber(entry.hrvRmssd, 1)} ms` : '';
    details.textContent = `Duration ${formatDuration(entry.durationMs)}${hrv}`;
    const time = document.createElement('time');
    time.dateTime = entry.savedAt;
    time.textContent = formatSavedDate(entry.savedAt);

    copy.append(heading, details, time);

    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'button button-quiet saved-delete';
    remove.dataset.deleteId = entry.id;
    remove.textContent = 'Delete';

    item.append(copy, remove);
    els.savedList.append(item);
  }

  els.savedClearBtn.disabled = false;
}

function deleteSavedSummary(id) {
  const entry = savedSummaries.find((item) => item.id === id);
  if (!entry) return;

  const previous = savedSummaries;
  savedSummaries = savedSummaries.filter((item) => item.id !== id);

  if (!persistSavedSummaries()) {
    savedSummaries = previous;
    showError({
      title: 'Could not delete the saved summary',
      message: 'Local storage is unavailable. Nothing was changed.',
      retryable: false,
    });
    return;
  }

  if (lastSavedId === id) {
    lastSavedId = null;
    savedThisSummary = false;
    if (summary && els.summaryDialog.open && !summary.simulated && summary.hasData) {
      els.summarySaveBtn.disabled = false;
      els.summarySaveBtn.textContent = 'Save locally';
      els.summaryNote.textContent = 'The saved copy was deleted. You can save this summary again.';
    }
  }

  renderSavedSessions();
  updateSavedButton();
}

function clearSavedSummaries() {
  if (savedSummaries.length === 0) return;
  if (!window.confirm('Delete all saved session summaries from this device?')) return;

  const previous = savedSummaries;
  savedSummaries = [];

  if (!persistSavedSummaries()) {
    savedSummaries = previous;
    showError({
      title: 'Could not delete saved summaries',
      message: 'Local storage is unavailable. Nothing was changed.',
      retryable: false,
    });
    return;
  }

  lastSavedId = null;
  savedThisSummary = false;
  if (summary && els.summaryDialog.open && !summary.simulated && summary.hasData) {
    els.summarySaveBtn.disabled = false;
    els.summarySaveBtn.textContent = 'Save locally';
    els.summaryNote.textContent = 'Saved copies were deleted. You can save this summary again.';
  }

  renderSavedSessions();
  updateSavedButton();
}

function openSavedDialog() {
  if (savedSummaries.length === 0) return;
  renderSavedSessions();
  if (!els.savedDialog.open) els.savedDialog.showModal();
}

function closeSummary(action) {
  if (els.summaryDialog.open) els.summaryDialog.close();

  if (action === 'discard') {
    summary = null;
    resetToConsent({ uncheck: true });
    showToast('Summary discarded. Nothing was saved.');
    return;
  }

  if (action === 'again') {
    summary = null;
    resetToConsent({ uncheck: true, focus: true });
  }
}

function retryLastSession() {
  hideError();
  if (!els.consentCheckbox.checked) {
    els.consentCheckbox.checked = true;
    updateStartButton();
  }

  if (els.startBtn.disabled) {
    els.consentCheckbox.focus();
    return;
  }

  startSession({ simulated: lastStartOptions.simulated });
}

function applyConfigState() {
  const issues = [];

  if (config.sdkLoadError) {
    issues.push(`Live camera is unavailable: ${config.sdkLoadError}`);
  }

  if (!config.hasApiKey) {
    issues.push('No SMARTSPECTRA_API_KEY was found. Add it to .env and restart Breathe Garden to use the live camera.');
  }

  if (simulatedRequested) {
    issues.push('Simulated development mode is enabled. No camera will turn on.');
  }

  showConsentNotice(
    issues.join(' '),
    Boolean((config.sdkLoadError || !config.hasApiKey) && !simulatedRequested),
  );
}

function setupEventListeners() {
  els.consentCheckbox.addEventListener('change', updateStartButton);

  els.startBtn.addEventListener('click', () => {
    startSession({ simulated: simulatedRequested });
  });

  els.stopCameraBtn.addEventListener('click', () => {
    stopSession({ reason: 'user' });
  });

  els.errorDismissBtn.addEventListener('click', hideError);
  els.errorRetryBtn.addEventListener('click', retryLastSession);

  els.summarySaveBtn.addEventListener('click', saveCurrentSummary);
  els.summaryDiscardBtn.addEventListener('click', () => closeSummary('discard'));
  els.summaryAgainBtn.addEventListener('click', () => closeSummary('again'));

  els.summaryDialog.addEventListener('cancel', (event) => {
    event.preventDefault();
  });

  els.savedSessionsBtn.addEventListener('click', openSavedDialog);
  els.savedCloseBtn.addEventListener('click', () => els.savedDialog.close());
  els.savedClearBtn.addEventListener('click', clearSavedSummaries);

  els.savedList.addEventListener('click', (event) => {
    const button = event.target.closest?.('button[data-delete-id]');
    if (!button) return;
    deleteSavedSummary(button.dataset.deleteId);
  });

  els.savedDialog.addEventListener('click', (event) => {
    if (event.target === els.savedDialog) els.savedDialog.close();
  });

  window.addEventListener('resize', () => landscape.resize());

  window.addEventListener('beforeunload', cleanup);
  window.addEventListener('pagehide', cleanup);
}

function cleanup() {
  stopUiTicker();
  releasePreview();
  try {
    source?.destroy();
  } catch {
    // Nothing left to release.
  }
  source = null;
  landscape.stop();
}

function installDevHelpers() {
  window.__breatheGardenDev = {
    startSimulated() {
      if (appState !== 'consent') return false;
      els.consentCheckbox.checked = true;
      updateStartButton();
      startSession({ simulated: true });
      return true;
    },

    stop() {
      return stopSession({ reason: 'dev' });
    },

    getState() {
      const snapshot = engine.getSnapshot();
      return {
        state: appState,
        simulated,
        hasStream,
        cameraActive: hasStream && ['starting', 'calibrating', 'active'].includes(appState),
        breathing: snapshot.breathing.value,
        pulse: snapshot.pulse.value,
        breathingValid: snapshot.breathing.valid,
        pulseValid: snapshot.pulse.valid,
        durationMs: snapshot.durationMs,
        savedCount: savedSummaries.length,
        summary: summary ? { ...summary } : null,
        error: lastError ? { ...lastError } : null,
      };
    },
  };
}

async function init() {
  try {
    const loadedConfig = await window.breatheGarden.getConfig();
    config = { ...config, ...(loadedConfig || {}) };
  } catch (error) {
    config = {
      ...config,
      sdkLoadError: `Could not read app configuration: ${error?.message || error}`,
    };
  }

  isDev = Boolean(config.isDev);
  simulatedRequested = isDev
    && new URLSearchParams(window.location.search).get('simulate') === '1';
  lastStartOptions = { simulated: simulatedRequested };

  savedSummaries = loadSavedSummaries();
  landscape.start();
  setupEventListeners();

  applyConfigState();
  updateSavedButton();
  resetMetricUI();
  syncPanels();
  updateCameraUI();
  updateStartButton();

  if (isDev) installDevHelpers();
}

init().catch((error) => {
  console.error('[breathe-garden] Initialization failed:', error);
  showConsentNotice(
    `Breathe Garden could not initialize: ${error?.message || error}`,
    true,
  );
});
