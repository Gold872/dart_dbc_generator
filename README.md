# Dart DBC Generator

A package to generate classes from a CAN DBC file for parsing CAN messages.

## How to Use

1. Add the package as a dependency in your project

```
dart pub add dart_dbc_generator
```

2. Generate classes from your dbc file

```
dart run dart_dbc_generator -i example.dbc -o lib/src/generated/
```

## Generated Class Usage

Below is an example of encoding and decoding a frame named "Example" with the fields "Signal_1" and "Signal_2":

```dart
// Create an "ExampleMessage"
ExampleMessage example = ExampleMessage(
    signal1: 0.5,
    signal2: -0.25,
);

// Encode the message into a CAN packet
Uint8List buffer = example.encode();

// ...

// Decode an "Example" from a CAN packet
ExampleMessage example = ExampleMessage.decode(...);
print(example);

// All fields in the generated classes are mutable
example.signal1 = 2;
```

## Known Limitations

* Does not support multiplex message decoding
* Does not currently support encoding or decoding CAN FD
* Generated classes will not compile if the message name starts with a number
