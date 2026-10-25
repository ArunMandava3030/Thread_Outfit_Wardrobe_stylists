import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// A local file choice only: no network, persistent browser storage or plugins.
/// A new invocation cancels any pending choice from an older browser picker.
void Function()? _cancelPending;

Future<Uint8List?> pickGuestPhoto() {
  _cancelPending?.call();
  final result = Completer<Uint8List?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*'
    ..multiple = false;
  input.style.display = 'none';
  web.document.body!.appendChild(input);
  late JSFunction onChange;
  late JSFunction onCancel;
  void cleanup() {
    input.removeEventListener('change', onChange);
    input.removeEventListener('cancel', onCancel);
    input.remove();
    _cancelPending = null;
  }

  void finish(Uint8List? bytes, [Object? error]) {
    if (result.isCompleted) return;
    cleanup();
    if (error == null) {
      result.complete(bytes);
    } else {
      result.completeError(error);
    }
  }

  onCancel = ((web.Event _) => finish(null)).toJS;
  onChange = ((web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      finish(null);
      return;
    }
    final file = files.item(0)!;
    if (file.size > 25 * 1024 * 1024) {
      finish(null, const FormatException('Choose a photo smaller than 25 MB.'));
      return;
    }
    if (file.size == 0) {
      finish(
        null,
        const FormatException('This photo is empty. Choose another.'),
      );
      return;
    }
    file.arrayBuffer().toDart.then(
      (buffer) {
        finish(Uint8List.fromList(buffer.toDart.asUint8List()));
      },
      onError: (Object _) {
        finish(null, const FormatException('This photo could not be read.'));
      },
    );
  }).toJS;
  input.addEventListener('change', onChange);
  input.addEventListener('cancel', onCancel);
  _cancelPending = () => finish(null);
  // Keep the click in the original user gesture for Safari and mobile browsers.
  try {
    input.click();
  } catch (_) {
    finish(null, const FormatException('Photo selection is unavailable.'));
  }
  return result.future;
}
