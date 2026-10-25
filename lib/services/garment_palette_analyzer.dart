import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_color_utilities/quantize/quantizer_celebi.dart';
import 'package:material_color_utilities/utils/color_utils.dart';

import '../models/style_models.dart';
import 'photo_analyzer.dart';

/// A representative garment colour and the number of sampled pixels it covers.
class GarmentSwatch {
  const GarmentSwatch({required this.color, required this.population});

  final ShirtColor color;
  final int population;
}

/// Local colour extraction from an explicitly selected garment rectangle.
///
/// This does not locate clothing, identify fabric or classify patterns. In
/// particular, neutral colours are retained: black and white are often the
/// important colours in checks, stripes and prints.
class GarmentPaletteAnalyzer {
  const GarmentPaletteAnalyzer();

  static const maxSampledPixels = 4096;
  static const maxPaletteColors = 3;

  /// [left], [top] are inclusive and [right], [bottom] are exclusive. Invalid
  /// or out-of-image rectangles return no result; they are never silently
  /// expanded to include a background. Only fully opaque pixels are used.
  Future<List<GarmentSwatch>> analyze({
    required Uint8List rgba,
    required int width,
    required int height,
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) async {
    if (width <= 0 ||
        height <= 0 ||
        rgba.length != width * height * 4 ||
        left < 0 ||
        top < 0 ||
        right > width ||
        bottom > height ||
        left >= right ||
        top >= bottom) {
      return const [];
    }
    final regionWidth = right - left;
    final area = regionWidth * (bottom - top);
    final sampleCount = math.min(area, maxSampledPixels);
    final pixels = <int>[];
    for (var index = 0; index < sampleCount; index++) {
      // One deterministic sample per stratum avoids repeatedly hitting the
      // same phase of a regular check/stripe while bounding quantizer work.
      final start = index * area ~/ sampleCount;
      final end = (index + 1) * area ~/ sampleCount;
      final jitter =
          ((index * 1103515245 + 12345) & 0x7fffffff) % (end - start);
      final position = start + jitter;
      final x = left + position % regionWidth;
      final y = top + position ~/ regionWidth;
      final offset = (y * width + x) * 4;
      if (rgba[offset + 3] != 255) continue;
      pixels.add(
        0xFF000000 |
            (rgba[offset] << 16) |
            (rgba[offset + 1] << 8) |
            rgba[offset + 2],
      );
    }
    if (pixels.isEmpty) return const [];
    final quantized = await QuantizerCelebi().quantize(pixels, 12);
    final entries = quantized.colorToCount.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    final merged = <({int argb, int population, List<double> lab})>[];
    for (final entry in entries) {
      if (entry.value <= 0) continue;
      final lab = ColorUtils.labFromArgb(entry.key);
      final neighbor = merged.indexWhere((swatch) {
        var squaredDistance = 0.0;
        for (var channel = 0; channel < 3; channel++) {
          final delta = swatch.lab[channel] - lab[channel];
          squaredDistance += delta * delta;
        }
        return squaredDistance < 8 * 8;
      });
      if (neighbor == -1) {
        merged.add((argb: entry.key, population: entry.value, lab: lab));
      } else {
        final existing = merged[neighbor];
        // Keep the more populous representative rather than inventing an
        // averaged colour that may not actually appear in the garment.
        merged[neighbor] = (
          argb: existing.argb,
          population: existing.population + entry.value,
          lab: existing.lab,
        );
      }
    }
    merged.sort((a, b) {
      final byCount = b.population.compareTo(a.population);
      return byCount != 0 ? byCount : a.argb.compareTo(b.argb);
    });
    return List.unmodifiable([
      for (final swatch in merged.take(maxPaletteColors))
        GarmentSwatch(
          color: PhotoAnalyzer.shirtColorFor(swatch.argb),
          population: swatch.population,
        ),
    ]);
  }
}
