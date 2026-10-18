import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'auto_pose_types.dart';

class PoseBackend {
  Future<PoseDetection> detect(Uint8List rgba, int width, int height) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw const AutoPhotoException(
        'Automatic analysis is available in the browser, Android and iPhone. '
        'Tap the photo to sample here.',
      );
    }
    final model = await rootBundle.load(
      'assets/models/movenet_lightning.tflite',
    );
    // Loading and inference happen in a worker isolate. No photo is uploaded.
    return compute(_detectNative, (
      model: model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes),
      rgba: rgba,
      width: width,
      height: height,
    ));
  }

  void dispose() {}
}

PoseDetection _detectNative(
  ({Uint8List model, Uint8List rgba, int width, int height}) request,
) {
  final options = InterpreterOptions()..threads = 2;
  Interpreter? interpreter;
  try {
    interpreter = Interpreter.fromBuffer(request.model, options: options);
    final input = PoseInput.fromRgba(
      request.rgba,
      request.width,
      request.height,
    );
    final tensor = interpreter.getInputTensor(0);
    if (tensor.type != TensorType.uint8 ||
        !listEquals(tensor.shape, [1, 192, 192, 3])) {
      throw const FormatException('Unexpected MoveNet input');
    }
    tensor.data = input.rgb;
    interpreter.invoke();
    final output = interpreter.getOutputTensor(0);
    if (output.type != TensorType.float32 ||
        !listEquals(output.shape, [1, 1, 17, 3])) {
      throw const FormatException('Unexpected MoveNet output');
    }
    final bytes = ByteData.sublistView(output.data);
    final points = <PosePoint>[];
    for (var index = 0; index < 17; index++) {
      final offset = index * 12;
      points.add(
        input.restore(
          bytes.getFloat32(offset + 4, Endian.host),
          bytes.getFloat32(offset, Endian.host),
          bytes.getFloat32(offset + 8, Endian.host),
        ),
      );
    }
    return PoseDetection(points);
  } finally {
    interpreter?.close();
    options.delete();
  }
}
