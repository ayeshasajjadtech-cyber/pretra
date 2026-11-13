import 'models.dart';

typedef MetricsCallback = void Function(
  DecodedMetrics metrics,
  int receivedAtMs,
);

typedef StatusCallback = void Function(int status);

typedef ValidationCallback = void Function(
  int code,
  String hint,
  int timestampUs,
);

typedef SourceErrorCallback = void Function(
  int code,
  String message,
  bool retryable,
);
