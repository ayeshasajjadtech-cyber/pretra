import 'dart:typed_data';

import 'models.dart';

class MetricsCodec {
  const MetricsCodec._();

  static DecodedMetrics decode(Uint8List bytes) {
    try {
      return _decodeMetrics(_ProtoReader(bytes));
    } on FormatException {
      return const DecodedMetrics();
    } on RangeError {
      return const DecodedMetrics();
    }
  }

  static DecodedMetrics _decodeMetrics(_ProtoReader reader) {
    final breathingRate = <MeasurementSample>[];
    final upperTrace = <MeasurementSample>[];
    final lowerTrace = <MeasurementSample>[];
    final pulseRate = <MeasurementSample>[];
    final pulseTrace = <MeasurementSample>[];
    final hrv = <HrvSample>[];

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          if (tag.wireType == 2) {
            _decodeBreathing(
              _ProtoReader(reader.readBytes()),
              breathingRate,
              upperTrace,
              lowerTrace,
            );
          } else {
            reader.skip(tag.wireType);
          }
          break;
        case 5:
          if (tag.wireType == 2) {
            _decodeCardio(
              _ProtoReader(reader.readBytes()),
              pulseRate,
              pulseTrace,
              hrv,
            );
          } else {
            reader.skip(tag.wireType);
          }
          break;
        default:
          reader.skip(tag.wireType);
          break;
      }
    }

    return DecodedMetrics(
      breathingRate: breathingRate,
      breathingTrace: upperTrace.isNotEmpty ? upperTrace : lowerTrace,
      pulseRate: pulseRate,
      pulseTrace: pulseTrace,
      hrv: hrv,
    );
  }

  static void _decodeBreathing(
    _ProtoReader reader,
    List<MeasurementSample> rate,
    List<MeasurementSample> upperTrace,
    List<MeasurementSample> lowerTrace,
  ) {
    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          if (tag.wireType == 2) {
            rate.add(_decodeMeasurementWithConfidence(
              _ProtoReader(reader.readBytes()),
            ));
          } else {
            reader.skip(tag.wireType);
          }
          break;
        case 2:
          if (tag.wireType == 2) {
            upperTrace.add(_decodeMeasurement(
              _ProtoReader(reader.readBytes()),
            ));
          } else {
            reader.skip(tag.wireType);
          }
          break;
        case 3:
          if (tag.wireType == 2) {
            lowerTrace.add(_decodeMeasurement(
              _ProtoReader(reader.readBytes()),
            ));
          } else {
            reader.skip(tag.wireType);
          }
          break;
        default:
          reader.skip(tag.wireType);
          break;
      }
    }
  }

  static void _decodeCardio(
    _ProtoReader reader,
    List<MeasurementSample> pulseRate,
    List<MeasurementSample> pulseTrace,
    List<HrvSample> hrv,
  ) {
    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          if (tag.wireType == 2) {
            pulseRate.add(_decodeMeasurementWithConfidence(
              _ProtoReader(reader.readBytes()),
            ));
          } else {
            reader.skip(tag.wireType);
          }
          break;
        case 2:
          if (tag.wireType == 2) {
            pulseTrace.add(_decodeMeasurementWithConfidence(
              _ProtoReader(reader.readBytes()),
            ));
          } else {
            reader.skip(tag.wireType);
          }
          break;
        case 3:
          if (tag.wireType == 2) {
            hrv.add(_decodeHrv(_ProtoReader(reader.readBytes())));
          } else {
            reader.skip(tag.wireType);
          }
          break;
        default:
          reader.skip(tag.wireType);
          break;
      }
    }
  }

  static MeasurementSample _decodeMeasurement(_ProtoReader reader) {
    double? value;
    bool? stable;
    int? timestampUs;

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          if (tag.wireType == 5) {
            value = reader.readFloat();
          } else {
            reader.skip(tag.wireType);
          }
          break;
        case 2:
          if (tag.wireType == 0) {
            stable = reader.readVarint() != 0;
          } else {
            reader.skip(tag.wireType);
          }
          break;
        case 3:
          if (tag.wireType == 0) {
            timestampUs = reader.readVarint();
          } else {
            reader.skip(tag.wireType);
          }
          break;
        default:
          reader.skip(tag.wireType);
          break;
      }
    }

    return MeasurementSample(
      value: value,
      stable: stable,
      timestampUs: timestampUs,
    );
  }

  static MeasurementSample _decodeMeasurementWithConfidence(
    _ProtoReader reader,
  ) {
    double? value;
    bool? stable;
    double? confidence;
    int? timestampUs;

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          if (tag.wireType == 5) {
            value = reader.readFloat();
          } else {
            reader.skip(tag.wireType);
          }
          break;
        case 2:
          if (tag.wireType == 0) {
            stable = reader.readVarint() != 0;
          } else {
            reader.skip(tag.wireType);
          }
          break;
        case 3:
          if (tag.wireType == 5) {
            confidence = reader.readFloat();
          } else {
            reader.skip(tag.wireType);
          }
          break;
        case 4:
          if (tag.wireType == 0) {
            timestampUs = reader.readVarint();
          } else {
            reader.skip(tag.wireType);
          }
          break;
        default:
          reader.skip(tag.wireType);
          break;
      }
    }

    return MeasurementSample(
      value: value,
      confidence: confidence,
      stable: stable,
      timestampUs: timestampUs,
    );
  }

  static HrvSample _decodeHrv(_ProtoReader reader) {
    double? rmssd;
    double? confidence;
    bool? stable;
    int? timestampUs;

    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          if (tag.wireType == 1) {
            rmssd = reader.readDouble();
          } else {
            reader.skip(tag.wireType);
          }
          break;
        case 5:
          if (tag.wireType == 0) {
            timestampUs = reader.readVarint();
          } else {
            reader.skip(tag.wireType);
          }
          break;
        case 6:
          if (tag.wireType == 5) {
            confidence = reader.readFloat();
          } else {
            reader.skip(tag.wireType);
          }
          break;
        case 7:
          if (tag.wireType == 0) {
            stable = reader.readVarint() != 0;
          } else {
            reader.skip(tag.wireType);
          }
          break;
        default:
          reader.skip(tag.wireType);
          break;
      }
    }

    return HrvSample(
      rmssd: rmssd,
      confidence: confidence,
      stable: stable,
      timestampUs: timestampUs,
    );
  }
}

class _Tag {
  const _Tag(this.field, this.wireType);

  final int field;
  final int wireType;
}

class _ProtoReader {
  _ProtoReader(this.bytes) : _end = bytes.length;

  final Uint8List bytes;
  final int _end;
  int _pos = 0;

  bool get isAtEnd => _pos >= _end;

  _Tag readTag() {
    final tag = readVarint();
    final field = tag >>> 3;
    final wireType = tag & 0x7;
    if (field <= 0) {
      throw const FormatException('Invalid protobuf field');
    }
    return _Tag(field, wireType);
  }

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_pos >= _end) {
        throw const FormatException('Truncated protobuf varint');
      }
      final byte = bytes[_pos++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
      if (shift >= 70) {
        throw const FormatException('Protobuf varint too long');
      }
    }
  }

  double readFloat() {
    _require(4);
    final value = ByteData.sublistView(bytes, _pos, _pos + 4)
        .getFloat32(0, Endian.little);
    _pos += 4;
    return value;
  }

  double readDouble() {
    _require(8);
    final value = ByteData.sublistView(bytes, _pos, _pos + 8)
        .getFloat64(0, Endian.little);
    _pos += 8;
    return value;
  }

  Uint8List readBytes() {
    final length = readVarint();
    if (length < 0) {
      throw const FormatException('Negative protobuf length');
    }
    _require(length);
    final value = Uint8List.sublistView(bytes, _pos, _pos + length);
    _pos += length;
    return value;
  }

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
        break;
      case 1:
        _require(8);
        _pos += 8;
        break;
      case 2:
        final length = readVarint();
        if (length < 0) {
          throw const FormatException('Negative protobuf length');
        }
        _require(length);
        _pos += length;
        break;
      case 5:
        _require(4);
        _pos += 4;
        break;
      default:
        throw FormatException('Unsupported protobuf wire type $wireType');
    }
  }

  void _require(int length) {
    if (length < 0 || _pos + length > _end) {
      throw const FormatException('Truncated protobuf message');
    }
  }
}
