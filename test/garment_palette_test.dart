import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/services/garment_palette_analyzer.dart';

void main() {
  const analyzer = GarmentPaletteAnalyzer();

  test(
    'red black and white checks retain neutral colors and populations',
    () async {
      final pixels = _pixels(24, 24, (x, y) {
        final square = (x ~/ 4 + y ~/ 4) % 4;
        return square < 2
            ? 0xFFCC2222
            : square == 2
            ? 0xFF000000
            : 0xFFFFFFFF;
      });
      final result = await analyzer.analyze(
        rgba: pixels,
        width: 24,
        height: 24,
        left: 0,
        top: 0,
        right: 24,
        bottom: 24,
      );
      expect(result.map((swatch) => swatch.color.argb), [
        0xFFCC2222,
        0xFF000000,
        0xFFFFFFFF,
      ]);
      // A six-by-six check grid has 19 red, 9 black and 8 white squares.
      expect(result.map((swatch) => swatch.population), [304, 144, 128]);
    },
  );

  test('only the requested garment rectangle contributes colors', () async {
    final pixels = _pixels(
      30,
      20,
      (x, y) => x >= 10 && x < 20 && y >= 5 && y < 15 ? 0xFF183151 : 0xFF00FF00,
    );
    final result = await analyzer.analyze(
      rgba: pixels,
      width: 30,
      height: 20,
      left: 10,
      top: 5,
      right: 20,
      bottom: 15,
    );
    expect(result, hasLength(1));
    expect(result.single.color.argb, 0xFF183151);
    expect(result.single.population, 100);
  });

  test(
    'all dark garment colors are retained without a brightness filter',
    () async {
      final result = await analyzer.analyze(
        rgba: _pixels(20, 10, (x, y) => x < 10 ? 0xFF000000 : 0xFF132E55),
        width: 20,
        height: 10,
        left: 0,
        top: 0,
        right: 20,
        bottom: 10,
      );
      expect(result, hasLength(2));
      expect(
        result.map((swatch) => swatch.color.argb),
        containsAll([0xFF000000, 0xFF132E55]),
      );
    },
  );

  test(
    'transparent and translucent pixels do not become garment colors',
    () async {
      final result = await analyzer.analyze(
        rgba: _pixels(
          30,
          10,
          (x, y) => x < 10
              ? 0x0000FF00
              : x < 20
              ? 0x8000FF00
              : 0xFFCC2222,
        ),
        width: 30,
        height: 10,
        left: 0,
        top: 0,
        right: 30,
        bottom: 10,
      );
      expect(result, hasLength(1));
      expect(result.single.color.argb, 0xFFCC2222);
      expect(result.single.population, 100);
      expect(
        await analyzer.analyze(
          rgba: Uint8List(400),
          width: 10,
          height: 10,
          left: 0,
          top: 0,
          right: 10,
          bottom: 10,
        ),
        isEmpty,
      );
    },
  );

  test(
    'malformed buffers and out of bounds or empty regions return nothing',
    () async {
      final pixels = _pixels(10, 10, (x, y) => 0xFFFFFFFF);
      for (final region in [
        (-1, 0, 10, 10),
        (0, -1, 10, 10),
        (0, 0, 11, 10),
        (0, 0, 10, 11),
        (5, 0, 5, 10),
        (0, 5, 10, 5),
        (7, 2, 3, 8),
      ]) {
        expect(
          await analyzer.analyze(
            rgba: pixels,
            width: 10,
            height: 10,
            left: region.$1,
            top: region.$2,
            right: region.$3,
            bottom: region.$4,
          ),
          isEmpty,
        );
      }
      for (final length in [0, 399, 401]) {
        expect(
          await analyzer.analyze(
            rgba: Uint8List(length),
            width: 10,
            height: 10,
            left: 0,
            top: 0,
            right: 10,
            bottom: 10,
          ),
          isEmpty,
        );
      }
      expect(
        await analyzer.analyze(
          rgba: pixels,
          width: 0,
          height: -10,
          left: 0,
          top: 0,
          right: 10,
          bottom: 10,
        ),
        isEmpty,
      );
    },
  );

  test(
    'large images use at most 4096 sampled pixels and have stable results',
    () async {
      final pixels = _pixels(
        256,
        256,
        (x, y) => (x + y) % 3 == 0 ? 0xFFFFFFFF : 0xFFCC2222,
      );
      Future<List<GarmentSwatch>> read() => analyzer.analyze(
        rgba: pixels,
        width: 256,
        height: 256,
        left: 0,
        top: 0,
        right: 256,
        bottom: 256,
      );
      final first = await read();
      final second = await read();
      expect(
        first.fold<int>(0, (total, swatch) => total + swatch.population),
        4096,
      );
      expect(
        first.map((swatch) => (swatch.color.argb, swatch.population)),
        second.map((swatch) => (swatch.color.argb, swatch.population)),
      );
      expect(first.first.color.argb, 0xFFCC2222);
      expect(first, hasLength(2));
    },
  );

  test(
    'nearby shades merge without averaging away the main representative',
    () async {
      final result = await analyzer.analyze(
        rgba: _pixels(20, 10, (x, y) => x < 12 ? 0xFF102030 : 0xFF122232),
        width: 20,
        height: 10,
        left: 0,
        top: 0,
        right: 20,
        bottom: 10,
      );
      expect(result, hasLength(1));
      expect(result.single.population, 200);
    },
  );

  test(
    'many colors return at most three swatches in population order',
    () async {
      const colors = [
        0xFFFF0000,
        0xFF00FF00,
        0xFF0000FF,
        0xFFFFFFFF,
        0xFF000000,
      ];
      final result = await analyzer.analyze(
        rgba: _pixels(50, 10, (x, y) => colors[x ~/ 10]),
        width: 50,
        height: 10,
        left: 0,
        top: 0,
        right: 50,
        bottom: 10,
      );
      expect(result, hasLength(3));
      for (var i = 1; i < result.length; i++) {
        expect(
          result[i - 1].population,
          greaterThanOrEqualTo(result[i].population),
        );
      }
    },
  );
}

Uint8List _pixels(int width, int height, int Function(int, int) colorAt) {
  final result = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final argb = colorAt(x, y);
      final offset = (y * width + x) * 4;
      result[offset] = (argb >> 16) & 255;
      result[offset + 1] = (argb >> 8) & 255;
      result[offset + 2] = argb & 255;
      result[offset + 3] = (argb >> 24) & 255;
    }
  }
  return result;
}
