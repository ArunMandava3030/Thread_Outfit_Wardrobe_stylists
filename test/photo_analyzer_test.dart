import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/services/photo_analyzer.dart';

void main() {
  group('PhotoAnalyzer.pixelAtContainedPosition', () {
    test('maps portrait photos without including side letterboxing', () {
      expect(
        PhotoAnalyzer.pixelAtContainedPosition(
          localX: 150,
          localY: 100,
          viewportWidth: 300,
          viewportHeight: 200,
          imageWidth: 100,
          imageHeight: 200,
        ),
        (x: 50, y: 100),
      );
      expect(
        PhotoAnalyzer.pixelAtContainedPosition(
          localX: 50,
          localY: 100,
          viewportWidth: 300,
          viewportHeight: 200,
          imageWidth: 100,
          imageHeight: 200,
        ),
        isNull,
      );
    });

    test('maps scaled landscape corners and rejects bottom letterboxing', () {
      expect(
        PhotoAnalyzer.pixelAtContainedPosition(
          localX: 0,
          localY: 50,
          viewportWidth: 200,
          viewportHeight: 200,
          imageWidth: 400,
          imageHeight: 200,
        ),
        (x: 0, y: 0),
      );
      expect(
        PhotoAnalyzer.pixelAtContainedPosition(
          localX: 199.9,
          localY: 149.9,
          viewportWidth: 200,
          viewportHeight: 200,
          imageWidth: 400,
          imageHeight: 200,
        ),
        (x: 399, y: 199),
      );
      expect(
        PhotoAnalyzer.pixelAtContainedPosition(
          localX: 100,
          localY: 150,
          viewportWidth: 200,
          viewportHeight: 200,
          imageWidth: 400,
          imageHeight: 200,
        ),
        isNull,
      );
    });
  });

  group('PhotoAnalyzer.sampleRgba', () {
    test('preserves RGBA channel ordering and returns opaque ARGB', () {
      expect(
        PhotoAnalyzer.sampleRgba(
          rgba: Uint8List.fromList([35, 100, 170, 255]),
          width: 1,
          height: 1,
          x: 0,
          y: 0,
        ),
        0xFF2364AA,
      );
    });

    test('clips edge patches and resists one bright highlight', () {
      final pixels = Uint8List.fromList([
        40,
        80,
        120,
        255,
        40,
        80,
        120,
        255,
        40,
        80,
        120,
        255,
        255,
        255,
        255,
        255,
      ]);
      expect(
        PhotoAnalyzer.sampleRgba(
          rgba: pixels,
          width: 2,
          height: 2,
          x: 0,
          y: 0,
          radius: 4,
        ),
        0xFF285078,
      );
    });

    test('does not treat transparent background as a colour', () {
      final pixels = Uint8List.fromList([255, 255, 255, 0, 20, 30, 40, 255]);
      expect(
        PhotoAnalyzer.sampleRgba(rgba: pixels, width: 2, height: 1, x: 0, y: 0),
        0xFF141E28,
      );
      expect(
        PhotoAnalyzer.sampleRgba(
          rgba: pixels,
          width: 2,
          height: 1,
          x: 0,
          y: 0,
          radius: 0,
        ),
        isNull,
      );
    });

    test('rejects coordinates beyond all four image edges', () {
      for (final coordinates in [(-1, 0), (0, -1), (1, 0), (0, 1)]) {
        expect(
          PhotoAnalyzer.sampleRgba(
            rgba: Uint8List.fromList([10, 20, 30, 255]),
            width: 1,
            height: 1,
            x: coordinates.$1,
            y: coordinates.$2,
          ),
          isNull,
        );
      }
    });

    test('rejects malformed pixel buffers and negative patch radius', () {
      expect(
        PhotoAnalyzer.sampleRgba(
          rgba: Uint8List(3),
          width: 1,
          height: 1,
          x: 0,
          y: 0,
        ),
        isNull,
      );
      expect(
        PhotoAnalyzer.sampleRgba(
          rgba: Uint8List(4),
          width: 1,
          height: 1,
          x: 0,
          y: 0,
          radius: -1,
        ),
        isNull,
      );
    });
  });

  test('colour naming keeps the original sampled value', () {
    const sample = 0xFF4775A1;
    final result = PhotoAnalyzer.shirtColorFor(sample);
    expect(result.argb, sample);
    expect(
      ShirtColor.presets.map((color) => color.name),
      contains(result.name),
    );
  });

  group('PhotoAnalyzer.classifyProportions', () {
    test('uses shoulders, waist and hips together', () {
      expect(
        PhotoAnalyzer.classifyProportions(
          shoulderWidth: 120,
          waistWidth: 80,
          hipWidth: 100,
        ),
        BodyShape.broadShoulders,
      );
      expect(
        PhotoAnalyzer.classifyProportions(
          shoulderWidth: 100,
          waistWidth: 80,
          hipWidth: 120,
        ),
        BodyShape.widerHips,
      );
      expect(
        PhotoAnalyzer.classifyProportions(
          shoulderWidth: 100,
          waistWidth: 115,
          hipWidth: 102,
        ),
        BodyShape.fullerMidsection,
      );
      expect(
        PhotoAnalyzer.classifyProportions(
          shoulderWidth: 104,
          waistWidth: 82,
          hipWidth: 100,
        ),
        BodyShape.balanced,
      );
    });

    test('classification is independent of photo resolution', () {
      expect(
        PhotoAnalyzer.classifyProportions(
          shoulderWidth: 0.36,
          waistWidth: 0.24,
          hipWidth: 0.30,
        ),
        PhotoAnalyzer.classifyProportions(
          shoulderWidth: 360,
          waistWidth: 240,
          hipWidth: 300,
        ),
      );
    });

    test('rejects missing or nonsensical measurements', () {
      for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          PhotoAnalyzer.classifyProportions(
            shoulderWidth: invalid,
            waistWidth: 90,
            hipWidth: 100,
          ),
          isNull,
        );
        expect(
          PhotoAnalyzer.classifyProportions(
            shoulderWidth: 100,
            waistWidth: invalid,
            hipWidth: 100,
          ),
          isNull,
        );
        expect(
          PhotoAnalyzer.classifyProportions(
            shoulderWidth: 100,
            waistWidth: 90,
            hipWidth: invalid,
          ),
          isNull,
        );
      }
    });
  });
}
