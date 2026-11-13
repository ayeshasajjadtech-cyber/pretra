# Breathe Garden: a living landscape shaped by your breathing and pulse

**Tags:** `#presagechallenge`

**Challenge categories:** Most Creative or Delightful Use · Best Thoughtful Real-World Use

## The idea

Most physiological dashboards ask you to read numbers. Breathe Garden asks you to watch a small world respond.

I built an Electron desktop app that uses the Presage SmartSpectra SDK to turn live breathing and pulse estimates into a generative landscape. Your breathing rate slowly shapes the sky and the growth of the garden. Your pulse adds small pulses of light and energy to the flowers. When the signal is calm and stable, the landscape settles into a slower, more coherent rhythm.

It is intentionally not a medical interface. It is a quiet, consent-first ritual: a way to notice your own rhythm without turning it into a score.

## Why this use case

Breathing and pulse are familiar, everyday signals, but they are usually presented as numbers, charts, or warnings. I wanted to explore a different relationship with them: ambient, creative, and non-judgmental.

The design goals were:

- Make the experience feel alive without making it feel clinical.
- Keep the camera and data handling explicit and consent-first.
- Use only breathing and pulse; no facial expressions, emotion inference, or diagnosis.
- Make the experience degrade gracefully when the signal is poor.
- Leave a small, private record only if the user asks for one.

## How it works

Breathe Garden is built with Electron and a sandboxed renderer. The SmartSpectra SDK runs through its renderer integration and is bound to the main process with `bindSmartSpectraIpc`.

The SDK is configured with:

```js
new SmartSpectraSDK({
  apiKey,
  requestedMetrics: [...breathingMetrics, ...cardioMetrics],
  enableAccumulatedOutput: false,
  enableTelemetry: false,
});
```

The app decodes metrics with `decodeMetrics` and passes them into a small signal engine that handles:

- freshness and confidence thresholds
- range validation
- smoothing
- sparkline and trace history
- session summaries
- HRV only after 60 seconds of stable session data

The landscape is a Canvas 2D scene with layered sky, hills, mist, grass, flowers, and fireflies. Breathing drives the slow motion of the scene and the growth of the garden. Pulse drives smaller, faster pulses of light. If the signal becomes stale, the scene relaxes back toward an ambient state instead of pretending the data is still live.

## Consent and privacy

The camera stays off until the user checks a consent box and presses **Start breathing garden**. A visible **Stop camera** button is always available while a session is running.

The app does not save video, images, or raw camera frames. Session summaries stay in memory by default. If the user chooses to save one, the app stores only summary numbers in local storage on that device, and the user can delete them at any time.

The SDK's aggregate telemetry is disabled with `enableTelemetry: false`. Even with telemetry off, the SDK still contacts Presage for API-key authentication and service validation. That can involve network metadata such as IP address, app credentials, attestation data, hashed device identifiers, and SDK version. I disclosed that explicitly in the app and the README instead of claiming the app is fully offline.

Breathe Garden does not call AI Insights and does not request facial expressions. It is not a medical device.

## What is tested

On this machine, I verified:

- dependency installation
- the esbuild renderer/preload build
- 21 unit tests for smoothing, signal gating, traces, summaries, and error mapping
- an Electron smoke run using the development-only simulated source
- the simulated session reaching a live, stable state and producing a screenshot

The live camera path is implemented but has not been verified end-to-end without a real Presage API key. I am treating that as unverified rather than claiming it works.

## Challenges

The most interesting constraint was making the experience honest about uncertainty. Physiological signals arrive at different rates, with different confidence levels, and sometimes not at all. The landscape should not imply that a reading is valid when it is stale or low-confidence. The signal engine therefore separates “visual signal” from “valid reading”: the garden can still move gently with a low-confidence trace, while the UI refuses to show a number until the reading is fresh, stable, and in range.

Another constraint was Windows camera selection. Forcing `CameraSelection.front` or `CameraSelection.back` can fail with `kInputUnavailable`, so the app leaves selection to the SDK's default/discovered camera path.

## What is next

- Verify a real live session with a Presage API key and camera.
- Test lighting, motion, no-face, and camera-busy states on Windows.
- Confirm cardio/HRV entitlement on the account used for the demo.
- Add packaging/signing and a production smoke check.
- Record the 60–90 second demo.

## Built with

- Electron
- Node.js
- Presage SmartSpectra Node SDK
- Canvas 2D
- esbuild

The project is intentionally small and readable. The SmartSpectra integration is isolated in one module so the rest of the app can be understood and tested without a camera.
