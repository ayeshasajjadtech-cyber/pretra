# Breathe Garden

Breathe Garden is an Electron desktop app that turns live breathing and pulse estimates from the Presage SmartSpectra SDK into a quiet, generative landscape. It is a creative experience, not a medical device.

The app is consent-first: the camera stays off until you explicitly start a session, a visible Stop camera button is always available during a session, and video/images/raw frames are never saved by the app.

## Status

This is a development build prepared for the Presage SmartSpectra SDK Challenge.

Tested on this machine:

- `npm install`
- `npm run build`
- `npm test` (21 unit tests)
- `npm run smoke` (Electron 43.8.7 smoke run with the development-only simulated source)
- `npm audit` (0 vulnerabilities)

Not yet verified on this machine:

- Live SmartSpectra camera session with a real API key
- Real camera permission, lighting, motion, and face-positioning states
- Cardio/HRV entitlement on the Presage account
- Packaged production build

The live SDK path is implemented, but it has not been exercised end-to-end without a real `SMARTSPECTRA_API_KEY`.

## Requirements

- Node.js 24.x (verified with 24.21.0)
- npm 11.x (verified with 11.19.0)
- Windows 10/11, macOS, or Linux with a working camera
- A Presage SmartSpectra API key

## Setup

1. Install dependencies:

   ```powershell
   npm install
   ```

2. Create `.env` from the example:

   ```powershell
   Copy-Item .env.example .env
   ```

3. Put your key in `.env`:

   ```dotenv
   SMARTSPECTRA_API_KEY=your_key_here
   ```

   Never commit `.env`. The key is read in the Electron main process and is not written into source, the renderer bundle, or logs.

4. Build the renderer and preload bundles:

   ```powershell
   npm run build
   ```

5. Start the app:

   ```powershell
   npm start
   ```

   `npm start` runs the build first, then launches Electron.

Create or manage keys at the Presage physiology portal: <https://physiology.presagetech.com/auth/register>.

## Tests

```powershell
npm test
```

The unit tests cover signal smoothing, stale/confidence gating, trace normalization, HRV's 60-second summary gate, and SDK/validation error mapping.

## Smoke Test

```powershell
npm run smoke
```

The smoke run launches Electron hidden, enables the development-only simulated source, waits for live simulated metrics, captures a screenshot, and writes:

- `docs/screenshots/smoke.png`
- `docs/screenshots/smoke-result.json`

The smoke path is for development verification only. It does not test the real camera or the Presage service.

## How It Works

```text
main.js
  - creates the sandboxed BrowserWindow
  - loads .env
  - binds SmartSpectra IPC with bindSmartSpectraIpc(window)
  - exposes only a small config bridge to the renderer

preload.js
  - loads @smartspectra/node-sdk/preload
  - exposes window.breatheGarden.getConfig()

src/renderer/app.mjs
  - consent and session state machine
  - starts/stops the SDK source
  - updates the UI, summary, and saved-session list

src/renderer/sdk/smartspectra.mjs
  - the only module that talks to SmartSpectra
  - requests breathing + cardio metrics
  - decodes metric payloads and forwards events

src/renderer/signals/engine.mjs
  - freshness, confidence, and range gating
  - sparkline/trace history
  - session summary calculation

src/renderer/visual/landscape.mjs
  - Canvas 2D generative landscape
  - breathing drives slow growth and sky motion
  - pulse drives small luminous pulses and flower energy
```

### SmartSpectra integration

The renderer SDK is created with:

```js
new SmartSpectraSDK({
  apiKey,
  requestedMetrics: [...breathingMetrics, ...cardioMetrics],
  enableAccumulatedOutput: false,
  enableTelemetry: false,
});
```

The app listens for:

- `processingStatus`
- `validationStatus`
- `metrics`
- `streamAvailable`
- `error`

Metrics are decoded with `decodeMetrics` from `@smartspectra/node-sdk/messages`. The engine treats each metrics payload as containing only the samples since the previous callback, so it appends history rather than re-accumulating old values.

The Content Security Policy includes `worker-src 'self' blob:` because the SDK uses a worker.

### Windows camera selection

On Windows, `CameraSelection.front` and `CameraSelection.back` can fail with `kInputUnavailable`. Breathe Garden leaves camera selection to the SDK's default/discovered camera path instead of forcing front/back selection.

## Consent and Data Handling

Breathe Garden is designed around informed consent and data minimization.

### What the app does

- The camera stays off until you check the consent box and press **Start breathing garden**.
- A visible **Stop camera** button is always available while a session is running.
- The app does not save video, images, or raw camera frames.
- The app shows only breathing and pulse estimates. It does not request facial expressions or emotion analysis.
- Session summaries stay in memory by default.
- If you choose **Save locally**, the app stores only summary numbers in this app's local storage on this device.
- Saved summaries can be deleted individually or all at once from **Saved sessions**.
- The app does not make medical claims.

### What the Presage SmartSpectra SDK does

The app sets `enableTelemetry: false` to opt out of the SDK's aggregate telemetry. According to the SDK documentation, that telemetry is an aggregate session summary and excludes raw video/images, metric values, and user/stable device IDs.

Even with telemetry disabled, the SDK contacts Presage for API-key authentication and subscription/service validation. That validation may involve network metadata such as:

- IP address
- app credentials
- attestation data
- hashed device identifiers
- SDK version

Breathe Garden does not call `requestInsight` or the AI Insights feature, and the app itself does not send metric values to Presage.

Do not describe this app as fully offline or as “no data leaves your device.” The honest statement is:

> Breathe Garden stores no video or raw frames and disables the SDK's aggregate telemetry, but the SDK still contacts Presage for API-key authentication and service validation.

### Local summary storage

If you save a summary, it is stored under this local-storage key:

```text
breatheGarden.savedSummaries.v1
```

Each entry contains only:

- a random id
- save timestamp
- session duration
- average breathing rate
- average pulse rate
- optional HRV RMSSD
- app version

Up to 50 entries are kept. The app never stores video, images, raw frames, or trace arrays in local storage.

### HRV

HRV (RMSSD) is shown only in summaries after at least 60 seconds of session time and only when the SDK provides a stable HRV sample. It is a summary number, not a diagnosis or medical assessment.

## Failure Handling

The app maps SDK errors and validation hints to friendly messages for:

- missing API key
- SDK native module load failure
- camera denied, unavailable, or busy
- no face / multiple faces
- poor lighting
- too much motion
- authentication, network, and service errors
- exhausted measurement credits
- stale or low-confidence signals

If the camera is not providing a usable signal, the app returns to the consent screen and explains what happened. Retry is offered when it is safe to retry.

## Development-Only Simulated Mode

The simulated source exists only to test the UI and smoke path without a camera or API key.

- It is available only when the app is not packaged and the page is opened with `?simulate=1`.
- It is visibly labeled **Simulated signal — development only**.
- Simulated summaries cannot be saved.
- It must not be used in the challenge demo.

## Project Structure

```text
main.js                         Electron main process
preload.js                      context-isolated SDK/config bridge
index.html                      app shell
styles.css                      visual design
src/renderer/app.mjs            renderer state machine and UI
src/renderer/sdk/smartspectra.mjs
src/renderer/sdk/error-messages.mjs
src/renderer/signals/smoothing.mjs
src/renderer/signals/engine.mjs
src/renderer/visual/landscape.mjs
src/renderer/simulated.mjs
scripts/build.mjs               esbuild renderer/preload build
scripts/smoke.mjs               Electron smoke harness
test/*.test.mjs                 unit tests
docs/DEV_POST.md                challenge post draft
docs/DEMO_SCRIPT.md             60–90 second demo script
```

## Troubleshooting

### `SMARTSPECTRA_API_KEY is missing from .env`

Create `.env` from `.env.example` and add your key, then restart the app. Do not paste the key into source or chat.

### SDK failed to load

The native SDK or its platform binary may not be installed correctly. Re-run `npm install`. On machines where npm blocks install scripts, approve the required packages and reinstall:

```powershell
npm install-scripts approve esbuild koffi protobufjs
npm install
```

If the Electron binary is missing:

```powershell
node node_modules/electron/install.js
```

### Camera unavailable

Close other apps that use the camera, check Windows camera privacy settings, and try again. On Windows, do not force front/back camera selection; use the default/discovered camera.

### No stable signal

Sit comfortably, keep one face in frame, add soft even light, reduce motion, and keep your upper body visible. Breathing rate typically needs about 30 seconds and pulse about 12 seconds to stabilize.

### Credits exhausted

The Presage account may have no remaining measurement credits. Check the Presage plan or add credits.

### Cardio or HRV is unavailable

Breathe Garden requests both breathing and cardio metrics. If the API key is not provisioned for cardio, SDK configuration may fail. Check the key's plan/permissions in the Presage portal. Breathing-only fallback is not implemented yet.

## Limitations

- Estimates are for a creative experience only and are not medical measurements.
- The landscape is intentionally abstract; it does not display a medical chart.
- Live camera behavior and cardio/HRV entitlement still need verification with a real key and camera.
- Packaging/signing is not set up yet.
