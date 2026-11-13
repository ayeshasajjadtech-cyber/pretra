import 'dart:io';
import 'dart:math' as math;

class _ErrorMetrics {
  int attempts = 0;
  final List<double> errors = <double>[];

  void add({required double? estimate, required double reference}) {
    attempts++;
    if (estimate != null && estimate.isFinite && reference.isFinite) {
      errors.add(estimate - reference);
    }
  }

  void write(String label) {
    if (attempts == 0) {
      stdout.writeln('$label: no reference values entered.');
      return;
    }
    if (errors.isEmpty) {
      stdout.writeln('$label: 0/$attempts paired estimates (0.0% coverage).');
      return;
    }
    final mae =
        errors.fold<double>(0, (sum, error) => sum + error.abs()) /
        errors.length;
    final bias =
        errors.fold<double>(0, (sum, error) => sum + error) / errors.length;
    final mse =
        errors.fold<double>(0, (sum, error) => sum + error * error) /
        errors.length;
    final coverage = errors.length / attempts * 100;
    stdout.writeln(
      '$label: n=${errors.length}/$attempts; '
      'coverage=${coverage.toStringAsFixed(1)}%; '
      'MAE=${mae.toStringAsFixed(2)}; '
      'RMSE=${math.sqrt(mse).toStringAsFixed(2)}; '
      'bias=${bias.toStringAsFixed(2)}',
    );
  }
}

List<String> _parseCsvRow(String line) {
  final values = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (char == ',' && !quoted) {
      values.add(cell.toString());
      cell.clear();
    } else {
      cell.write(char);
    }
  }
  if (quoted) throw const FormatException('CSV row has an unclosed quote.');
  values.add(cell.toString());
  return values;
}

double? _number(String? value, String label, int row) {
  if (value == null || value.trim().isEmpty) return null;
  final number = double.tryParse(value.trim());
  if (number == null || !number.isFinite) {
    throw FormatException('Invalid $label value on CSV row $row.');
  }
  return number;
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/accuracy_eval.dart <paired-session-csv>',
    );
    exitCode = 64;
    return;
  }

  try {
    final lines = await File(arguments.single).readAsLines();
    final headerIndex = lines.indexWhere(
      (line) => line.trimLeft().startsWith('Elapsed_Sec,'),
    );
    if (headerIndex < 0) {
      throw const FormatException(
        'Could not find the PreTra time-series header.',
      );
    }
    final headers = _parseCsvRow(lines[headerIndex]);
    final indexes = <String, int>{
      for (var i = 0; i < headers.length; i++) headers[i].trim(): i,
    };
    const required = <String>[
      'Breathing_Rate_BRM',
      'Pulse_Rate_BPM',
      'Reference_Breathing_Rate_BRM',
      'Reference_Pulse_Rate_BPM',
    ];
    for (final name in required) {
      if (!indexes.containsKey(name)) {
        throw FormatException('CSV is missing required column: $name');
      }
    }

    final breathing = _ErrorMetrics();
    final pulse = _ErrorMetrics();
    for (
      var lineIndex = headerIndex + 1;
      lineIndex < lines.length;
      lineIndex++
    ) {
      final line = lines[lineIndex];
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final row = _parseCsvRow(line);
      String? field(String name) {
        final index = indexes[name]!;
        return index < row.length ? row[index] : null;
      }

      final referenceBreathing = _number(
        field('Reference_Breathing_Rate_BRM'),
        'reference breathing',
        lineIndex + 1,
      );
      if (referenceBreathing != null) {
        breathing.add(
          estimate: _number(
            field('Breathing_Rate_BRM'),
            'PreTra breathing',
            lineIndex + 1,
          ),
          reference: referenceBreathing,
        );
      }

      final referencePulse = _number(
        field('Reference_Pulse_Rate_BPM'),
        'reference pulse',
        lineIndex + 1,
      );
      if (referencePulse != null) {
        pulse.add(
          estimate: _number(
            field('Pulse_Rate_BPM'),
            'PreTra pulse',
            lineIndex + 1,
          ),
          reference: referencePulse,
        );
      }
    }

    stdout.writeln('Paired reference comparison (estimate minus reference):');
    pulse.write('Pulse BPM');
    breathing.write('Breathing rate/min');
    stdout.writeln(
      'Coverage here means paired rows divided by rows where you entered a reference value; it is not camera-session availability.',
    );
  } on FileSystemException catch (error) {
    stderr.writeln('Could not read CSV: ${error.message}');
    exitCode = 66;
  } on FormatException catch (error) {
    stderr.writeln('Invalid comparison CSV: ${error.message}');
    exitCode = 65;
  }
}
