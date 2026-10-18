import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'auto_pose_types.dart';

@JS('threadPoseDetect')
external JSPromise<JSString> _detect(
  JSUint8Array rgba,
  JSNumber width,
  JSNumber height,
  JSString request,
);

@JS('threadPoseCancel')
external void _cancel(JSString request);

class PoseBackend {
  static var _nextId = 0;
  String? _request;
  String? _lastRequest;

  Future<PoseDetection> detect(Uint8List rgba, int width, int height) async {
    final request = 'photo-${_nextId++}';
    _request = request;
    _lastRequest = request;
    try {
      final response = await _detect(
        rgba.toJS,
        width.toJS,
        height.toJS,
        request.toJS,
      ).toDart;
      final json = jsonDecode(response.toDart) as Map<String, dynamic>;
      final raw = json['points'] as List<dynamic>;
      return PoseDetection([
        for (final item in raw)
          PosePoint(
            (item['x'] as num).toDouble(),
            (item['y'] as num).toDouble(),
            (item['score'] as num).toDouble(),
            z: (item['z'] as num?)?.toDouble(),
          ),
      ], people: (json['people'] as num).toInt());
    } finally {
      if (_request == request) _request = null;
    }
  }

  void dispose() {
    final request = _request ?? _lastRequest;
    if (request != null) _cancel(request.toJS);
    _request = null;
    _lastRequest = null;
  }
}
