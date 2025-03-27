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

## Known Limitations

* Does not support message decoding
* Does not currently support encoding or decoding CAN FD
* Generated classes will not compile if the message name starts with a number
