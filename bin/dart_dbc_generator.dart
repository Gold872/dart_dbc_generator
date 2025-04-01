import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:change_case/change_case.dart';
import 'package:dart_dbc_generator/src/dbc/dbc_database.dart';

const String dbcLibPrefix = r'$_dbc';
const String mathLibPrefix = r'$_math';
const String typedLibPrefix = r'$_typed';

const String fileHeader = '''
// AUTO GENERATED FILE, DO NOT MODIFY

// ignore_for_file: type=lint
// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:math' as $mathLibPrefix;
import 'dart:typed_data' as $typedLibPrefix;

import 'package:dart_dbc_generator/dart_dbc_generator.dart' as $dbcLibPrefix;''';

ArgParser buildParser() {
  return ArgParser()
    ..addOption(
      'input-file',
      abbr: 'i',
      valueHelp: 'The input file to generate code for.',
      mandatory: true,
    )
    ..addOption(
      'output-path',
      abbr: 'o',
      valueHelp: 'The output directory of the generated file.',
      mandatory: true,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    );
}

void printUsage(ArgParser parser) {
  print(
    'Usage: dart_dbc_generator -i <input file> -o <output directory> [arguments]',
  );
  print(parser.usage);
}

void main(List<String> arguments) async {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);

    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }

    final String filePath = results.option('input-file')!;
    final String outputPath = results.option('output-path')!;
    final File inputFile = File(filePath);
    final Directory outputDirectory = Directory(outputPath);

    if (!await inputFile.exists()) {
      print('File not found: $filePath');
      return;
    }

    try {
      final dbc = await DBCDatabase.loadFromBytes(inputFile.readAsBytesSync());
      final generatedCode = generateDartClasses(dbc);

      final outputFileName =
          '${inputFile.absolute.path.replaceAll('\\', '/').split('/').last.split('.').first.toSnakeCase()}_messages.dbc.dart';
      final outputFile = File(
        '${outputDirectory.path}/$outputFileName'
            .replaceAll('\\', '/')
            .replaceAll('//', '/'),
      );

      await outputFile.writeAsString(generatedCode);
      print('Generated classes written to ${outputFile.path}');
    } catch (e) {
      print('Error processing DBC file: $e');
    }
  } catch (e) {
    print(e);
    print('');
    printUsage(argParser);
  }
}

String generateDartClasses(DBCDatabase dbc) {
  final buffer = StringBuffer();

  buffer.writeln(fileHeader);

  for (final dbEntry in dbc.database.entries) {
    final messageName = dbc.messageNames[dbEntry.key]!;
    final className = '${messageName.toPascalCase()}Message';
    buffer.writeln();
    buffer.writeln('class $className extends $dbcLibPrefix.DBCMessage {');

    final isMultiplex = dbc.isMultiplex[dbEntry.key]!;
    final messageLength = dbc.messageLengths[dbEntry.key]!;
    final multiplexor = dbc.multiplexors[dbEntry.key] ?? "";

    // dart format off
    // Getters
    buffer.writeln('  @override');
    buffer.writeln('  String messageName = "$messageName";');
    buffer.writeln();
    buffer.writeln('  @override');
    buffer.writeln('  int messageLength = $messageLength;');
    buffer.writeln();
    buffer.writeln('  @override');
    buffer.writeln('  int canId = 0x${dbEntry.key.toRadixString(16)};');
    buffer.writeln();
    buffer.writeln('  /// Whether or not "$messageName" is multiplex');
    buffer.writeln('  static const bool isMultiplex = $isMultiplex;');
    buffer.writeln();
    buffer.writeln('  /// The multiplexor for "$messageName"');
    buffer.writeln('  static const String multiplexor = "$multiplexor";');
    buffer.writeln();

    // Signal value fields
    for (final signalEntry in dbEntry.value) {
      final fieldName = signalEntry.name.toCamelCase();
      buffer.writeln('  /// Value of signal "${signalEntry.name}"');
      buffer.writeln('  num $fieldName;');
      buffer.writeln();
    }

    // All signals
    for (final signal in dbEntry.value) {
      final fieldName = signal.name.toCamelCase();

      buffer.writeln('  final $dbcLibPrefix.DBCSignal _${fieldName}Signal = $dbcLibPrefix.DBCSignal(');
      buffer.writeln('    name: "${signal.name}",');
      buffer.writeln('    signalSignedness: $dbcLibPrefix.${signal.signalSignedness.toString()},');
      buffer.writeln('    signalType: $dbcLibPrefix.${signal.signalType.toString()},');
      buffer.writeln('    signalMode: $dbcLibPrefix.${signal.signalMode.toString()},');
      buffer.writeln('    multiplexGroup: ${signal.multiplexGroup},');
      buffer.writeln('    start: ${signal.start},');
      buffer.writeln('    length: ${signal.length},');
      buffer.writeln('    mapping: ${signal.mapping.toList().toString()},');
      buffer.writeln('    mappingIndexes: ${signal.mappingIndexes.toList().toString()},');
      buffer.writeln('    factor: ${signal.factor},');
      buffer.writeln('    offset: ${signal.offset},');
      buffer.writeln('    min: ${signal.min},');
      buffer.writeln('    max: ${signal.max},');
      buffer.writeln('    unit: "${signal.unit}",');
      buffer.writeln('  );');
      buffer.writeln();
    }

    // Signals list getter
    buffer.writeln('  @override');
    buffer.writeln('  List<$dbcLibPrefix.DBCSignal> get signals => [');
    for (final signal in dbEntry.value) {
      buffer.writeln('    _${signal.name.toCamelCase()}Signal,');
    }
    buffer.writeln('  ];');
    buffer.writeln();

    // Constructor
    buffer.write('  $className(');
    if (dbEntry.value.isNotEmpty) {
      buffer.writeln('{');
      for (final signal in dbEntry.value) {
        final fieldName = signal.name.toCamelCase();
        buffer.writeln('    this.$fieldName = ${numToStringWithMinimumDecimals(max(signal.offset, signal.min))},');
      }
      buffer.writeln('  });');
    } else {
      buffer.writeln(');');
    }
    buffer.writeln();

    // Copy with
    buffer.writeln('  /// Creates a clone of this [$className] with the non-null values replaced');
    buffer.write('  $className copyWith(');
    if (dbEntry.value.isNotEmpty) {
      buffer.writeln('{');
      for (final signal in dbEntry.value) {
        buffer.writeln('    num? ${signal.name.toCamelCase()},');
      }
      buffer.writeln('  }) {');
      buffer.writeln('    return $className(');
      for (final signal in dbEntry.value) {
        final signalName = signal.name.toCamelCase();
        buffer.writeln('      $signalName: $signalName ?? this.$signalName,');
      }
      buffer.writeln('    );');
      buffer.writeln('  }');
    } else {
      buffer.writeln(') => $className();');
    }
    buffer.writeln();

    // From buffer constructor
    buffer.writeln('  factory $className.fromBuffer(List<int> buffer) {');
    buffer.writeln('    final message = $className();');
    buffer.writeln('    final typedBuffer = $typedLibPrefix.Uint8List.fromList(buffer);');
    buffer.writeln('    final bitField = $dbcLibPrefix.BitField.from(typedBuffer.sublist(0, message.messageLength));');
    for (final signalEntry in dbEntry.value) {
      final fieldName = signalEntry.name.toCamelCase();
      final signalFieldName = '_${fieldName}Signal';
      buffer.writeln('    message.$fieldName =\n        message.$signalFieldName.decode(bitField) ??\n        $mathLibPrefix.max(0, message.$signalFieldName.min);');
    }
    buffer.writeln();
    buffer.writeln('    return message;');
    buffer.writeln('  }');
    buffer.writeln();

    // Write to buffer
    buffer.writeln('  @override');
    buffer.writeln('  $typedLibPrefix.Uint8List writeToBuffer() {');
    buffer.writeln('    final Map<$dbcLibPrefix.DBCSignal, num> values = {');
    for (final signalEntry in dbEntry.value) {
      final signalName = signalEntry.name.toCamelCase();
      buffer.writeln('      _${signalName}Signal: $signalName,');
    }
    buffer.writeln('    };');
    buffer.writeln();
    buffer.writeln('    return encodeMessage(values);');
    buffer.writeln('  }');
    buffer.writeln();

    // To string override
    buffer.writeln('  @override');
    buffer.writeln('  String toString() {');
    buffer.write('    return "$messageName(');
    for (final signal in dbEntry.value) {
      final signalName = signal.name.toCamelCase();
      buffer.write('\\n  ${signal.name}=\$$signalName');
    }
    buffer.writeln('\\n)";');
    buffer.writeln('  }');
    buffer.writeln('}');
  }
  // dart format on

  return buffer.toString();
}

String numToStringWithMinimumDecimals(num value) {
  String stringValue = value.toString();
  if (stringValue.contains('.')) {
    // Remove trailing zeros
    stringValue = stringValue.replaceAll(RegExp(r'0*$'), '');
    stringValue = stringValue.replaceAll('.', '');
  }
  return stringValue;
}
