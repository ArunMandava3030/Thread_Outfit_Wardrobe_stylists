import 'dart:math' as math;
import 'dart:typed_data';

/// Coordinates in the original, decoded image, normalized to [0, 1].
/// Keypoint indexes follow MoveNet/COCO's 17-point order on both platforms.
class PosePoint {
  const PosePoint(this.x, this.y, this.score, {this.z});

  final double x;
  final double y;
  final double score;
  final double? z;

  bool get visible =>
      x.isFinite &&
      y.isFinite &&
      score.isFinite &&
      (z == null || z!.isFinite) &&
      x >= 0 &&
      x <= 1 &&
      y >= 0 &&
      y <= 1 &&
      score >= 0.55;
}

class PoseDetection {
  const PoseDetection(this.points, {this.people = 1});

  final List<PosePoint> points;
  final int people;
}

class AutoPhotoException implements Exception {
  const AutoPhotoException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Letterboxing transform used by the native 192px MoveNet model. Pixel-center
/// bilinear sampling preserves aspect ratio; padding is opaque black RGB.
class PoseInput {
  const PoseInput({
    required this.rgb,
    required this.size,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.scaledWidth,
    required this.scaledHeight,
    required this.left,
    required this.top,
  });

  final Uint8List rgb;
  final int size;
  final int sourceWidth;
  final int sourceHeight;
  final int scaledWidth;
  final int scaledHeight;
  final int left;
  final int top;

  PosePoint restore(double x, double y, double score) => PosePoint(
    (x * size - left) / scaledWidth,
    (y * size - top) / scaledHeight,
    score,
  );

  static PoseInput fromRgba(
    Uint8List rgba,
    int width,
    int height, {
    int size = 192,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        size <= 0 ||
        rgba.length != width * height * 4) {
      throw const FormatException('Invalid photo pixels');
    }
    final scale = size / math.max(width, height);
    final scaledWidth = math.max(1, (width * scale).round());
    final scaledHeight = math.max(1, (height * scale).round());
    final left = (size - scaledWidth) ~/ 2;
    final top = (size - scaledHeight) ~/ 2;
    final rgb = Uint8List(size * size * 3);
    for (var row = 0; row < scaledHeight; row++) {
      final sy = ((row + 0.5) * height / scaledHeight - 0.5).clamp(
        0.0,
        height - 1.0,
      );
      final y0 = sy.floor();
      final y1 = math.min(height - 1, y0 + 1);
      final fy = sy - y0;
      for (var col = 0; col < scaledWidth; col++) {
        final sx = ((col + 0.5) * width / scaledWidth - 0.5).clamp(
          0.0,
          width - 1.0,
        );
        final x0 = sx.floor();
        final x1 = math.min(width - 1, x0 + 1);
        final fx = sx - x0;
        final destination = ((row + top) * size + col + left) * 3;
        for (var channel = 0; channel < 3; channel++) {
          double pixel(int x, int y) {
            final index = (y * width + x) * 4;
            return rgba[index + channel] * rgba[index + 3] / 255;
          }

          final upper = pixel(x0, y0) * (1 - fx) + pixel(x1, y0) * fx;
          final lower = pixel(x0, y1) * (1 - fx) + pixel(x1, y1) * fx;
          rgb[destination + channel] = (upper * (1 - fy) + lower * fy).round();
        }
      }
    }
    return PoseInput(
      rgb: rgb,
      size: size,
      sourceWidth: width,
      sourceHeight: height,
      scaledWidth: scaledWidth,
      scaledHeight: scaledHeight,
      left: left,
      top: top,
    );
  }
}
