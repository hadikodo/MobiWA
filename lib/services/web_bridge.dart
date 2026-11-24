import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Talks to the MobiWA Connector Chrome extension (web build only).
///
/// The extension's content script on app.mobiwa.com relays window messages:
///   app → ext: {source: 'mobiwa-app', id, method, args}
///   ext → app: {source: 'mobiwa-ext', type: 'response', id, ok, result | error}
///              {source: 'mobiwa-ext', type: 'event', event, data}
class WebBridge {
  WebBridge._();

  static final _pending = <String, Completer<Object?>>{};
  static final _events = StreamController<({String event, Object? data})>.broadcast();
  static bool _ready = false;
  static int _seq = 0;

  static Stream<({String event, Object? data})> get events => _events.stream;

  static void init() {
    if (_ready) return;
    _ready = true;
    web.window.addEventListener(
      'message',
      ((web.MessageEvent e) {
        if (e.source != web.window) return;
        final data = e.data.dartify();
        if (data is! Map || data['source'] != 'mobiwa-ext') return;
        if (data['type'] == 'response') {
          final c = _pending.remove('${data['id']}');
          if (c == null) return;
          if (data['ok'] == true) {
            c.complete(data['result']);
          } else {
            c.completeError(Exception('${data['error'] ?? 'Extension error'}'));
          }
        } else if (data['type'] == 'event') {
          _events.add((event: '${data['event']}', data: data['data']));
        }
      }).toJS,
    );
  }

  /// Calls [method] in the extension. Throws [TimeoutException] when the
  /// extension is not installed (no answer).
  static Future<Object?> call(
    String method, [
    Map<String, Object?> args = const {},
    Duration timeout = const Duration(seconds: 30),
  ]) {
    init();
    final id = 'm${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
    final c = Completer<Object?>();
    _pending[id] = c;
    web.window.postMessage(
      {'source': 'mobiwa-app', 'id': id, 'method': method, 'args': args}.jsify(),
      web.window.location.origin.toJS,
    );
    return c.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('MobiWA Connector did not answer ($method).');
    });
  }

  /// Opens the browser's file picker. Returns name, mime, size and the bytes.
  static Future<({String name, String mime, int size, Uint8List bytes})?> pickFile(String accept) {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = accept;
    final done = Completer<({String name, String mime, int size, Uint8List bytes})?>();
    Future<void> read() async {
      final file = input.files?.item(0);
      if (file == null) {
        if (!done.isCompleted) done.complete(null);
        return;
      }
      final buffer = await file.arrayBuffer().toDart;
      if (done.isCompleted) return;
      done.complete((
        name: file.name,
        mime: file.type.isEmpty ? 'application/octet-stream' : file.type,
        size: file.size,
        bytes: buffer.toDart.asUint8List(),
      ));
    }

    // JS callbacks must be synchronous; they start the async read.
    input.addEventListener('change', ((web.Event _) {
      unawaited(read());
    }).toJS);
    input.addEventListener('cancel', ((web.Event _) {
      if (!done.isCompleted) done.complete(null);
    }).toJS);
    input.click();
    return done.future;
  }

  /// Short description of this browser, e.g. "Chrome on Windows".
  static String browserName() {
    final ua = web.window.navigator.userAgent;
    final browser = ua.contains('Edg/')
        ? 'Edge'
        : ua.contains('OPR/')
            ? 'Opera'
            : ua.contains('Chrome/')
                ? 'Chrome'
                : ua.contains('Firefox/')
                    ? 'Firefox'
                    : ua.contains('Safari/')
                        ? 'Safari'
                        : 'Browser';
    final os = ua.contains('Windows')
        ? 'Windows'
        : ua.contains('Mac OS')
            ? 'macOS'
            : ua.contains('Android')
                ? 'Android'
                : ua.contains('Linux')
                    ? 'Linux'
                    : ua.contains('CrOS')
                        ? 'ChromeOS'
                        : '';
    return os.isEmpty ? browser : '$browser on $os';
  }
}
