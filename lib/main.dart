import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'src/config.dart';
import 'src/engine/lighting_recovery_engine.dart';
import 'src/ffi/smartspectra_bridge.dart';
import 'src/models.dart';
import 'src/saved_store.dart';
import 'src/signal_engine.dart';
import 'src/ui/telemetry_history_dialog.dart';
import 'src/ui/recovery_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final AppConfig config = AppConfig.load();
  runApp(PreTraApp(config: config));
}

/// Palette constants matching the glowing cyan/emerald logo
class AppColors {
  static const Color background = Color(0xFF050B14);
  static const Color surfaceGlass = Color(0xCC09172A);
  static const Color neonCyan = Color(0xFF00E5FF);
  static const Color neonEmerald = Color(0xFF00E676);
  static const Color neonAmber = Color(0xFFFFD54F);
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
}

class PreTraApp extends StatelessWidget {
  const PreTraApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PreTra',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.neonCyan,
          secondary: AppColors.neonEmerald,
          surface: AppColors.surfaceGlass,
        ),
      ),
      home: ConsentScreen(config: config),
    );
  }
}

/// Alias for backwards compatibility
typedef BreatheGardenApp = PreTraApp;

/// ---- Consent / Welcome Screen with 3D glowing logo ----
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, required this.config});

  final AppConfig config;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;
  final SavedSummaryStore _savedStore = SavedSummaryStore();
  bool _startingSession = false;
  bool _hasUserConsent = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _handleStart() async {
    if (!_hasUserConsent) return;
    if (!widget.config.hasApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add SMARTSPECTRA_API_KEY to .env, then restart PreTra to start the live camera.',
          ),
        ),
      );
      return;
    }

    setState(() => _startingSession = true);
    final startedAt = DateTime.now().toUtc();
    final sessionId = 'PT-${startedAt.microsecondsSinceEpoch}';
    try {
      await _savedStore.initialize();
      final recordNumber = await _savedStore.nextRecordNumber();
      await _savedStore.beginSession(
        id: sessionId,
        recordNumber: recordNumber,
        startedAt: startedAt,
        appVersion: AppConfig.appVersion,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 700),
          pageBuilder: (_, animation, _) => FadeTransition(
            opacity: animation,
            child: SessionScreen(
              config: widget.config,
              recordNumber: recordNumber,
              sessionId: sessionId,
              startedAt: startedAt,
              savedStore: _savedStore,
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to create a session record: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _startingSession = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background ambient gradient glow
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _glowController,
              builder: (context, _) {
                final breath = _glowController.value;
                return Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.35),
                      radius: 0.9 + breath * 0.25,
                      colors: [
                        AppColors.neonCyan.withValues(
                          alpha: 0.12 + breath * 0.08,
                        ),
                        AppColors.neonEmerald.withValues(
                          alpha: 0.06 + breath * 0.04,
                        ),
                        AppColors.background,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                );
              },
            ),
          ),

          // Main content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 28.0,
                vertical: 36.0,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 3D Glowing App Logo
                    _buildGlowingLogo(),
                    const SizedBox(height: 28),

                    // Title with gradient shader
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [AppColors.neonCyan, AppColors.neonEmerald],
                      ).createShader(bounds),
                      child: const Text(
                        'PRETRA',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.5,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Live Desktop Biometrics & Respiration • Powered by Presage SmartSpectra',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),

                    // Feature highlights cards
                    _buildFeatureCard(
                      icon: Icons.air_rounded,
                      iconColor: AppColors.neonCyan,
                      title: 'Harmonic Respiration Tracking',
                      description:
                          'Real-time webcam chest motion tracking captures respiratory rate, breathing depth, and cadence.',
                    ),
                    const SizedBox(height: 12),
                    _buildFeatureCard(
                      icon: Icons.monitor_heart_rounded,
                      iconColor: AppColors.neonEmerald,
                      title: 'Webcam Plethysmography (PPG)',
                      description:
                          'Captures micro-capillary blood pulse variance from facial pixels to drive pulsing light rings and vitality waveforms.',
                    ),
                    const SizedBox(height: 12),
                    _buildFeatureCard(
                      icon: Icons.wb_incandescent_outlined,
                      iconColor: AppColors.neonAmber,
                      title: 'Adaptive Lighting Recovery',
                      description:
                          'Intelligent quality monitoring detects shadows or dim lighting and guides you back into optimal signal range.',
                    ),
                    const SizedBox(height: 24),

                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceGlass,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        child: CheckboxListTile(
                          value: _hasUserConsent,
                          onChanged: (value) =>
                              setState(() => _hasUserConsent = value ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppColors.neonCyan,
                          title: const Text(
                            'I agree to start a webcam session',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'PreTra saves session estimates and SDK confidence locally. Webcam frames are used for live processing and are not saved.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Action Button
                    _buildStartButton(),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () =>
                          TelemetryHistoryDialog.show(context, _savedStore),
                      icon: const Icon(Icons.manage_history_rounded, size: 18),
                      label: const Text('Session history'),
                    ),
                    const SizedBox(height: 18),

                    // Disclaimer text (Policy Compliance)
                    const Text(
                      'A wellness-focused experience for mindful breathing and personal reflection.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowingLogo() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, _) {
        final breath = _glowController.value;
        return Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: AppColors.neonCyan.withValues(
                  alpha: 0.35 + breath * 0.25,
                ),
                blurRadius: 36 + breath * 20,
                spreadRadius: 2 + breath * 6,
              ),
              BoxShadow(
                color: AppColors.neonEmerald.withValues(
                  alpha: 0.25 + breath * 0.2,
                ),
                blurRadius: 48 + breath * 24,
                spreadRadius: 4 + breath * 8,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer rotating ring effect
              Transform.rotate(
                angle: breath * math.pi * 0.1,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: AppColors.neonCyan.withValues(
                        alpha: 0.4 + breath * 0.3,
                      ),
                      width: 2,
                    ),
                  ),
                ),
              ),
              // App Logo Image
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/logo.png',
                  width: 132,
                  height: 132,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [AppColors.neonCyan, AppColors.neonEmerald],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonCyan.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: _startingSession || !_hasUserConsent ? null : _handleStart,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_startingSession)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF03101C),
                ),
              )
            else
              const Icon(
                Icons.play_arrow_rounded,
                color: Color(0xFF03101C),
                size: 24,
              ),
            const SizedBox(width: 10),
            Text(
              _startingSession ? 'Preparing session…' : 'Launch PreTra Session',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: Color(0xFF03101C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---- Session Screen with live camera preview and telemetry ----
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.config,
    required this.recordNumber,
    required this.sessionId,
    required this.startedAt,
    required this.savedStore,
  });

  final AppConfig config;
  final String recordNumber;
  final String sessionId;
  final DateTime startedAt;
  final SavedSummaryStore savedStore;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final SignalEngine _engine;
  SmartSpectraBridge? _bridge;
  LightingRecoveryEngine? _recoveryEngine;
  StreamSubscription? _metricsSub;
  StreamSubscription<CameraVideoFrame>? _videoSub;
  StreamSubscription<String>? _nativeErrorSub;
  Timer? _uiRefreshTimer;
  Timer? _previewTimer;
  DateTime? _cameraStartedAt;
  DateTime? _lastCameraFrameAt;

  bool _isLiveActive = false;
  bool _liveSdkStarted = false;
  bool _nativeSdkError = false;
  bool _isPaused = false;
  String? _cameraError;
  bool _previewUnavailable = false;
  bool _everReceivedCameraFrame = false;
  double _lastSignalQuality = 0;
  CameraVideoFrame? _cameraFrame;
  Future<void> _storageQueue = Future<void>.value();
  String? _storageError;
  int _lastRecordedSecond = -1;
  int _lastRecordedAtMs = 0;
  bool _sessionEnded = false;
  DateTime? _pauseStartedAt;
  int _pausedDurationMs = 0;

  @override
  void initState() {
    super.initState();
    _engine = SignalEngine();
    _engine.startSession();
    if (widget.config.hasApiKey) {
      _startLiveCameraBridge();
    } else {
      _cameraError = 'Add SMARTSPECTRA_API_KEY to .env and restart PreTra.';
    }

    _uiRefreshTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && !_isPaused) {
        final snapshot = _engine.getSnapshot();
        final breathingQuality = snapshot.breathing.fresh
            ? snapshot.breathing.confidence
            : 0.0;
        final pulseQuality = snapshot.pulse.fresh
            ? snapshot.pulse.confidence
            : 0.0;
        setState(() {
          _lastSignalQuality = breathingQuality > pulseQuality
              ? breathingQuality
              : pulseQuality;
        });
      }
    });
  }

  void _recordStableSample(EngineSnapshot snapshot) {
    if (_sessionEnded) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Only sample in response to SDK metric callbacks; this prevents storing
    // repeated copies of a held value while the native stream is quiet.
    if (nowMs - _lastRecordedAtMs < 1000) return;
    final second = _activeDurationMs() ~/ 1000;
    if (second <= _lastRecordedSecond) return;
    final breathing = snapshot.breathing;
    final pulse = snapshot.pulse;
    final breathingValue =
        breathing.valid && breathing.fresh && breathing.stable
        ? breathing.value
        : null;
    final pulseValue = pulse.valid && pulse.fresh && pulse.stable
        ? pulse.value
        : null;
    if (breathingValue == null && pulseValue == null) return;
    _lastRecordedAtMs = nowMs;
    _lastRecordedSecond = second;
    final availableConfidence = <double>[
      if (breathingValue != null) breathing.confidence,
      if (pulseValue != null) pulse.confidence,
    ];
    final meanConfidence =
        availableConfidence.reduce((a, b) => a + b) /
        availableConfidence.length;
    final point = TelemetryPoint(
      elapsedSec: second,
      timestampIso: DateTime.now().toUtc().toIso8601String(),
      breathingRate: breathingValue,
      pulseRate: pulseValue,
      signalQuality: meanConfidence,
      confidence: meanConfidence,
    );
    _storageQueue = _storageQueue
        .then((_) => widget.savedStore.appendSample(widget.sessionId, point))
        .catchError((Object error) {
          _storageError ??= error.toString();
          debugPrint('[PreTra Storage Error] $_storageError');
        });
  }

  int _activeDurationMs([DateTime? now]) {
    final wallDuration = _engine.getSnapshot().durationMs;
    final activePauseMs = _isPaused && _pauseStartedAt != null
        ? (now ?? DateTime.now()).difference(_pauseStartedAt!).inMilliseconds
        : 0;
    return math.max(0, wallDuration - _pausedDurationMs - activePauseMs);
  }

  void _startLiveCameraBridge() {
    try {
      final bridge = SmartSpectraBridge();
      _bridge = bridge;
      _recoveryEngine = LightingRecoveryEngine(
        qcStream: bridge.qualityControlStream,
      );
      _nativeErrorSub = bridge.nativeErrorStream.listen((message) {
        if (!mounted) return;
        setState(() {
          _nativeSdkError = true;
          _cameraError = message;
          _isLiveActive = false;
          _previewUnavailable = true;
        });
      });
      _metricsSub = bridge.telemetryStream.listen((metrics) {
        if (!_isPaused) {
          _engine.ingestMetrics(metrics, DateTime.now().millisecondsSinceEpoch);
          _recordStableSample(_engine.getSnapshot());
        }
      });
      _videoSub = bridge.videoFrameStream.listen((frame) {
        if (mounted) {
          setState(() {
            _cameraFrame = frame;
            _lastCameraFrameAt = DateTime.now();
            _previewUnavailable = false;
            _everReceivedCameraFrame = true;
          });
        }
      });

      bridge
          .start(apiKey: widget.config.apiKey)
          .then((_) {
            if (mounted) {
              setState(() {
                _bridge = bridge;
                _isLiveActive = true;
                _liveSdkStarted = true;
              });
              _cameraStartedAt = DateTime.now();
              _previewTimer?.cancel();
              _previewTimer = Timer.periodic(const Duration(seconds: 1), (_) {
                if (!mounted) return;
                final lastFrameAt = _lastCameraFrameAt;
                final reference = lastFrameAt ?? _cameraStartedAt;
                if (reference == null) return;
                final staleAfter = lastFrameAt == null
                    ? const Duration(seconds: 8)
                    : const Duration(seconds: 2);
                final unavailable =
                    DateTime.now().difference(reference) > staleAfter;
                if (unavailable != _previewUnavailable) {
                  setState(() {
                    _previewUnavailable = unavailable;
                    if (unavailable) _cameraFrame = null;
                  });
                }
              });
            }
          })
          .catchError((error) {
            debugPrint('[PreTra Bridge Startup Error] $error');
            _bridge = null;
            unawaited(bridge.dispose());
            if (mounted) {
              setState(() {
                _isLiveActive = false;
                _cameraError = error.toString();
              });
            }
          });
    } catch (e) {
      debugPrint('[PreTra Bridge Exception] $e');
      _cameraError = e.toString();
    }
  }

  void _retryCamera() {
    _previewTimer?.cancel();
    final previousBridge = _bridge;
    _bridge = null;
    if (previousBridge != null) unawaited(previousBridge.dispose());
    _metricsSub?.cancel();
    _videoSub?.cancel();
    _nativeErrorSub?.cancel();
    _recoveryEngine?.dispose();
    setState(() {
      _cameraError = null;
      _previewUnavailable = false;
      _isLiveActive = false;
      _cameraFrame = null;
      _cameraStartedAt = null;
      _lastCameraFrameAt = null;
    });
    _startLiveCameraBridge();
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    _previewTimer?.cancel();
    _metricsSub?.cancel();
    _videoSub?.cancel();
    _nativeErrorSub?.cancel();
    _bridge?.dispose();
    _recoveryEngine?.dispose();
    super.dispose();
  }

  Future<void> _showSummaryDialog() async {
    if (_sessionEnded) return;
    _sessionEnded = true;
    _uiRefreshTimer?.cancel();
    final activeBridge = _bridge;
    _bridge = null;
    await _metricsSub?.cancel();
    await _videoSub?.cancel();
    await _nativeErrorSub?.cancel();
    if (activeBridge != null) await activeBridge.dispose();
    final rawSummary = _engine.getSummary(null, false);
    final activeDurationMs = _activeDurationMs();
    final hrvEligible = activeDurationMs >= hrvMinSessionMs;
    final summary = SessionSummary(
      durationMs: activeDurationMs,
      breathingAvg: rawSummary.breathingAvg,
      pulseAvg: rawSummary.pulseAvg,
      hrvRmssd: hrvEligible ? rawSummary.hrvRmssd : null,
      hrvEligible: hrvEligible && rawSummary.hrvEligible,
      sampleCounts: rawSummary.sampleCounts,
      hasData: rawSummary.hasData,
      simulated: rawSummary.simulated,
    );
    await _storageQueue;
    final status = _storageError != null
        ? 'storage_error'
        : _nativeSdkError
        ? 'sdk_error'
        : !_liveSdkStarted
        ? 'camera_unavailable'
        : summary.hasData
        ? 'completed'
        : 'no_stable_readings';
    try {
      await widget.savedStore.completeSession(
        SavedSummary(
          id: widget.sessionId,
          recordNumber: widget.recordNumber,
          savedAt: widget.startedAt,
          durationMs: summary.durationMs,
          breathingAvg: summary.breathingAvg,
          pulseAvg: summary.pulseAvg,
          hrvRmssd: summary.hrvRmssd,
          appVersion: AppConfig.appVersion,
          signalQualityAvg: null,
          isLiveCamera: _liveSdkStarted,
          previewReceived: _everReceivedCameraFrame,
          status: status,
        ),
      );
    } catch (error) {
      _storageError ??= error.toString();
      debugPrint('[PreTra Storage Error] $_storageError');
    }
    if (!mounted) return;
    final durationSec = (summary.durationMs / 1000).round();
    final mins = durationSec ~/ 60;
    final secs = durationSec % 60;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: AppColors.neonCyan.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.neonEmerald.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: AppColors.neonEmerald,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'PreTra Session Completed',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Duration: ${mins > 0 ? '$mins min ' : ''}$secs sec',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _storageError == null
                      ? 'Record ${widget.recordNumber} saved on this device.'
                      : 'Record could not be fully saved: $_storageError',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: _storageError == null
                        ? AppColors.textSecondary
                        : AppColors.neonAmber,
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSummaryItem(
                      label: 'Avg Breath',
                      value: summary.breathingAvg != null
                          ? '${summary.breathingAvg!.toStringAsFixed(1)} BRM'
                          : '—',
                      color: AppColors.neonCyan,
                    ),
                    _buildSummaryItem(
                      label: 'Avg Pulse',
                      value: summary.pulseAvg != null
                          ? '${summary.pulseAvg!.toStringAsFixed(0)} BPM'
                          : '—',
                      color: AppColors.neonEmerald,
                    ),
                    _buildSummaryItem(
                      label: 'SDK confidence',
                      value: _lastSignalQuality > 0
                          ? '${_lastSignalQuality.toStringAsFixed(0)}%'
                          : '—',
                      color: AppColors.neonAmber,
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonCyan,
                      foregroundColor: const Color(0xFF03101C),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConsentScreen(config: widget.config),
                        ),
                      );
                    },
                    child: const Text(
                      'Back to Home',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryItem({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _engine.getSnapshot();
    final breathRate = snapshot.breathing.value?.toStringAsFixed(1) ?? '—';
    final pulseRate = snapshot.pulse.value?.toStringAsFixed(0) ?? '—';
    final confidence =
        (snapshot.breathing.confidence > snapshot.pulse.confidence
                ? snapshot.breathing.confidence
                : snapshot.pulse.confidence)
            .toStringAsFixed(0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Stable background keeps the telemetry readable and avoids motion.
          Positioned.fill(
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF07131C),
                    Color(0xFF081D24),
                    Color(0xFF07131C),
                  ],
                ),
              ),
            ),
          ),

          // 2. Dynamic Lighting Failure-Recovery Overlay
          Positioned(
            top: 140,
            left: 24,
            right: 220,
            bottom: 86,
            child: _CameraPreviewPanel(
              frame: _cameraFrame,
              live: _isLiveActive && !_previewUnavailable,
              error: _cameraError,
              previewUnavailable: _previewUnavailable,
              breathingReady: snapshot.breathing.valid,
              pulseReady: snapshot.pulse.valid,
              cameraElapsed: _cameraStartedAt == null
                  ? Duration.zero
                  : DateTime.now().difference(_cameraStartedAt!),
              qualityStatus: _recoveryEngine?.latestQualityStatus,
              onRetry: _retryCamera,
            ),
          ),

          // 3. Dynamic Lighting Failure-Recovery Overlay
          if (_recoveryEngine != null)
            Positioned.fill(
              child: LightingRecoveryOverlay(engine: _recoveryEngine!),
            ),

          // 3. Top Floating Glassmorphism Header Bar
          Positioned(top: 18, left: 20, right: 20, child: _buildTopHeaderBar()),

          // 4. Right Floating Biometric Telemetry Cards
          Positioned(
            top: 90,
            right: 20,
            child: _buildBiometricPanel(
              breathRate: '$breathRate /min',
              heartRate: '$pulseRate BPM',
              quality: _lastSignalQuality > 0 ? '$confidence%' : '—',
            ),
          ),

          // Bottom control bar.
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeaderBar() {
    final previewActive =
        _isLiveActive && !_previewUnavailable && _cameraFrame != null;
    final statusColor = previewActive
        ? AppColors.neonEmerald
        : AppColors.neonAmber;
    final statusLabel = !_isLiveActive
        ? _cameraError == null
              ? 'CONNECTING CAMERA'
              : 'CAMERA UNAVAILABLE'
        : _previewUnavailable
        ? 'PREVIEW NOT RECEIVED'
        : previewActive
        ? 'LIVE CAMERA PREVIEW'
        : 'WAITING FOR PREVIEW';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.neonCyan.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/logo.png',
              width: 36,
              height: 36,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PRETRA',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'Presage SmartSpectra Desktop Engine',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
              Text(
                'SESSION ${widget.recordNumber}',
                style: TextStyle(fontSize: 9, color: AppColors.neonCyan),
              ),
            ],
          ),
          const Spacer(),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricPanel({
    required String breathRate,
    required String heartRate,
    required String quality,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildMetricCard(
          icon: Icons.air_rounded,
          iconColor: AppColors.neonCyan,
          label: 'RESPIRATION',
          value: breathRate,
        ),
        const SizedBox(height: 10),
        _buildMetricCard(
          icon: Icons.favorite_rounded,
          iconColor: AppColors.neonEmerald,
          label: 'PULSE RATE',
          value: heartRate,
        ),
        const SizedBox(height: 10),
        _buildMetricCard(
          icon: Icons.auto_awesome_rounded,
          iconColor: AppColors.neonAmber,
          label: 'SDK CONFIDENCE',
          value: quality,
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      width: 165,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withValues(alpha: 0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: iconColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.neonEmerald.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(
              _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: AppColors.neonAmber,
              size: 26,
            ),
            tooltip: _isPaused ? 'Resume Session' : 'Pause Session',
            onPressed: () {
              final now = DateTime.now();
              setState(() {
                if (_isPaused) {
                  final pausedAt = _pauseStartedAt;
                  if (pausedAt != null) {
                    _pausedDurationMs += now
                        .difference(pausedAt)
                        .inMilliseconds;
                  }
                  _pauseStartedAt = null;
                  _isPaused = false;
                } else {
                  _pauseStartedAt = now;
                  _isPaused = true;
                }
              });
            },
          ),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48).withValues(alpha: 0.85),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text(
              'End Session',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: _showSummaryDialog,
          ),
        ],
      ),
    );
  }
}

class _CameraPreviewPanel extends StatefulWidget {
  const _CameraPreviewPanel({
    required this.frame,
    required this.live,
    required this.error,
    required this.previewUnavailable,
    required this.breathingReady,
    required this.pulseReady,
    required this.cameraElapsed,
    required this.qualityStatus,
    required this.onRetry,
  });

  final CameraVideoFrame? frame;
  final bool live;
  final String? error;
  final bool previewUnavailable;
  final bool breathingReady;
  final bool pulseReady;
  final Duration cameraElapsed;
  final QualityControlStatus? qualityStatus;
  final VoidCallback onRetry;

  @override
  State<_CameraPreviewPanel> createState() => _CameraPreviewPanelState();
}

class _CameraPreviewPanelState extends State<_CameraPreviewPanel> {
  ui.Image? _image;
  int _decodeGeneration = 0;

  @override
  void initState() {
    super.initState();
    final frame = widget.frame;
    if (frame != null) _decode(frame);
  }

  @override
  void didUpdateWidget(covariant _CameraPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final frame = widget.frame;
    if (frame != null && !identical(frame, oldWidget.frame)) {
      _decode(frame);
    } else if (frame == null && oldWidget.frame != null) {
      _decodeGeneration++;
      final previous = _image;
      _image = null;
      previous?.dispose();
    }
  }

  void _decode(CameraVideoFrame frame) {
    if (frame.pixelFormat != 2 && frame.pixelFormat != 3) return;
    final generation = ++_decodeGeneration;
    ui.decodeImageFromPixels(
      frame.bytes,
      frame.width,
      frame.height,
      frame.pixelFormat == 2
          ? ui.PixelFormat.rgba8888
          : ui.PixelFormat.bgra8888,
      (image) {
        if (!mounted || generation != _decodeGeneration) {
          image.dispose();
          return;
        }
        final previous = _image;
        setState(() => _image = image);
        previous?.dispose();
      },
      rowBytes: frame.strideBytes,
    );
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingMessage = _pendingMessage(
      elapsed: widget.cameraElapsed,
      qualityStatus: widget.qualityStatus,
      breathingReady: widget.breathingReady,
      pulseReady: widget.pulseReady,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF030A11),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1A3945)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_image != null)
            RawImage(
              image: _image,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            )
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.error == null
                        ? Icons.videocam_outlined
                        : Icons.videocam_off_outlined,
                    size: 44,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.error != null
                        ? widget.error!
                        : widget.previewUnavailable
                        ? 'The camera session is connected, but SmartSpectra did not return preview frames. Check the SDK video-output callback.'
                        : widget.live
                        ? 'Waiting for camera frames from SmartSpectra…'
                        : 'Starting camera preview…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  if (widget.error != null || widget.previewUnavailable) ...[
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: widget.onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        widget.previewUnavailable
                            ? 'Restart camera'
                            : 'Retry live camera',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.neonCyan,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (_image != null &&
              widget.live &&
              (!widget.breathingReady || !widget.pulseReady))
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE609172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x5538D9C2)),
                ),
                child: Text(
                  pendingMessage,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xCC07131C),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x5538D9C2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _image == null ? Icons.videocam_outlined : Icons.circle,
                    size: 12,
                    color: _image == null
                        ? AppColors.textSecondary
                        : AppColors.neonEmerald,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _image == null ? 'CAMERA' : 'LIVE PREVIEW',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _pendingMessage({
    required Duration elapsed,
    required QualityControlStatus? qualityStatus,
    required bool breathingReady,
    required bool pulseReady,
  }) {
    if (qualityStatus != null && qualityStatus != QualityControlStatus.optimal) {
      return qualityStatus.userGuidance;
    }
    if (elapsed < const Duration(seconds: 12)) {
      return 'Collecting a steady camera signal. Keep your face centered, chest visible, and hold still.';
    }
    if (!breathingReady && !pulseReady) {
      return elapsed < const Duration(seconds: 30)
          ? 'Signal is building. Breathing estimates need a longer stable observation window; the pulse estimate is still settling.'
          : 'The signal has not met SmartSpectra stability criteria yet. Keep steady and follow any quality guidance above; rates appear when stable.';
    }
    if (!breathingReady) {
      return elapsed < const Duration(seconds: 30)
          ? 'Pulse is available. Breathing is still building a stable observation window.'
          : 'Pulse is available. Breathing has not met SmartSpectra stability criteria yet; keep your upper chest visible and hold steady.';
    }
    return elapsed < const Duration(seconds: 30)
        ? 'Breathing is available. Pulse is still settling from the camera signal.'
        : 'Breathing is available. Pulse has not met SmartSpectra stability criteria yet; keep steady and well lit.';
  }
}
