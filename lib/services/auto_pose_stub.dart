import 'dart:typed_data';

import 'auto_pose_types.dart';

class PoseBackend {
  Future<PoseDetection> detect(Uint8List rgba, int width, int height) async {
    throw const AutoPhotoException(
      'Automatic analysis is unavailable here. Tap the photo to continue.',
    );
  }

  void dispose() {}
}
