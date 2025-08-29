import 'dart:io';

import 'package:dart_dbc_generator/src/dbc/dbc_signal.dart';

const int byteLen = 8; // in bits

/// An object that stores multiple [DBCSignal]-s along with information needed to decode them
class DBCDatabase {
  /// Map of [DBCSignal]-s used for decoding. Signals are grouped by their decimal CAN id's.
  final Map<int, List<DBCSignal>> database;

  /// A map of Can IDs to their respective message names.
  final Map<int, String> messageNames;

  /// Length of each CAN message, the key is the decimal CAN id
  final Map<int, int> messageLengths;

  /// Defines whether a message designated by its CAN id has multiplex groups
  final Map<int, bool> isMultiplex;

  /// Shortcut for finding the [DBCSignalMode.MULTIPLEXOR] of a message
  final Map<int, String> multiplexors;

  /// Map of signal and its value table
  final Map<String, dynamic> valueTable;

  DBCDatabase({
    required this.database,
    required this.messageNames,
    required this.messageLengths,
    required this.isMultiplex,
    required this.multiplexors,
    required this.valueTable,
  });

  /// The initial loading function.
  ///
  /// This function may throw, when any of the given files dont exist.
  /// If the given file is not in line with DBC format then it will return a [DBCDatabase] with empty [DBCDatabase.database] field, an will therefore not decode anything
  static Future<DBCDatabase> loadFromFile(File file) async {
    Map<int, String> messageNames = {};
    Map<int, List<DBCSignal>> database = {};
    Map<int, int> messageLengths = {};
    Map<int, bool> isMultiplex = {};
    Map<int, String> multiplexors = {};
    Map<String, Map<int, String>> valueTable = {};

    String fileString = await file.readAsString();

    List<String> lines = fileString.split('\n');

    RegExp messageRegex = RegExp(
      r"BO_\s[0-9]{1,4}\s[a-zA-z0-9]+:\s\d\s[a-zA-z]+",
    );
    RegExp signalRegex = RegExp(
      r"\sSG_\s[a-zA-Z0-9_ ]+\s:\s[0-9\S]+\s[\S0-9]+\s[\S0-9]+\s[a-zA-Z\S]+\s{1,2}[a-zA-z]+",
    );

    RegExp messageNameRegex = RegExp(r"BO_\s[0-9]{1,4}\s([a-zA-z0-9]+):\s");
    RegExp messageIdRegex = RegExp(r"BO_\s[0-9]{1,4}");
    RegExp messageLengthRegex = RegExp(r":\s\d\s");

    RegExp signalNameRegex = RegExp(r"SG_\s[a-zA-Z0-9_]+");

    RegExp extendedMultiplexValue = RegExp(
      r"SG_MUL_VAL_\s(\d+)\s([a-zA-Z0-9_]+)\s([a-zA-Z0-9_]+)\s(.+);",
    );

    RegExp valueTableRegex = RegExp(
      r'VAL_\s+(\d+)\s+(\w+)\s+((?:\d+\s+"[^"]+"\s*)+)',
    );

    bool messageContinuation = false;
    int canId = 0;

    for (String line in lines) {
      if (!messageContinuation && messageRegex.hasMatch(line)) {
        messageContinuation = true;

        RegExpMatch messageIdMatch = messageNameRegex.firstMatch(line)!;
        RegExpMatch canIdMatch = messageIdRegex.firstMatch(line)!;
        RegExpMatch canLengthMatch = messageLengthRegex.firstMatch(line)!;
        canId = int.parse(canIdMatch[0]!.substring(4));
        int length = int.parse(canLengthMatch[0]!.substring(2, 3));

        messageNames[canId] = messageIdMatch.group(1)!;
        messageLengths[canId] = length;
        database[canId] = [];
      } else if (messageContinuation && signalRegex.hasMatch(line)) {
        String signalName = signalNameRegex.firstMatch(line)![0]!.substring(4);
        if (signalName.endsWith(' ')) {
          signalName = signalName.substring(0, signalName.length - 1);
        }
        database[canId]!.add(
          DBCSignal.fromString(signalName, line, messageLengths[canId]! * 8),
        );
      } else if (messageContinuation && !signalRegex.hasMatch(line)) {
        messageContinuation = false;
        canId = 0;
      }

      if (extendedMultiplexValue.hasMatch(line)) {
        RegExpMatch match = extendedMultiplexValue.firstMatch(line)!;

        int canID = int.parse(match.group(1)!);
        String signalName = match.group(2)!;
        String multiplexerSignalName = match.group(3)!;
        String rangesString = match.group(4)!;

        if (database.containsKey(canID) &&
            database[canID]!.any((e) => e.name == signalName)) {
          int index = database[canID]!.indexWhere((e) => e.name == signalName);
          final DBCSignal signal = database[canID]![index];

          List<int> multiplexerIDs = [];

          for (String range in rangesString.split(', ')) {
            List<String> pair = range.split('-');
            int lower = int.parse(pair[0]);
            int upper = int.parse(pair[1]);

            for (int i = lower; i <= upper; i++) {
              multiplexerIDs.add(i);
            }
          }

          database[canID]![index] = signal.copyWith(
            signalMode: DBCSignalMode.MULTIPLEX_GROUP,
            multiplexerName: multiplexerSignalName,
            multiplexerIds: multiplexerIDs,
          );
        }
      }

      /// To read the individual signal value maps and assign to SignalValue map
      if (valueTableRegex.hasMatch(line)) {
        RegExpMatch? match = valueTableRegex.firstMatch(line);
        // String messageId = match!.group(1)!;
        String signalName = match!.group(2)!;
        String valueMappings = match.group(3)!;

        RegExp pairPattern = RegExp(r'(\d+)\s+"([^"]+)"');
        Iterable<RegExpMatch> pairs = pairPattern.allMatches(valueMappings);

        Map<int, String> valueDescriptionMap = {
          for (var pair in pairs) int.parse(pair.group(1)!): pair.group(2)!,
        };

        valueTable[signalName] = valueDescriptionMap;
      }
    }

    // Post process
    for (int canId in database.keys) {
      if (database[canId]!.any(
        (element) => element.signalMode == DBCSignalMode.MULTIPLEXOR,
      )) {
        final multiplexorSignal = database[canId]!.firstWhere(
          (element) => element.signalMode == DBCSignalMode.MULTIPLEXOR,
        );
        for (int i = 0; i < database[canId]!.length; i++) {
          final signal = database[canId]![i];

          if (signal.signalMode == DBCSignalMode.MULTIPLEX_GROUP &&
              signal.multiplexerName == '') {
            database[canId]![i] = signal.copyWith(
              multiplexerName: multiplexorSignal.name,
            );
          }
        }
        isMultiplex[canId] = true;
        multiplexors[canId] = multiplexorSignal.name;
      } else {
        isMultiplex[canId] = false;
      }
    }

    return DBCDatabase(
      database: database,
      messageNames: messageNames,
      messageLengths: messageLengths,
      isMultiplex: isMultiplex,
      multiplexors: multiplexors,
      valueTable: valueTable,
    );
  }

  /// A decode function that runs on a [Uint8List], eg. from a socket
  ///
  /// Returns a map of successfully decoded signals, if a [DBCSignal] was determined to be out of range specified by [DBCSignal.min] and [DBCSignal.max], that value is omitted from the returned map
  // Map<String, num> decode(Uint8List bytes) {
  //   int mainOffset = 0;
  //   Map<String, num> decoded = {};

  //   while (mainOffset < bytes.length - canIdLength) {
  //     while (!database.containsKey(
  //       bytes
  //           .sublist(mainOffset, mainOffset + canIdLength)
  //           .buffer
  //           .asByteData()
  //           .getUint16(0),
  //     )) {
  //       mainOffset++;
  //       if (mainOffset >= bytes.length - canIdLength) {
  //         return decoded;
  //       }
  //     }
  //     int canId = bytes
  //         .sublist(mainOffset, mainOffset + canIdLength)
  //         .buffer
  //         .asByteData()
  //         .getUint16(0);
  //     mainOffset += canIdLength;

  //     Map<String, DBCSignal> messageData = database[canId]!;
  //     int messageLength = messageLengths[canId]!;
  //     if (bytes.length - mainOffset < messageLength) {
  //       return decoded;
  //     }

  //     List<int> payloadBitField = BitField.from(
  //       bytes.sublist(mainOffset, mainOffset + messageLength),
  //     );

  //     mainOffset += messageLength;
  //     if (isMultiplex[canId]!) {
  //       int? activeMultiplexGroup =
  //           messageData[multiplexors[canId]]!.decode(payloadBitField)?.toInt();
  //       if (activeMultiplexGroup == null) {
  //         continue;
  //       }
  //       messageData.forEach((signalName, signalData) {
  //         if (signalData.signalMode == DBCSignalMode.SIGNAL ||
  //             signalData.signalMode == DBCSignalMode.MULTIPLEX_GROUP &&
  //                 signalData.multiplexGroup == activeMultiplexGroup) {
  //           final num? signalValue = signalData.decode(payloadBitField);
  //           if (signalValue != null) {
  //             decoded[signalName] = signalValue;
  //           }
  //         }
  //       });
  //     } else {
  //       for (String signalName in messageData.keys) {
  //         final num? signalValue = messageData[signalName]!.decode(
  //           payloadBitField,
  //         );
  //         if (signalValue != null) {
  //           decoded[signalName] = signalValue;
  //         }
  //       }
  //     }
  //   }
  //   return decoded;
  // }

  // Uint8List encodeMessage(int canId) {
  //   // Ensure the CAN ID exists in the database
  //   if (!database.containsKey(canId)) {
  //     throw ArgumentError("CAN ID $canId not found in database.");
  //   }

  //   // Retrieve the signals for the given CAN ID
  //   Map<String, DBCSignal> signals = database[canId]!;

  //   // Create an 8-byte CAN frame (standard size)
  //   List<int> message = List.filled(10, 0);

  //   // Encode CAN ID (2 bytes for 11-bit CAN IDs)
  //   message[0] = (canId >> 8) & 0xFF; // High byte of CAN ID
  //   message[1] = canId & 0xFF; // Low byte of CAN ID

  //   // For each signal, encode its value into the message's payload
  //   List<int> payloadBitField = BitField.from(
  //     Uint8List(messageLengths[canId]!),
  //   );

  //   for (var signalEntry in signals.entries) {
  //     DBCSignal signal = signalEntry.value;
  //     payloadBitField = signal.encode(payloadBitField);
  //   }
  //   List<int> byteValue = BitField.convert64BitListTo8Bit(payloadBitField);

  //   for (int i = 0; i < 8; i++) {
  //     message[2 + i] = byteValue[i];
  //   }
  //   return Uint8List.fromList(message);
  // }
}
