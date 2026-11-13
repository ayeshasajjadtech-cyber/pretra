import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models.dart';

class SavedSummaryStore {
  SavedSummaryStore({Directory? directory})
    : _directory = directory ?? _defaultDirectory();

  final Directory _directory;
  Database? _database;
  Future<void>? _initializing;
  String? _migrationWarning;

  Directory get directory => _directory;
  String? get migrationWarning => _migrationWarning;
  File get _legacyFile =>
      File('${_directory.path}${Platform.pathSeparator}saved_summaries.json');
  File get _legacySequenceFile =>
      File('${_directory.path}${Platform.pathSeparator}record_sequence.txt');
  File get _databaseFile =>
      File('${_directory.path}${Platform.pathSeparator}pretra_sessions.sqlite');

  Directory get exportDirectory {
    final profile = Platform.environment['USERPROFILE'];
    if (profile != null && profile.isNotEmpty) {
      return Directory(
        '$profile${Platform.pathSeparator}Documents${Platform.pathSeparator}PreTra${Platform.pathSeparator}exports',
      );
    }
    return Directory('${_directory.path}${Platform.pathSeparator}exports');
  }

  Future<void> initialize() {
    if (_database != null) return Future<void>.value();
    return _initializing ??= _initialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _initialize() async {
    if (_database != null) return;
    await _directory.create(recursive: true);
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      _databaseFile.path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.rawQuery('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA synchronous = NORMAL');
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE sessions (
              id TEXT PRIMARY KEY,
              record_number TEXT NOT NULL,
              saved_at TEXT NOT NULL,
              duration_ms INTEGER NOT NULL DEFAULT 0,
              breathing_avg REAL,
              pulse_avg REAL,
              hrv_rmssd REAL,
              app_version TEXT NOT NULL,
              confidence_avg REAL,
              is_live_camera INTEGER NOT NULL,
              preview_received INTEGER NOT NULL DEFAULT 0,
              status TEXT NOT NULL,
              sample_count INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE telemetry_points (
              session_id TEXT NOT NULL,
              elapsed_sec INTEGER NOT NULL,
              timestamp_iso TEXT NOT NULL,
              breathing_rate REAL,
              pulse_rate REAL,
              confidence REAL NOT NULL,
              PRIMARY KEY (session_id, elapsed_sec),
              FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE app_metadata (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX telemetry_session_idx ON telemetry_points(session_id, elapsed_sec)',
          );
          await db.execute(
            'CREATE INDEX sessions_record_idx ON sessions(record_number)',
          );
        },
      ),
    );
    _database = database;
    await _importLegacyJsonOnce(database);
    // A session left as "recording" after process termination is retained for
    // recovery and marked interrupted instead of being silently discarded.
    await database.update(
      'sessions',
      <String, Object?>{'status': 'interrupted'},
      where: 'status = ?',
      whereArgs: <Object?>['recording'],
    );
  }

  Future<Database> get _db async {
    await initialize();
    return _database!;
  }

  /// Assigns an increasing local record number. It numbers scans and does not
  /// identify a person or link that person across sessions.
  Future<String> nextRecordNumber() async {
    final db = await _db;
    return db.transaction((txn) async {
      final metadata = await txn.query(
        'app_metadata',
        columns: <String>['value'],
        where: 'key = ?',
        whereArgs: <Object?>['record_sequence'],
        limit: 1,
      );
      var highest = metadata.isEmpty
          ? 0
          : int.tryParse(metadata.first['value'] as String) ?? 0;
      if (metadata.isEmpty) {
        final result = await txn.rawQuery(
          "SELECT MAX(CAST(SUBSTR(record_number, 3) AS INTEGER)) AS highest "
          "FROM sessions WHERE record_number LIKE 'P-%'",
        );
        highest = (result.first['highest'] as num?)?.toInt() ?? 0;
        if (await _legacySequenceFile.exists()) {
          final old =
              int.tryParse(await _legacySequenceFile.readAsString()) ?? 0;
          if (old > highest) highest = old;
        }
      }
      final next = highest + 1;
      await txn.insert('app_metadata', <String, Object?>{
        'key': 'record_sequence',
        'value': '$next',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return 'P-${next.toString().padLeft(6, '0')}';
    });
  }

  Future<void> beginSession({
    required String id,
    required String recordNumber,
    required DateTime startedAt,
    required String appVersion,
  }) async {
    final db = await _db;
    await db.insert('sessions', <String, Object?>{
      'id': id,
      'record_number': recordNumber,
      'saved_at': startedAt.toUtc().toIso8601String(),
      'duration_ms': 0,
      'app_version': appVersion,
      'is_live_camera': 1,
      'preview_received': 0,
      'status': 'recording',
      'sample_count': 0,
    });
  }

  /// Commits one stable sample at a time. Primary-key upsert makes a repeated
  /// elapsed second idempotent and keeps the database bounded to one point/sec.
  Future<void> appendSample(String sessionId, TelemetryPoint point) async {
    final db = await _db;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'telemetry_points',
        columns: <String>['elapsed_sec'],
        where: 'session_id = ? AND elapsed_sec = ?',
        whereArgs: <Object?>[sessionId, point.elapsedSec],
        limit: 1,
      );
      await txn.insert('telemetry_points', <String, Object?>{
        'session_id': sessionId,
        'elapsed_sec': point.elapsedSec,
        'timestamp_iso': point.timestampIso,
        'breathing_rate': point.breathingRate,
        'pulse_rate': point.pulseRate,
        'confidence': point.confidence,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (existing.isEmpty) {
        await txn.rawUpdate(
          'UPDATE sessions SET sample_count = sample_count + 1 WHERE id = ?',
          <Object?>[sessionId],
        );
      }
    });
  }

  Future<void> completeSession(SavedSummary summary) async {
    final db = await _db;
    await db.transaction((txn) async {
      final confidenceRows = await txn.rawQuery(
        'SELECT AVG(confidence) AS average FROM telemetry_points WHERE session_id = ?',
        <Object?>[summary.id],
      );
      final confidenceAverage = (confidenceRows.first['average'] as num?)
          ?.toDouble();
      final updated = await txn.update(
        'sessions',
        <String, Object?>{
          'duration_ms': summary.durationMs,
          'breathing_avg': summary.breathingAvg,
          'pulse_avg': summary.pulseAvg,
          'hrv_rmssd': summary.hrvRmssd,
          'confidence_avg': confidenceAverage,
          'preview_received': summary.previewReceived ? 1 : 0,
          'status': summary.status,
        },
        where: 'id = ?',
        whereArgs: <Object?>[summary.id],
      );
      if (updated != 1) {
        throw StateError(
          'Session ${summary.id} is missing from local storage.',
        );
      }
    });
  }

  Future<List<SavedSummary>> load() async {
    final db = await _db;
    final rows = await db.query('sessions', orderBy: 'saved_at DESC');
    return rows.map(_summaryFromRow).toList(growable: false);
  }

  Future<SavedSummary?> loadWithSamples(String id) async {
    final db = await _db;
    final rows = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final pointRows = await db.query(
      'telemetry_points',
      where: 'session_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'elapsed_sec ASC',
    );
    final base = _summaryFromRow(rows.first);
    return SavedSummary(
      id: base.id,
      recordNumber: base.recordNumber,
      savedAt: base.savedAt,
      durationMs: base.durationMs,
      breathingAvg: base.breathingAvg,
      pulseAvg: base.pulseAvg,
      hrvRmssd: base.hrvRmssd,
      appVersion: base.appVersion,
      signalQualityAvg: base.signalQualityAvg,
      isLiveCamera: base.isLiveCamera,
      previewReceived: base.previewReceived,
      status: base.status,
      sampleCount: base.sampleCount,
      telemetryPoints: pointRows.map(_pointFromRow).toList(growable: false),
    );
  }

  Future<void> addSummary(SavedSummary summary) async {
    final db = await _db;
    await db.transaction((txn) async {
      await _insertSummary(txn, summary);
    });
  }

  Future<void> deleteSummary(String id) async {
    final db = await _db;
    await db.delete('sessions', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> clear() async {
    final db = await _db;
    await db.delete('sessions');
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    if (database != null) await database.close();
  }

  SavedSummary _summaryFromRow(Map<String, Object?> row) => SavedSummary(
    id: row['id']! as String,
    recordNumber: row['record_number']! as String,
    savedAt: DateTime.parse(row['saved_at']! as String),
    durationMs: row['duration_ms']! as int,
    breathingAvg: (row['breathing_avg'] as num?)?.toDouble(),
    pulseAvg: (row['pulse_avg'] as num?)?.toDouble(),
    hrvRmssd: (row['hrv_rmssd'] as num?)?.toDouble(),
    appVersion: row['app_version']! as String,
    signalQualityAvg: (row['confidence_avg'] as num?)?.toDouble(),
    isLiveCamera: row['is_live_camera'] == 1,
    previewReceived: row['preview_received'] == 1,
    status: row['status']! as String,
    sampleCount: row['sample_count']! as int,
  );

  TelemetryPoint _pointFromRow(Map<String, Object?> row) => TelemetryPoint(
    elapsedSec: row['elapsed_sec']! as int,
    timestampIso: row['timestamp_iso']! as String,
    breathingRate: (row['breathing_rate'] as num?)?.toDouble(),
    pulseRate: (row['pulse_rate'] as num?)?.toDouble(),
    signalQuality: (row['confidence']! as num).toDouble(),
    confidence: (row['confidence']! as num).toDouble(),
  );

  Future<void> _insertSummary(Transaction txn, SavedSummary summary) async {
    await txn.insert('sessions', <String, Object?>{
      'id': summary.id,
      'record_number': summary.recordNumber,
      'saved_at': summary.savedAt.toUtc().toIso8601String(),
      'duration_ms': summary.durationMs,
      'breathing_avg': summary.breathingAvg,
      'pulse_avg': summary.pulseAvg,
      'hrv_rmssd': summary.hrvRmssd,
      'app_version': summary.appVersion,
      'confidence_avg': summary.signalQualityAvg,
      'is_live_camera': summary.isLiveCamera ? 1 : 0,
      'preview_received': summary.previewReceived ? 1 : 0,
      'status': summary.status,
      'sample_count': summary.telemetryCount,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    for (final point in summary.telemetryPoints) {
      await txn.insert('telemetry_points', <String, Object?>{
        'session_id': summary.id,
        'elapsed_sec': point.elapsedSec,
        'timestamp_iso': point.timestampIso,
        'breathing_rate': point.breathingRate,
        'pulse_rate': point.pulseRate,
        'confidence': point.confidence,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _importLegacyJsonOnce(Database db) async {
    final alreadyImported = await db.query(
      'app_metadata',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>['legacy_json_import_v1'],
      limit: 1,
    );
    if (alreadyImported.isNotEmpty) {
      if (alreadyImported.first['value'] == 'backup_kept') {
        _migrationWarning =
            'The old session file could not be read; its backup remains in the PreTra data folder.';
      }
      return;
    }
    List<SavedSummary> legacy = <SavedSummary>[];
    if (await _legacyFile.exists()) {
      try {
        final decoded = jsonDecode(await _legacyFile.readAsString());
        if (decoded is List<Object?>) {
          legacy = decoded
              .map(SavedSummary.fromJson)
              .whereType<SavedSummary>()
              .toList(growable: false);
        }
      } catch (e) {
        debugPrint('[SavedSummaryStore] Legacy JSON import failed: $e');
        _migrationWarning =
            'The old session file could not be read; its original file was kept as a backup.';
        try {
          final backup = File('${_legacyFile.path}.backup');
          if (!await backup.exists()) await _legacyFile.copy(backup.path);
        } catch (backupError) {
          debugPrint('[SavedSummaryStore] Legacy backup failed: $backupError');
          return;
        }
      }
    }
    await db.transaction((txn) async {
      for (final summary in legacy) {
        await _insertSummary(txn, summary);
      }
      await txn.insert('app_metadata', <String, Object?>{
        'key': 'legacy_json_import_v1',
        'value': _migrationWarning == null ? 'complete' : 'backup_kept',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Exports all session summaries into CSV.
  String generateSessionsCsv(List<SavedSummary> summaries) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Record_Number,Session_ID,Date_Time_UTC,Duration_Sec,Breathing_Avg_BRM,Pulse_Avg_BPM,SDK_Confidence_Avg_Pct,HRV_RMSSD,Mode,Status,Preview_Received,Data_Points_Count',
    );
    for (final s in summaries) {
      final sec = (s.durationMs / 1000).round();
      final breath = s.breathingAvg?.toStringAsFixed(1) ?? 'N/A';
      final pulse = s.pulseAvg?.toStringAsFixed(1) ?? 'N/A';
      final confidence = s.signalQualityAvg?.toStringAsFixed(1) ?? 'N/A';
      final hrv = s.hrvRmssd?.toStringAsFixed(1) ?? 'N/A';
      final mode = s.isLiveCamera ? 'Live_SmartSpectra' : 'Simulated';
      buffer.writeln(
        '${_csv(s.recordNumber)},${_csv(s.id)},${s.savedAt.toUtc().toIso8601String()},$sec,$breath,$pulse,$confidence,$hrv,$mode,${_csv(s.status)},${s.previewReceived},${s.telemetryCount}',
      );
    }
    return buffer.toString();
  }

  String generateTimeSeriesCsv(SavedSummary session) {
    final buffer = StringBuffer();
    buffer.writeln('# PreTra Telemetry Time-Series Export');
    buffer.writeln('# Record number: ${session.recordNumber}');
    buffer.writeln('# Session ID: ${session.id}');
    buffer.writeln('# Date UTC: ${session.savedAt.toUtc().toIso8601String()}');
    buffer.writeln('# Session status: ${session.status}');
    buffer.writeln(
      'Elapsed_Sec,Timestamp_UTC,Breathing_Rate_BRM,Pulse_Rate_BPM,SDK_Confidence_Pct,Reference_Breathing_Rate_BRM,Reference_Pulse_Rate_BPM',
    );
    for (final point in session.telemetryPoints) {
      final breathing = point.breathingRate?.toStringAsFixed(2) ?? '';
      final pulse = point.pulseRate?.toStringAsFixed(2) ?? '';
      buffer.writeln(
        '${point.elapsedSec},${_csv(point.timestampIso)},$breathing,$pulse,${point.confidence.toStringAsFixed(1)},,',
      );
    }
    return buffer.toString();
  }

  String _csv(String value) => '"${value.replaceAll('"', '""')}"';

  Future<File?> saveCsv({
    required String fileName,
    required String csvData,
  }) async {
    try {
      await exportDirectory.create(recursive: true);
      final file = File(
        '${exportDirectory.path}${Platform.pathSeparator}$fileName',
      );
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(csvData)];
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      debugPrint('[SavedSummaryStore] Failed to write CSV file: $e');
      return null;
    }
  }

  Future<void> openExportFolder() async {
    try {
      await exportDirectory.create(recursive: true);
      if (Platform.isWindows) {
        await Process.run('explorer.exe', <String>[exportDirectory.path]);
      }
    } catch (e) {
      debugPrint('[SavedSummaryStore] Failed to open export folder: $e');
    }
  }

  static Directory _defaultDirectory() {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return Directory('$appData${Platform.pathSeparator}PreTra');
    }
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory('$home${Platform.pathSeparator}.pretra');
    }
    return Directory(
      '${Directory.current.path}${Platform.pathSeparator}.pretra',
    );
  }
}
