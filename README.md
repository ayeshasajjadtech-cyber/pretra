# PreTra Desktop

PreTra is a Windows desktop wellness experience that displays live SmartSpectra pulse and breathing estimates from a webcam session.

## Configure and run

1. Install the Flutter Windows desktop toolchain and the Presage SmartSpectra Windows runtime.
2. Put the licensed SmartSpectra runtime DLLs and `graph` assets in `windows/runner/native/`.
3. Create a local `.env` file with `SMARTSPECTRA_API_KEY=your_key` (do not commit the key).
4. Run `flutter run -d windows` during development, or build a distributable with `flutter build windows --release`.

The Windows CMake install rules stage the SDK DLLs and graph assets beside the application executable. The SDK DLLs must match the target architecture and include all licensed runtime dependencies.

## Session records

Each session receives an automatically incremented record number (for example, `P-000001`). This numbers recordings only; it does not identify a person or link the same person across sessions. Sessions and stable telemetry samples are persisted in SQLite under `%APPDATA%\PreTra\pretra_sessions.sqlite`; session samples are written during capture, and a session still marked `recording` on the next app start is retained as `interrupted`. The previous `%APPDATA%\PreTra\saved_summaries.json` file is imported once and kept as a migration backup. The home screen's **Session history** action filters records by record number and exports summaries or time-series CSVs under `Documents\PreTra\exports`.

PreTra stores SDK estimates and the SDK confidence value it reports; confidence is not measurement accuracy. Recording a session does not store webcam video. The local SQLite database is not encrypted and is not shared across computers. Treat its contents as sensitive, limit access to the Windows account, and clear test records when appropriate. It is not a centralized participant record system.

## Accuracy evaluation

See [docs/accuracy-validation.md](docs/accuracy-validation.md) for the paired reference protocol and `dart tool/accuracy_eval.dart <paired-session-csv>` for MAE, RMSE, signed bias, and paired-row coverage. The evaluator requires manually paired reference values; it does not create ground truth. A BP monitor can provide a pulse comparison, not a breathing reference. The SDK's confidence output and a visually plausible waveform do not establish accuracy, and this app does not promise 100% accuracy.
