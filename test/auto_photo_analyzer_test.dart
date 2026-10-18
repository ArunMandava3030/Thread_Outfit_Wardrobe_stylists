import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/services/auto_photo_analyzer.dart';

void main() {
  group('MoveNet letterboxing', () {
    test(
      'preserves portrait aspect, RGB order, padding and original coordinates',
      () {
        final pixels = _solid(2, 4, 0xFF2356A1);
        final input = PoseInput.fromRgba(pixels, 2, 4, size: 4);
        expect(input.scaledWidth, 2);
        expect(input.scaledHeight, 4);
        expect(input.left, 1);
        expect(input.top, 0);
        expect(input.rgb.sublist(0, 3), [0, 0, 0]);
        expect(input.rgb.sublist(3, 6), [0x23, 0x56, 0xA1]);
        final point = input.restore(0.5, 0.75, 0.95);
        expect(point.x, 0.5);
        expect(point.y, 0.75);
        expect(point.score, 0.95);
        expect(input.restore(0, 0, 0.99).visible, isFalse);
      },
    );

    test(
      'landscape padding and transparent pixels cannot become bright inputs',
      () {
        final input = PoseInput.fromRgba(
          _solid(4, 2, 0x00FFFFFF),
          4,
          2,
          size: 4,
        );
        expect(input.top, 1);
        expect(input.left, 0);
        expect(input.rgb.every((value) => value == 0), isTrue);
        final center = input.restore(0.5, 0.5, 0.9);
        expect(center.x, 0.5);
        expect(center.y, 0.5);
      },
    );

    test('rejects malformed buffers and zero dimensions', () {
      expect(
        () => PoseInput.fromRgba(Uint8List(3), 1, 1),
        throwsFormatException,
      );
      expect(
        () => PoseInput.fromRgba(Uint8List(0), 0, 1),
        throwsFormatException,
      );
    });
  });

  group('Pose-guided photo estimates', () {
    test(
      'samples an inset torso and resists background and a small bright logo',
      () {
        final pixels = _solid(100, 100, 0xFFFFFFFF);
        for (var y = 29; y < 58; y++) {
          for (var x = 37; x < 64; x++) {
            _setPixel(pixels, 100, x, y, 0xFF71845B);
          }
        }
        for (var y = 40; y < 44; y++) {
          for (var x = 48; x < 52; x++) {
            _setPixel(pixels, 100, x, y, 0xFFFFFFFF);
          }
        }
        final result = _estimate(pixels, _frontPose());
        expect(result.shirtColor?.argb, 0xFF71845B);
        expect(result.bodyShape, BodyShape.balanced);
        expect(result.skinToneArgb, isNull);
        expect(result.shoulderHipRatio, closeTo(4 / 3, 0.001));
        expect(result.samplePoint!.x, closeTo(50, 0.001));
      },
    );

    test(
      'body guide only describes shoulder/hip spacing, never waist shape',
      () {
        final pixels = _solid(100, 100, 0xFF71845B);
        final broad = _frontPose()
          ..[11] = const PosePoint(0.62, 0.7, 0.99)
          ..[12] = const PosePoint(0.38, 0.7, 0.99);
        final wideHips = _frontPose()
          ..[11] = const PosePoint(0.78, 0.7, 0.99)
          ..[12] = const PosePoint(0.22, 0.7, 0.99);
        expect(_estimate(pixels, broad).bodyShape, BodyShape.broadShoulders);
        expect(_estimate(pixels, wideHips).bodyShape, BodyShape.widerHips);
        for (final points in [broad, wideHips, _frontPose()]) {
          expect(
            _estimate(pixels, points).bodyShape,
            isNot(BodyShape.fullerMidsection),
          );
        }
      },
    );

    test(
      'low confidence, multiple people and cropped hips require manual fallback',
      () {
        final pixels = _solid(100, 100, 0xFF71845B);
        final low = _frontPose()..[5] = const PosePoint(0.7, 0.25, 0.3);
        final cropped = _frontPose()..[11] = const PosePoint(0.65, 1.2, 0.99);
        for (final pose in [
          PoseDetection(low),
          PoseDetection(cropped),
          PoseDetection(_frontPose(), people: 2),
          const PoseDetection([], people: 0),
        ]) {
          expect(
            () => AutoPhotoAnalyzer.estimateFromPose(
              rgba: pixels,
              width: 100,
              height: 100,
              pose: pose,
            ),
            throwsA(isA<AutoPhotoException>()),
          );
        }
      },
    );

    test('tilted, sideways and crossed torso landmarks require correction', () {
      final pixels = _solid(100, 100, 0xFF71845B);
      final tilted = _frontPose()..[5] = const PosePoint(0.7, 0.4, 0.99);
      final sideways = _frontPose()
        ..[5] = const PosePoint(0.7, 0.25, 0.99, z: 0.4)
        ..[6] = const PosePoint(0.3, 0.25, 0.99, z: -0.4);
      final crossed = _frontPose()
        ..[11] = const PosePoint(0.35, 0.7, 0.99)
        ..[12] = const PosePoint(0.65, 0.7, 0.99);
      for (final points in [tilted, sideways, crossed]) {
        expect(
          () => _estimate(pixels, points),
          throwsA(isA<AutoPhotoException>()),
        );
      }
    });

    test(
      'optional face sampling works without torso landmarks and preserves RGB',
      () {
        final pixels = _solid(200, 200, 0xFFAE8062);
        final points = List<PosePoint>.filled(17, const PosePoint(0, 0, 0));
        points[0] = const PosePoint(0.5, 0.3, 0.99);
        points[1] = const PosePoint(0.55, 0.25, 0.99);
        points[2] = const PosePoint(0.45, 0.25, 0.99);
        final result = AutoPhotoAnalyzer.estimateFromPose(
          rgba: pixels,
          width: 200,
          height: 200,
          pose: PoseDetection(points),
          sampleSkin: true,
        );
        expect(result.skinToneArgb, 0xFFAE8062);
        expect(result.shirtColor, isNull);
        expect(result.bodyShape, isNull);
        points[0] = const PosePoint(0.5, 0.3, 0.4);
        expect(
          () => AutoPhotoAnalyzer.estimateFromPose(
            rgba: pixels,
            width: 200,
            height: 200,
            pose: PoseDetection(points),
            sampleSkin: true,
          ),
          throwsA(isA<AutoPhotoException>()),
        );
      },
    );

    test('transparent torso cannot become a shirt-color estimate', () {
      final result = _estimate(_solid(100, 100, 0x00123456), _frontPose());
      expect(result.shirtColor, isNull);
    });
  });
}

AutoPhotoEstimate _estimate(Uint8List pixels, List<PosePoint> points) =>
    AutoPhotoAnalyzer.estimateFromPose(
      rgba: pixels,
      width: 100,
      height: 100,
      pose: PoseDetection(points),
    );

List<PosePoint> _frontPose() {
  final points = List<PosePoint>.filled(17, const PosePoint(0, 0, 0));
  points[5] = const PosePoint(0.7, 0.25, 0.99);
  points[6] = const PosePoint(0.3, 0.25, 0.99);
  points[11] = const PosePoint(0.65, 0.7, 0.99);
  points[12] = const PosePoint(0.35, 0.7, 0.99);
  return points;
}

Uint8List _solid(int width, int height, int argb) {
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      _setPixel(pixels, width, x, y, argb);
    }
  }
  return pixels;
}

void _setPixel(Uint8List rgba, int width, int x, int y, int argb) {
  final offset = (y * width + x) * 4;
  rgba[offset] = (argb >> 16) & 255;
  rgba[offset + 1] = (argb >> 8) & 255;
  rgba[offset + 2] = argb & 255;
  rgba[offset + 3] = (argb >> 24) & 255;
}
