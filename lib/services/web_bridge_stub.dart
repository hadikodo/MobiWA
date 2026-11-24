import 'dart:typed_data';

/// Non-web builds: the extension bridge doesn't exist (Android uses the
/// accessibility service through MethodChannel instead).
class WebBridge {
  WebBridge._();

  static Stream<({String event, Object? data})> get events => const Stream.empty();

  static void init() {}

  static Future<Object?> call(
    String method, [
    Map<String, Object?> args = const {},
    Duration timeout = const Duration(seconds: 30),
  ]) =>
      throw UnsupportedError('WebBridge is only available on the web.');

  static Future<({String name, String mime, int size, Uint8List bytes})?> pickFile(String accept) =>
      throw UnsupportedError('WebBridge is only available on the web.');

  static String browserName() => '';
}
