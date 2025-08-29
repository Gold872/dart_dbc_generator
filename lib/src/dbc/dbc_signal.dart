import 'package:dart_dbc_generator/src/bitfield/bitfield.dart';

/// An enum to signal signedness
enum DBCSignalSignedness {
  // ignore: constant_identifier_names
  SIGNED,
  // ignore: constant_identifier_names
  UNSIGNED,
}

/// An enum to signal type, eq INTEL and MOTOROLA
enum DBCSignalType {
  // ignore: constant_identifier_names
  INTEL,
  // ignore: constant_identifier_names
  MOTOROLA,
}

/// An enum to signal mode, such as standalone SIGNAL or MULTIPLEX GROUP and MULTIPLEXOR
enum DBCSignalMode {
  // ignore: constant_identifier_names
  SIGNAL,
  // ignore: constant_identifier_names
  MULTIPLEXOR,
  // ignore: constant_identifier_names
  MULTIPLEX_GROUP,
}

/// An object that stores necessary data to decode a CAN signal
class DBCSignal {
  DBCSignal({
    required this.name,
    required this.signalSignedness,
    required this.signalType,
    required this.signalMode,
    this.multiplexerName = '',
    this.multiplexerIds = const [],
    required this.start,
    required this.length,
    required this.mapping,
    required this.mappingIndexes,
    required this.factor,
    required this.offset,
    required this.min,
    required this.max,
    required this.unit,
  });

  DBCSignal copyWith({
    DBCSignalMode? signalMode,
    String? multiplexerName,
    List<int>? multiplexerIds,
  }) => DBCSignal(
    name: name,
    signalSignedness: signalSignedness,
    signalType: signalType,
    signalMode: signalMode ?? this.signalMode,
    multiplexerIds: multiplexerIds ?? this.multiplexerIds,
    multiplexerName: multiplexerName ?? this.multiplexerName,
    start: start,
    length: length,
    mapping: mapping,
    mappingIndexes: mappingIndexes,
    factor: factor,
    offset: offset,
    min: min,
    max: max,
    unit: unit,
  );

  final String name;
  final DBCSignalSignedness signalSignedness;
  final DBCSignalType signalType;
  final DBCSignalMode signalMode;
  final String multiplexerName;
  final List<int> multiplexerIds;
  final int start;
  final int length;

  /// Specifies how the payload bits count towards a decoded value
  final List<int> mapping;

  /// Specifies the used bits in the payload
  final List<int> mappingIndexes;
  final double factor;
  final double offset;
  final double min;
  final double max;
  final String unit;

  static RegExp signalNameRegex = RegExp(r"SG_ (\w+) ");
  static RegExp signednessRegex = RegExp(r"@\d[+-]{1}");
  static RegExp multiplexorRegex = RegExp(r" M ");
  static RegExp multiplexGroupRegex = RegExp(r" m\d ");
  static RegExp startbitRegex = RegExp(r": [0-9]+\|");
  static RegExp lengthRegex = RegExp(r"\|[0-9]+@");
  static RegExp factorRegex = RegExp(r"\([0-9.Ee-]+,");
  static RegExp offsetRegex = RegExp(r",([0-9.\-Ee]+)\)");
  static RegExp minRegex = RegExp(r"\[([0-9.\-\+Ee]+)\|");
  static RegExp maxRegex = RegExp(r"\|([0-9.\-\+Ee]+)\]");
  static RegExp unitRegex = RegExp(r'\] "([a-zA-Z\/0-9%!^°-\s]*)" ');

  /// When a DBC file is initially parsed each signals are constructed on a line-by-line basis
  static DBCSignal fromString(String name, String data, int lengthOfMessage) {
    DBCSignalSignedness signalSignedness;
    DBCSignalType signalType;
    DBCSignalMode signalMode;
    int multiplexGroup;
    int length;
    int start;
    List<int> mapping;
    List<int> mappingIndexes;
    double factor;
    double offset;
    double min;
    double max;
    String unit;

    signalSignedness =
        signednessRegex.firstMatch(data)![0]!.contains('-')
            ? DBCSignalSignedness.SIGNED
            : DBCSignalSignedness.UNSIGNED;
    signalType =
        signednessRegex.firstMatch(data)![0]!.contains('0')
            ? DBCSignalType.MOTOROLA
            : DBCSignalType.INTEL;

    if (multiplexorRegex.hasMatch(data)) {
      signalMode = DBCSignalMode.MULTIPLEXOR;
      multiplexGroup = -1;
    } else if (multiplexGroupRegex.hasMatch(data)) {
      signalMode = DBCSignalMode.MULTIPLEX_GROUP;

      final multiplexerData = multiplexGroupRegex
          .firstMatch(data)![0]!
          .trim()
          .split('m');
      multiplexGroup = int.parse(multiplexerData[1]);
    } else {
      multiplexGroup = -1;
      signalMode = DBCSignalMode.SIGNAL;
    }

    String startMatch = startbitRegex.firstMatch(data)![0]!.substring(2);
    start = int.parse(startMatch.substring(0, startMatch.length - 1));
    String lengthMatch = lengthRegex.firstMatch(data)![0]!.substring(1);
    length = int.parse(lengthMatch.substring(0, lengthMatch.length - 1));

    mapping = BitField.getMapping(length, start, lengthOfMessage, signalType);
    mappingIndexes =
        mapping
            .asMap()
            .keys
            .toList()
            .where((element) => mapping[element] != 0)
            .toList();

    String factorMatch = factorRegex.firstMatch(data)![0]!.substring(1);
    factor = double.parse(factorMatch.substring(0, factorMatch.length - 1));
    String offsetMatch = offsetRegex.firstMatch(data)!.group(1)!;
    offset = double.parse(offsetMatch);

    String minMatch = minRegex.firstMatch(data)!.group(1)!;
    min = double.parse(minMatch);
    String maxMatch = maxRegex.firstMatch(data)!.group(1)!;
    max = double.parse(maxMatch);
    String unitMatch = unitRegex.firstMatch(data)!.group(1)!;
    unit = unitMatch;

    return DBCSignal(
      name: name,
      signalSignedness: signalSignedness,
      signalType: signalType,
      signalMode: signalMode,
      multiplexerName: '',
      multiplexerIds: multiplexGroup != -1 ? [multiplexGroup] : [],
      start: start,
      length: length,
      mapping: mapping,
      mappingIndexes: mappingIndexes,
      factor: factor,
      offset: offset,
      min: min,
      max: max,
      unit: unit,
    );
  }

  /// The bit level representation of the payload is multiplied with the signals mapping to form a decoded value
  /// This value changes sign dependent on [DBCSignalSignedness], and then is multiplied by the factor, and offseted my the offset
  /// If a value turns out to be out of range specified by [min] and [max] null is returned
  num? decode(List<int> payload) {
    int val = 0;
    for (int i in mappingIndexes) {
      val += payload[i] * mapping[i];
    }
    if (signalSignedness == DBCSignalSignedness.SIGNED) {
      val = val.toSigned(length);
    }
    final double scaled = val * factor + offset;
    if (min <= scaled && scaled <= max) {
      return scaled;
    }
    return null;
  }

  List<int> encode(List<int> payload, num value) {
    // Apply the scaling and offset
    int rawValue = ((value - offset) / factor).round();
    // Handle signedness if the signal is signed
    if (signalSignedness == DBCSignalSignedness.SIGNED) {
      // Convert to signed value (two's complement)
      rawValue =
          rawValue &
          ((1 << length) - 1); // Mask to fit within the signal's length
    }

    for (int i = 0; i < mappingIndexes.length; i++) {
      int bitPos = mappingIndexes[i]; // Get the bit position
      int bitValue =
          (rawValue & mapping[bitPos]) != 0
              ? 1
              : 0; // Extract the bit based on the mask
      payload[bitPos] = bitValue;
    }

    return payload;
  }
}
