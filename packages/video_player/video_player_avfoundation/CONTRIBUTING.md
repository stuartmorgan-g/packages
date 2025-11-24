# Contributing

## `ffigen`

This package uses [ffigen](https://pub.dev/packages/ffigen) to call many plugin
methods, rather than using method channels. To add new functionality to the
FFI interface, update `tool/ffigen.dart`, then run:

```bash
dart run tool/ffigen.dart
```

### Configuration philosophy

This package intentionally uses very strict filtering rules to include only the
necessary methods and functions, to keep the package small.
