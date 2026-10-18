import 'dart:math' as math;
import 'dart:typed_data';

import '../models/style_models.dart';
import 'auto_pose_stub.dart'
    if (dart.library.io) 'auto_pose_native.dart'
    if (dart.library.js_interop) 'auto_pose_web.dart';
import 'auto_pose_types.dart';
import 'photo_analyzer.dart';

export 'auto_pose_types.dart';

class AutoPhotoEstimate {
  const AutoPhotoEstimate({
    this.shirtColor,
    this.skinToneArgb,
    this.bodyShape,
    this.shoulderHipRatio,
    this.samplePoint,
    required this.landmarks,
  });

  final ShirtColor? shirtColor;
  final int? skinToneArgb;
  final BodyShape? bodyShape;
  final double? shoulderHipRatio;
  final ({double x, double y})? samplePoint;
  final List<PosePoint> landmarks;
}

/// Real pose inference is supplied by local MediaPipe (web) or MoveNet (mobile).
/// The model locates joints; the following image sampling and rough proportion
/// rules are ordinary post-processing, not learned clothing/body classifiers.
class AutoPhotoAnalyzer {
  final _backend = PoseBackend();

  Future<AutoPhotoEstimate> analyze({
    required Uint8List rgba,
    required int width,
    required int height,
    bool sampleSkin = false,
  }) async {
    final pose = await _backend.detect(rgba, width, height);
    return estimateFromPose(
      rgba: rgba,
      width: width,
      height: height,
      pose: pose,
      sampleSkin: sampleSkin,
    );
  }

  void dispose() => _backend.dispose();

  /// Exposed separately so confidence gates and coordinate math are testable
  /// without a platform runtime or a photo containing an identifiable person.
  static AutoPhotoEstimate estimateFromPose({
    required Uint8List rgba,
    required int width,
    required int height,
    required PoseDetection pose,
    bool sampleSkin = false,
  }) {
    if (width <= 0 || height <= 0 || rgba.length != width * height * 4) {
      throw const FormatException('Invalid photo pixels');
    }
    if (pose.people != 1 || pose.points.length != 17) {
      throw const AutoPhotoException(
        'Use a photo with one person, or tap to choose the area yourself.',
      );
    }
    if (sampleSkin) return _skinEstimate(rgba, width, height, pose);

    final leftShoulder = pose.points[5];
    final rightShoulder = pose.points[6];
    final leftHip = pose.points[11];
    final rightHip = pose.points[12];
    final torso = [leftShoulder, rightShoulder, leftHip, rightHip];
    if (torso.any((point) => !point.visible)) {
      throw const AutoPhotoException(
        'Shoulders and hips need to be clearly visible. Try a fuller photo '
        'or use the guided taps.',
      );
    }
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs() * width;
    final hipWidth = (leftHip.x - rightHip.x).abs() * width;
    final shoulderY = (leftShoulder.y + rightShoulder.y) / 2 * height;
    final hipY = (leftHip.y + rightHip.y) / 2 * height;
    final torsoHeight = hipY - shoulderY;
    final depthDifference = leftShoulder.z != null && rightShoulder.z != null
        ? (leftShoulder.z! - rightShoulder.z!).abs() * width
        : 0.0;
    if (shoulderWidth < width * 0.08 ||
        hipWidth < width * 0.05 ||
        torsoHeight < height * 0.10 ||
        torsoHeight / shoulderWidth < 0.55 ||
        torsoHeight / shoulderWidth > 3.5 ||
        (leftShoulder.y - rightShoulder.y).abs() * height >
            shoulderWidth * 0.30 ||
        (leftHip.y - rightHip.y).abs() * height > hipWidth * 0.35 ||
        depthDifference > shoulderWidth * 0.75 ||
        (leftShoulder.x - rightShoulder.x) * (leftHip.x - rightHip.x) <= 0) {
      throw const AutoPhotoException(
        'Try a straight-on photo with your arms relaxed, or use guided taps.',
      );
    }
    final sample = _torsoColor(
      rgba,
      width,
      height,
      leftShoulder,
      rightShoulder,
      leftHip,
      rightHip,
    );
    final ratio = shoulderWidth / hipWidth;
    // Joint spacing differs from outer clothing width. These deliberately broad
    // bands are a rough styling cue, not anthropometry or a medical assessment.
    // There is no waist landmark: fuller-midsection is never inferred here.
    final shape = ratio > 1.6
        ? BodyShape.broadShoulders
        : ratio < 1.15
        ? BodyShape.widerHips
        : BodyShape.balanced;
    final centerX =
        (leftShoulder.x + rightShoulder.x) * 0.3 +
        (leftHip.x + rightHip.x) * 0.2;
    final centerY =
        (leftShoulder.y + rightShoulder.y) * 0.3 +
        (leftHip.y + rightHip.y) * 0.2;
    return AutoPhotoEstimate(
      shirtColor: sample == null ? null : PhotoAnalyzer.shirtColorFor(sample),
      bodyShape: ratio >= 0.65 && ratio <= 2.5 ? shape : null,
      shoulderHipRatio: ratio,
      samplePoint: (x: centerX * width, y: centerY * height),
      landmarks: pose.points,
    );
  }

  static AutoPhotoEstimate _skinEstimate(
    Uint8List rgba,
    int width,
    int height,
    PoseDetection pose,
  ) {
    final nose = pose.points[0];
    final leftEye = pose.points[1];
    final rightEye = pose.points[2];
    final eyeWidth = (leftEye.x - rightEye.x).abs() * width;
    if (![nose, leftEye, rightEye].every((point) => point.visible) ||
        nose.score < 0.7 ||
        eyeWidth < 8 ||
        (leftEye.y - rightEye.y).abs() * height > eyeWidth * 0.4) {
      throw const AutoPhotoException(
        'A clear, front-facing face is needed. You can tap exposed skin instead.',
      );
    }
    // The small nose patch avoids assumptions about skin color or ethnicity.
    // Masks, makeup and lighting may invalidate it; the user sees and confirms it.
    final x = (nose.x * (width - 1)).round();
    final y = (nose.y * (height - 1)).round();
    final color = PhotoAnalyzer.sampleRgba(
      rgba: rgba,
      width: width,
      height: height,
      x: x,
      y: y,
      radius: math.max(1, (eyeWidth * 0.10).round()),
    );
    return AutoPhotoEstimate(
      skinToneArgb: color,
      samplePoint: (x: x.toDouble(), y: y.toDouble()),
      landmarks: pose.points,
    );
  }

  static int? _torsoColor(
    Uint8List rgba,
    int width,
    int height,
    PosePoint leftShoulder,
    PosePoint rightShoulder,
    PosePoint leftHip,
    PosePoint rightHip,
  ) {
    final buckets = <int, List<int>>{};
    var count = 0;
    // Sample only an inset upper-torso quadrilateral, away from arms/background
    // and the collar/waist. The dominant 32-level RGB bin resists shirt logos.
    for (var row = 0; row < 12; row++) {
      final t = 0.18 + row / 11 * 0.44;
      final lx = leftShoulder.x * (1 - t) + leftHip.x * t;
      final ly = leftShoulder.y * (1 - t) + leftHip.y * t;
      final rx = rightShoulder.x * (1 - t) + rightHip.x * t;
      final ry = rightShoulder.y * (1 - t) + rightHip.y * t;
      for (var col = 0; col < 15; col++) {
        final u = 0.25 + col / 14 * 0.5;
        final x = ((lx * (1 - u) + rx * u) * (width - 1)).round();
        final y = ((ly * (1 - u) + ry * u) * (height - 1)).round();
        final offset = (y * width + x) * 4;
        if (rgba[offset + 3] < 128) continue;
        final r = rgba[offset];
        final g = rgba[offset + 1];
        final b = rgba[offset + 2];
        final bucket = ((r >> 5) << 6) | ((g >> 5) << 3) | (b >> 5);
        buckets
            .putIfAbsent(bucket, () => [])
            .add(0xFF000000 | (r << 16) | (g << 8) | b);
        count++;
      }
    }
    if (count < 40) return null;
    final dominant = buckets.values.reduce(
      (a, b) => a.length >= b.length ? a : b,
    );
    if (dominant.length / count < 0.18) return null;
    int median(int shift) {
      final values = dominant.map((argb) => (argb >> shift) & 255).toList()
        ..sort();
      return values[values.length ~/ 2];
    }

    return 0xFF000000 | (median(16) << 16) | (median(8) << 8) | median(0);
  }
}
