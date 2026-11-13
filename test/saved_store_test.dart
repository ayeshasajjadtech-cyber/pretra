import 'dart:convert';
import 'dart:io';

import 'package:breathe_garden_flutter/src/models.dart';
import 'package:breathe_garden_flutter/src/saved_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SavedSummaryStore SQLite history', () {
    late Directory tempDirectory;
    final stores = <SavedSummaryStore>[];

    SavedSummaryStore newStore() {
      final store = SavedSummaryStore(directory: tempDirectory);
      stores.add(store);
      return store;
    }

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'pretra_store_test_',
      );
      stores.clear();
    });

    tearDown(() async {
      for (final store in stores) {
        await store.close();
      }
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('allocates increasing record numbers transactionally', () async {
      final store = newStore();

      expect(await store.nextRecordNumber(), 'P-000001');
      expect(await store.nextRecordNumber(), 'P-000002');
      expect(await newStore().nextRecordNumber(), 'P-000003');
    });

    test('serializes concurrent record-number requests', () async {
      final store = newStore();
      final numbers = await Future.wait(
        List<Future<String>>.generate(12, (_) => store.nextRecordNumber()),
      );

      expect(numbers.toSet(), hasLength(12));
      expect(numbers.toSet(), contains('P-000001'));
      expect(numbers.toSet(), contains('P-000012'));
    });

    test('imports old JSON and preserves the next record number', () async {
      final legacyFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}saved_summaries.json',
      );
      await legacyFile.writeAsString(
        jsonEncode(<Object?>[
          <String, Object?>{
            'id': 'legacy-session',
            'participantId': 'P-000007',
            'savedAt': DateTime.utc(2026).toIso8601String(),
            'durationMs': 1000,
            'isLiveCamera': true,
            'telemetryPoints': <Object?>[
              <String, Object?>{
                'elapsedSec': 1,
                'timestampIso': DateTime.utc(2026).toIso8601String(),
                'breathingRate': 14.0,
                'pulseRate': 72.0,
                'signalQuality': 90.0,
                'confidence': 90.0,
              },
            ],
          },
        ]),
      );

      final store = newStore();
      final sessions = await store.load();
      expect(sessions, hasLength(1));
      expect(sessions.single.recordNumber, 'P-000007');
      expect(sessions.single.telemetryCount, 1);
      expect(await store.nextRecordNumber(), 'P-000008');
      final loaded = await store.loadWithSamples('legacy-session');
      expect(loaded?.telemetryPoints.single.pulseRate, 72.0);
      expect(await legacyFile.exists(), isTrue); // Keep source backup intact.
    });

    test(
      'persists samples during capture and recovers an interrupted session',
      () async {
        final firstProcess = newStore();
        await firstProcess.beginSession(
          id: 'session-1',
          recordNumber: 'P-000001',
          startedAt: DateTime.utc(2026),
          appVersion: '1.0.0',
        );
        await firstProcess.appendSample(
          'session-1',
          TelemetryPoint(
            elapsedSec: 1,
            timestampIso: DateTime.utc(2026).toIso8601String(),
            breathingRate: 13.0,
            pulseRate: 70.0,
            signalQuality: 88.0,
            confidence: 88.0,
          ),
        );
        await firstProcess.appendSample(
          'session-1',
          TelemetryPoint(
            elapsedSec: 1,
            timestampIso: DateTime.utc(2026, 1, 1, 0, 0, 1).toIso8601String(),
            breathingRate: 13.5,
            pulseRate: 71.0,
            signalQuality: 89.0,
            confidence: 89.0,
          ),
        );

        final restartedProcess = newStore();
        await restartedProcess.initialize();
        final recovered = await restartedProcess.loadWithSamples('session-1');

        expect(recovered?.status, 'interrupted');
        expect(recovered?.telemetryCount, 1);
        expect(recovered?.telemetryPoints.single.breathingRate, 13.5);
      },
    );

    test(
      'finalizes summary with persisted sample confidence and preview state',
      () async {
        final store = newStore();
        final startedAt = DateTime.utc(2026, 1, 1);
        await store.beginSession(
          id: 'session-complete',
          recordNumber: 'P-000001',
          startedAt: startedAt,
          appVersion: '1.0.0',
        );
        await store.appendSample(
          'session-complete',
          TelemetryPoint(
            elapsedSec: 1,
            timestampIso: startedAt.toIso8601String(),
            breathingRate: 12.5,
            pulseRate: 68.0,
            signalQuality: 91.0,
            confidence: 91.0,
          ),
        );
        await store.completeSession(
          SavedSummary(
            id: 'session-complete',
            recordNumber: 'P-000001',
            savedAt: startedAt,
            durationMs: 5000,
            breathingAvg: 12.5,
            pulseAvg: 68.0,
            hrvRmssd: null,
            appVersion: '1.0.0',
            status: 'completed',
            previewReceived: true,
          ),
        );

        final result = await store.loadWithSamples('session-complete');
        expect(result?.status, 'completed');
        expect(result?.previewReceived, isTrue);
        expect(result?.signalQualityAvg, 91.0);
        expect(result?.telemetryCount, 1);
        expect(
          store
              .generateTimeSeriesCsv(result!)
              .contains(
                'Reference_Breathing_Rate_BRM,Reference_Pulse_Rate_BPM',
              ),
          isTrue,
        );
      },
    );

    test(
      'keeps an unreadable legacy file as a backup without blocking use',
      () async {
        final legacyFile = File(
          '${tempDirectory.path}${Platform.pathSeparator}saved_summaries.json',
        );
        await legacyFile.writeAsString('{not valid json');

        final store = newStore();
        expect(await store.load(), isEmpty);
        expect(store.migrationWarning, isNotNull);
        expect(await File('${legacyFile.path}.backup').exists(), isTrue);
        expect(await store.nextRecordNumber(), 'P-000001');
      },
    );
  });
}
