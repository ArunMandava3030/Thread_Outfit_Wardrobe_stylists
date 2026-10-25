import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/garment_visual_profile.dart';
import 'package:thread_style/services/garment_visual_analyzer.dart';

void main() {
  const analyzer = GarmentVisualAnalyzer();

  Future<GarmentVisualProfile> read(
    int Function(int, int) colorAt, {
    int width = 96,
    int height = 96,
  }) async {
    final result = await analyzer.analyze(
      rgba: _pixels(width, height, colorAt),
      width: width,
      height: height,
      left: 0,
      top: 0,
      right: width,
      bottom: height,
    );
    expect(result, isNotNull);
    expect(result!.isReliable, isTrue);
    for (final metric in [
      result.contrast,
      result.detailDensity,
      result.directionality,
      result.regularity,
    ]) {
      expect(metric, inInclusiveRange(0.0, 1.0));
    }
    return result;
  }

  test(
    'plain fabric stays quiet with exact color and a bounded preview',
    () async {
      final profile = await read((x, y) => 0xFF4279A6);
      expect(profile.hasDetail, isFalse);
      expect(profile.detailDensity, 0);
      expect(profile.contrast, lessThan(.001));
      expect(profile.directionality, 0);
      expect(profile.regularity, 0);
      expect(profile.palette.single.color.argb, 0xFF4279A6);
      expect(profile.palette.single.share, 1);
      expect(profile.previewArgb, hasLength(256));
      expect(profile.previewArgb.toSet(), {0xFF4279A6});
    },
  );

  test(
    'stripes carry orientation and repetition while checks have lower coherence',
    () async {
      final vertical = await read(
        (x, y) => x ~/ 6 % 2 == 0 ? 0xFF101010 : 0xFFF0F0F0,
      );
      final horizontal = await read(
        (x, y) => y ~/ 6 % 2 == 0 ? 0xFF101010 : 0xFFF0F0F0,
      );
      final checks = await read(
        (x, y) => (x ~/ 6 + y ~/ 6) % 2 == 0 ? 0xFF101010 : 0xFFF0F0F0,
      );
      expect(vertical.hasDetail, isTrue);
      expect(horizontal.hasDetail, isTrue);
      expect(checks.hasDetail, isTrue);
      expect(vertical.directionality, greaterThan(.8));
      expect(horizontal.directionality, greaterThan(.8));
      expect(vertical.dominantAngle, closeTo(90, 3));
      expect(horizontal.dominantAngle, anyOf(lessThan(3), greaterThan(177)));
      expect(checks.directionality, lessThan(vertical.directionality));
      expect(vertical.regularity, greaterThan(.6));
      expect(horizontal.regularity, greaterThan(.6));
      expect(checks.regularity, greaterThan(.6));
      expect(vertical.signature, isNot(horizontal.signature));
    },
  );

  test(
    'irregular designs are described without a named-pattern label',
    () async {
      final random = math.Random(17);
      final tiles = List.generate(12 * 12, (_) => random.nextBool());
      final irregular = await read(
        (x, y) => tiles[(y ~/ 8) * 12 + x ~/ 8] ? 0xFFBA3538 : 0xFF22354A,
      );
      final repeated = await read(
        (x, y) => x ~/ 6 % 2 == 0 ? 0xFFBA3538 : 0xFF22354A,
      );
      expect(irregular.hasDetail, isTrue);
      expect(irregular.regularity, lessThan(repeated.regularity));
      expect(
        irregular.shortDescription.toLowerCase(),
        isNot(contains('plaid')),
      );
      expect(
        irregular.stylingDescription.toLowerCase(),
        isNot(contains('flannel')),
      );
    },
  );

  test(
    'soft noise and broad shadows do not become busy repeated fabric',
    () async {
      final shadow = await read((x, y) {
        final value = (35 + x * 1.8).round();
        return 0xFF000000 | value << 16 | value << 8 | value;
      });
      final random = math.Random(71);
      final noise = List.generate(96 * 96, (_) => 120 + random.nextInt(15) - 7);
      final noisy = await read((x, y) {
        final value = noise[y * 96 + x];
        return 0xFF000000 | value << 16 | value << 8 | value;
      });
      expect(shadow.hasDetail, isFalse);
      expect(shadow.regularity, 0);
      expect(noisy.hasDetail, isFalse);
      expect(noisy.regularity, 0);
    },
  );

  test(
    'small visible accent retains its measured share beside dark and light colors',
    () async {
      final profile = await read(
        (x, y) => x < 4
            ? 0xFFCC2222
            : x < 50
            ? 0xFF101010
            : 0xFFF0F0F0,
      );
      final red = profile.palette.singleWhere(
        (swatch) => swatch.color.argb == 0xFFCC2222,
      );
      expect(profile.palette, hasLength(3));
      expect(red.share, closeTo(4 / 96, .015));
      expect(
        profile.palette.fold<double>(0, (sum, swatch) => sum + swatch.share),
        closeTo(1, .001),
      );
      expect(profile.palette.first.share, greaterThan(red.share));
    },
  );

  test(
    'same palette with a different spatial layout has a different signature',
    () async {
      final a = await read((x, y) => x < 48 ? 0xFF225599 : 0xFFCC8822);
      final b = await read((x, y) => y < 48 ? 0xFF225599 : 0xFFCC8822);
      expect(
        a.palette.map((swatch) => swatch.color.argb).toSet(),
        b.palette.map((swatch) => swatch.color.argb).toSet(),
      );
      expect(a.signature, isNot(b.signature));
      expect(a.previewArgb, isNot(b.previewArgb));
      final again = await read((x, y) => x < 48 ? 0xFF225599 : 0xFFCC8822);
      expect(a.signature, again.signature);
    },
  );

  test(
    'only selected crop contributes and large input remains bounded',
    () async {
      final pixels = _pixels(
        480,
        320,
        (x, y) =>
            x >= 80 && x < 400 && y >= 80 && y < 240 ? 0xFF4279A6 : 0xFF00FF00,
      );
      final profile = await analyzer.analyze(
        rgba: pixels,
        width: 480,
        height: 320,
        left: 80,
        top: 80,
        right: 400,
        bottom: 240,
      );
      expect(profile!.isReliable, isTrue);
      expect(profile.sampleWidth, 96);
      expect(profile.sampleHeight, 48);
      expect(profile.palette.single.color.argb, 0xFF4279A6);
      expect(profile.previewArgb.length, 256);
    },
  );

  test(
    'invalid, tiny, narrow or insufficiently opaque regions are rejected',
    () async {
      final pixels = _pixels(30, 30, (x, y) => 0xFFFFFFFF);
      for (final region in [
        (0, 0, 5, 5),
        (-1, 0, 30, 30),
        (0, 0, 31, 30),
        (15, 0, 10, 30),
        (0, 0, 30, 4),
        (0, 0, 30, 31),
      ]) {
        expect(
          await analyzer.analyze(
            rgba: pixels,
            width: 30,
            height: 30,
            left: region.$1,
            top: region.$2,
            right: region.$3,
            bottom: region.$4,
          ),
          isNull,
        );
      }
      expect(
        await analyzer.analyze(
          rgba: Uint8List(5),
          width: 30,
          height: 30,
          left: 0,
          top: 0,
          right: 30,
          bottom: 30,
        ),
        isNull,
      );
      expect(
        await analyzer.analyze(
          rgba: _pixels(30, 30, (x, y) => x < 15 ? 0xFFFFFFFF : 0),
          width: 30,
          height: 30,
          left: 0,
          top: 0,
          right: 30,
          bottom: 30,
        ),
        isNull,
      );
    },
  );

  test(
    'large patterned crop has bounded analysis with diagnostic timing',
    () async {
      final pixels = _pixels(
        1024,
        768,
        (x, y) => (x ~/ 64 + y ~/ 64) % 2 == 0 ? 0xFFCC2222 : 0xFF17324A,
      );
      final stopwatch = Stopwatch()..start();
      final result = await analyzer.analyze(
        rgba: pixels,
        width: 1024,
        height: 768,
        left: 0,
        top: 0,
        right: 1024,
        bottom: 768,
      );
      stopwatch.stop();
      debugPrint(
        'Visual analyzer 1024x768 crop: ${stopwatch.elapsedMilliseconds} ms '
        '(desktop test runtime; not a mobile performance guarantee)',
      );
      expect(result!.sampleWidth, 96);
      expect(result.sampleHeight, 72);
      expect(result.hasDetail, isTrue);
      expect(result.previewArgb.length, 256);
    },
  );
}

Uint8List _pixels(int width, int height, int Function(int, int) colorAt) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final color = colorAt(x, y), i = (y * width + x) * 4;
      bytes[i] = color >> 16 & 255;
      bytes[i + 1] = color >> 8 & 255;
      bytes[i + 2] = color & 255;
      bytes[i + 3] = color >> 24 & 255;
    }
  }
  return bytes;
}
