import 'dart:typed_data';

import 'package:dart_dbc_generator/src/bitfield/bitfield.dart';
import 'package:dart_dbc_generator/src/dbc/dbc_signal.dart';

abstract class DBCMessage {
  /// The name of this DBC message
  String get messageName;

  /// The CAN ID for this DBC message
  int get canId;

  /// The length of this DBC message
  int get messageLength;

  /// All signals this message will be using to encode and decode CAN bus payloads.
  List<DBCSignal> get signals;

  Uint8List writeToBuffer();

  Uint8List encodeMessage(Map<DBCSignal, num> values) {
    List<int> payloadBitField = BitField.from(Uint8List(messageLength));

    for (final signalValue in values.entries) {
      payloadBitField = signalValue.key.encode(
        payloadBitField,
        signalValue.value,
      );
    }

    List<int> byteValue = BitField.convert64BitListTo8Bit(payloadBitField);

    return Uint8List.fromList(byteValue);
  }
}
