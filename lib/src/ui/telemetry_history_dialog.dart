import 'dart:async';
import 'package:flutter/material.dart';

import '../models.dart';
import '../saved_store.dart';

class TelemetryHistoryDialog extends StatefulWidget {
  const TelemetryHistoryDialog({super.key, required this.store});

  final SavedSummaryStore store;

  static Future<void> show(BuildContext context, SavedSummaryStore store) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => TelemetryHistoryDialog(store: store),
    );
  }

  @override
  State<TelemetryHistoryDialog> createState() => _TelemetryHistoryDialogState();
}

class _TelemetryHistoryDialogState extends State<TelemetryHistoryDialog> {
  List<SavedSummary> _summaries = <SavedSummary>[];
  bool _loading = false;
  bool _initialLoading = true;
  String _recordFilter = '';
  String? _exportMessage;
  Timer? _exportMessageTimer;

  static const Color background = Color(0xFF050B14);
  static const Color surfaceGlass = Color(0xCC09172A);
  static const Color neonCyan = Color(0xFF00E5FF);
  static const Color neonEmerald = Color(0xFF00E676);
  static const Color neonAmber = Color(0xFFFFD54F);
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final summaries = await widget.store.load();
      if (mounted) {
        setState(() {
          _summaries = summaries;
          _initialLoading = false;
          _exportMessage = widget.store.migrationWarning;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _initialLoading = false;
          _exportMessage = 'Unable to load saved sessions: $error';
        });
      }
    }
  }

  void _showExportResult(String message) {
    _exportMessageTimer?.cancel();
    setState(() => _exportMessage = message);
    _exportMessageTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _exportMessage = null);
    });
  }

  @override
  void dispose() {
    _exportMessageTimer?.cancel();
    super.dispose();
  }

  Future<void> _exportAllCsv() async {
    if (_summaries.isEmpty) return;
    setState(() => _loading = true);
    try {
      final csv = widget.store.generateSessionsCsv(_summaries);
      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final file = await widget.store.saveCsv(
        fileName: 'pretra_sessions_export_$timestamp.csv',
        csvData: csv,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      _showExportResult(
        file == null
            ? 'Could not export session history.'
            : 'Exported ${_summaries.length} sessions. Use Open Export Folder to view the CSV.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showExportResult('Could not export session history: $error');
    }
  }

  Future<void> _exportSingleSessionCsv(SavedSummary session) async {
    setState(() => _loading = true);
    try {
      final fullSession = await widget.store.loadWithSamples(session.id);
      final file = fullSession == null
          ? null
          : await widget.store.saveCsv(
              fileName: 'pretra_telemetry_${session.id}.csv',
              csvData: widget.store.generateTimeSeriesCsv(fullSession),
            );
      if (!mounted) return;
      setState(() => _loading = false);
      _showExportResult(
        file == null
            ? 'Could not export this session.'
            : 'Session time series exported. Use Open Export Folder to view the CSV.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showExportResult('Could not export this session: $error');
    }
  }

  void _confirmDelete(SavedSummary session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: const Text(
          'Delete Session Record?',
          style: TextStyle(color: textPrimary, fontSize: 16),
        ),
        content: const Text(
          'This will permanently remove this monitored session from local history.',
          style: TextStyle(color: textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.store.deleteSummary(session.id);
                await _loadData();
              } catch (error) {
                if (mounted) {
                  _showExportResult('Could not delete session: $error');
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: const Text(
          'Clear All Session Records?',
          style: TextStyle(color: textPrimary, fontSize: 16),
        ),
        content: const Text(
          'This will erase all historical telemetry logs from PreTra.',
          style: TextStyle(color: textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.store.clear();
                await _loadData();
              } catch (error) {
                if (mounted) {
                  _showExportResult('Could not clear session history: $error');
                }
              }
            },
            child: const Text(
              'Clear All',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleSummaries = _summaries
        .where((session) {
          return session.recordNumber.toLowerCase().contains(
            _recordFilter.trim().toLowerCase(),
          );
        })
        .toList(growable: false);
    // Calculate aggregate metrics
    double? avgBreath;
    double? avgPulse;
    double? avgQuality;
    if (visibleSummaries.isNotEmpty) {
      final breathVals = visibleSummaries
          .map((s) => s.breathingAvg)
          .whereType<double>()
          .toList();
      final pulseVals = visibleSummaries
          .map((s) => s.pulseAvg)
          .whereType<double>()
          .toList();
      final qualVals = visibleSummaries
          .map((s) => s.signalQualityAvg)
          .whereType<double>()
          .toList();

      if (breathVals.isNotEmpty) {
        avgBreath = breathVals.reduce((a, b) => a + b) / breathVals.length;
      }
      if (pulseVals.isNotEmpty) {
        avgPulse = pulseVals.reduce((a, b) => a + b) / pulseVals.length;
      }
      if (qualVals.isNotEmpty) {
        avgQuality = qualVals.reduce((a, b) => a + b) / qualVals.length;
      }
    }
    return Dialog(
      backgroundColor: background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: neonCyan.withValues(alpha: 0.35), width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: neonCyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: neonCyan,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PreTra Telemetry & Session Log',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          'Locally persisted biometric telemetry records and historical analytics',
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Aggregate Stats Summary Cards
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: surfaceGlass,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCol(
                      'Recorded Sessions',
                      '${_summaries.length}',
                      neonCyan,
                    ),
                    _buildDivider(),
                    _buildStatCol(
                      'Avg Respiration',
                      avgBreath != null
                          ? '${avgBreath.toStringAsFixed(1)} BRM'
                          : '—',
                      neonCyan,
                    ),
                    _buildDivider(),
                    _buildStatCol(
                      'Avg Pulse',
                      avgPulse != null
                          ? '${avgPulse.toStringAsFixed(0)} BPM'
                          : '—',
                      neonEmerald,
                    ),
                    _buildDivider(),
                    _buildStatCol(
                      'Avg SDK Confidence',
                      avgQuality != null
                          ? '${avgQuality.toStringAsFixed(0)}%'
                          : '—',
                      neonAmber,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, color: neonCyan),
                  hintText: 'Filter by record number',
                  filled: true,
                  fillColor: surfaceGlass,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1E293B)),
                  ),
                ),
                onChanged: (value) => setState(() => _recordFilter = value),
              ),
              const SizedBox(height: 12),

              // Session List Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SESSION HISTORY (${visibleSummaries.length} / ${_summaries.length})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: textSecondary,
                    ),
                  ),
                  if (_summaries.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: const Color(0xFFEF4444),
                      ),
                      icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                      label: const Text(
                        'Clear All',
                        style: TextStyle(fontSize: 12),
                      ),
                      onPressed: _confirmClearAll,
                    ),
                ],
              ),
              const SizedBox(height: 8),

              if (_exportMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: surfaceGlass,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Text(
                    _exportMessage!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: textSecondary, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Sessions Scrollable List
              Expanded(
                child: _initialLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: neonCyan),
                      )
                    : _summaries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.monitor_heart_outlined,
                              color: textSecondary.withValues(alpha: 0.4),
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No monitored sessions recorded yet.',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Launch a PreTra session to track live breathing and pulse data.',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : visibleSummaries.isEmpty
                    ? const Center(
                        child: Text(
                          'No sessions match that record number.',
                          style: TextStyle(color: textSecondary, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        itemCount: visibleSummaries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final session = visibleSummaries[index];
                          return _buildSessionCard(session);
                        },
                      ),
              ),
              const SizedBox(height: 16),

              // Bottom Action Bar
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textPrimary,
                      side: const BorderSide(color: Color(0xFF334155)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(
                      Icons.folder_open_rounded,
                      size: 18,
                      color: neonCyan,
                    ),
                    label: const Text(
                      'Open Export Folder',
                      style: TextStyle(fontSize: 13),
                    ),
                    onPressed: () => widget.store.openExportFolder(),
                  ),
                  const Spacer(),
                  if (_summaries.isNotEmpty) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: neonCyan,
                        foregroundColor: const Color(0xFF03101C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF03101C),
                              ),
                            )
                          : const Icon(Icons.download_rounded, size: 18),
                      label: const Text(
                        'Export All to CSV',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      onPressed: _loading ? null : _exportAllCsv,
                    ),
                    const SizedBox(width: 10),
                  ],
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: textSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionCard(SavedSummary session) {
    final durationSec = (session.durationMs / 1000).round();
    final mins = durationSec ~/ 60;
    final secs = durationSec % 60;
    final formattedDuration = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
    final statusColor = session.status == 'completed' ? neonEmerald : neonAmber;
    final sourceLabel = session.status == 'sdk_error'
        ? 'SDK error'
        : session.status == 'camera_unavailable'
        ? 'Camera unavailable'
        : session.isLiveCamera && !session.previewReceived
        ? 'SDK (preview missing)'
        : session.isLiveCamera
        ? 'SmartSpectra Live'
        : 'Simulated';
    final dateStr =
        '${session.savedAt.year}-${session.savedAt.month.toString().padLeft(2, '0')}-${session.savedAt.day.toString().padLeft(2, '0')} ${session.savedAt.hour.toString().padLeft(2, '0')}:${session.savedAt.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceGlass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          // Mode Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (session.isLiveCamera ? neonEmerald : neonCyan).withValues(
                alpha: 0.12,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              session.isLiveCamera
                  ? Icons.videocam_rounded
                  : Icons.sensors_rounded,
              color: session.isLiveCamera ? neonEmerald : neonCyan,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'RECORD ${session.recordNumber.isEmpty ? 'UNASSIGNED' : session.recordNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: neonCyan,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        formattedDuration,
                        style: const TextStyle(
                          fontSize: 10,
                          color: textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (session.isLiveCamera ? neonEmerald : neonCyan)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        sourceLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: session.isLiveCamera ? neonEmerald : neonCyan,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildInlineMetric(
                      'Breath',
                      session.breathingAvg != null
                          ? '${session.breathingAvg!.toStringAsFixed(1)} BRM'
                          : '—',
                      neonCyan,
                    ),
                    const SizedBox(width: 14),
                    _buildInlineMetric(
                      'Pulse',
                      session.pulseAvg != null
                          ? '${session.pulseAvg!.toStringAsFixed(0)} BPM'
                          : '—',
                      neonEmerald,
                    ),
                    const SizedBox(width: 14),
                    _buildInlineMetric(
                      'Confidence',
                      session.signalQualityAvg != null
                          ? '${session.signalQualityAvg!.toStringAsFixed(0)}%'
                          : '—',
                      neonAmber,
                    ),
                    const SizedBox(width: 14),
                    _buildInlineMetric(
                      'Status',
                      session.status.replaceAll('_', ' '),
                      statusColor,
                    ),
                    if (session.telemetryCount > 0) ...[
                      const SizedBox(width: 14),
                      Text(
                        '${session.telemetryCount} samples',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Actions
          IconButton(
            tooltip: 'Export Session Time-Series CSV',
            icon: const Icon(
              Icons.file_download_outlined,
              color: neonCyan,
              size: 20,
            ),
            onPressed: () => _exportSingleSessionCsv(session),
          ),
          IconButton(
            tooltip: 'Delete Session Record',
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFF94A3B8),
              size: 20,
            ),
            onPressed: () => _confirmDelete(session),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineMetric(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 11, color: textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCol(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: textSecondary)),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 24, color: const Color(0xFF1E293B));
  }
}
