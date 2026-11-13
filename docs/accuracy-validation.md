# PreTra reference comparison

The comparison tool summarizes paired values. It does not certify SmartSpectra, infer accuracy from SDK confidence, or turn a BP reading into a breathing reference.

## Protocol

1. Obtain the participant's consent and use a non-identifying record number.
2. Use a synchronized, suitable reference for each metric. A BP monitor's displayed pulse can be used for a pulse comparison, but its blood-pressure result does not validate breathing rate. Use a respiratory belt or another suitable breathing reference for that metric.
3. Compare readings taken at the same time and under steady conditions. Do not copy one reference value into multiple adjacent one-second rows; each row in the analysis is treated as an independent pair.
4. Export one session's time series from **Session history**. Fill `Reference_Pulse_Rate_BPM` and/or `Reference_Breathing_Rate_BRM` only on the row paired to the corresponding independent reference reading. If a reference attempt has no usable PreTra value, add a row with the reference filled and the PreTra field blank. Do not count an SDK confidence score as a reference measurement.
5. Run the analyzer and retain the filled CSV with the test protocol and device/setup notes.

```powershell
dart tool/accuracy_eval.dart "C:\path\to\paired-session.csv"
```

The report gives pair count, paired-row coverage, mean absolute error, root mean squared error, and signed bias (`PreTra estimate - reference`). Coverage is calculated only over rows where a reference value was entered; it is **not** the fraction of the entire session with usable camera readings. This time-series export contains stable SDK samples, so a complete camera-availability percentage requires a separate per-second availability/event log.

Report results per metric and per participant/session as well as aggregate values. Keep the reference protocol, sample count, unusable attempts, lighting, motion, camera model, and software/SDK versions with the results. A BP monitor provides no breathing ground truth. Do not report a universal accuracy percentage from a small pilot or a single paired reading.
