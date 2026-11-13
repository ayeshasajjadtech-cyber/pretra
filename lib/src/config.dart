import 'dart:io';

import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig({
    required this.apiKey,
    required this.simulatedRequested,
    required this.isDev,
  });

  final String apiKey;
  final bool simulatedRequested;
  final bool isDev;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  static const String appVersion = '1.0.0';

  static AppConfig load() {
    final env = _readEnvironment();
    final apiKey = _firstNonEmpty(<String?>[
      const String.fromEnvironment('SMARTSPECTRA_API_KEY'),
      env['SMARTSPECTRA_API_KEY'],
    ]);
    final simulateFlag = _firstNonEmpty(<String?>[
      const String.fromEnvironment('SIMULATE'),
      env['BREATHE_GARDEN_SIMULATE'],
      env['SIMULATE'],
    ]);
    final isDev = kDebugMode;
    final simulatedRequested = isDev && _isTruthy(simulateFlag);

    return AppConfig(
      apiKey: apiKey,
      simulatedRequested: simulatedRequested,
      isDev: isDev,
    );
  }

  static Map<String, String> _readEnvironment() {
    final result = <String, String>{};
    for (final entry in Platform.environment.entries) {
      result[entry.key] = entry.value;
    }

    for (final file in _dotEnvCandidates()) {
      if (!file.existsSync()) continue;
      try {
        _parseDotEnv(file.readAsLinesSync(), result);
      } on FileSystemException {
        continue;
      }
    }
    return result;
  }

  static List<File> _dotEnvCandidates() {
    final seen = <String>{};
    final candidates = <File>[];

    void addDirectory(Directory directory, int depth) {
      var current = directory;
      for (var i = 0; i <= depth; i++) {
        final file = File('${current.path}${Platform.pathSeparator}.env');
        if (seen.add(file.path)) candidates.add(file);
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }

    addDirectory(Directory.current, 3);
    addDirectory(File(Platform.resolvedExecutable).parent, 3);
    return candidates;
  }

  static void _parseDotEnv(List<String> lines, Map<String, String> target) {
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) {
        line = line.substring('export '.length).trim();
      }
      final equals = line.indexOf('=');
      if (equals <= 0) continue;
      final key = line.substring(0, equals).trim();
      var value = line.substring(equals + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty) target[key] = value;
    }
  }

  static String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  static bool _isTruthy(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on';
  }
}
