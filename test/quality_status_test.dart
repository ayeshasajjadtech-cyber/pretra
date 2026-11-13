import 'package:breathe_garden_flutter/src/ffi/smartspectra_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unknown SDK quality codes are never treated as optimal', () {
    expect(QualityControlStatus.fromCode(0), QualityControlStatus.optimal);
    expect(QualityControlStatus.fromCode(999), QualityControlStatus.unknown);
  });
}
