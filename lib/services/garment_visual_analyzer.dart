import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_color_utilities/quantize/quantizer_celebi.dart';
import 'package:material_color_utilities/utils/color_utils.dart';

import '../models/garment_visual_profile.dart';
import 'photo_analyzer.dart';

/// Reads continuous visual structure inside an explicitly selected rectangle.
/// It does not classify named patterns or identify a fabric or garment type.
class GarmentVisualAnalyzer {
  const GarmentVisualAnalyzer();

  static const maxGridDimension = 96;
  static const maxPaletteSamples = 4096;

  /// Rectangle bounds are inclusive left/top and exclusive right/bottom.
  /// Very small, narrow, malformed or mostly transparent crops are rejected.
  Future<GarmentVisualProfile?> analyze({
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
        right - left < 12 ||
        bottom - top < 12) {
      return null;
    }
    final cropWidth = right - left, cropHeight = bottom - top;
    final scale = math.min(
      1.0,
      maxGridDimension / math.max(cropWidth, cropHeight),
    );
    final gridWidth = (cropWidth * scale).round();
    final gridHeight = (cropHeight * scale).round();
    if (gridWidth < 12 || gridHeight < 12) return null;
    final grid = List<int>.filled(gridWidth * gridHeight, 0);
    final colors = <int>[];
    for (var y = 0; y < gridHeight; y++) {
      for (var x = 0; x < gridWidth; x++) {
        final position = y * gridWidth + x;
        final x0 = x * cropWidth ~/ gridWidth;
        final x1 = (x + 1) * cropWidth ~/ gridWidth;
        final y0 = y * cropHeight ~/ gridHeight;
        final y1 = (y + 1) * cropHeight ~/ gridHeight;
        // Stratified jitter avoids sampling only one phase of tiny checks.
        final seed = (position * 1103515245 + 12345) & 0x7fffffff;
        final sx = left + x0 + seed % (x1 - x0);
        final sy = top + y0 + ((seed >> 8) % (y1 - y0));
        final offset = (sy * width + sx) * 4;
        if (rgba[offset + 3] != 255) continue;
        final argb =
            0xFF000000 |
            (rgba[offset] << 16) |
            (rgba[offset + 1] << 8) |
            rgba[offset + 2];
        grid[position] = argb;
        colors.add(argb);
      }
    }
    final coverage = colors.length / grid.length;
    if (coverage < .75 || colors.length < 144) return null;

    final smooth = _smooth(grid, gridWidth, gridHeight);
    final channels = List.generate(3, (_) => <double>[]);
    for (var i = 0; i < grid.length; i++) {
      if (grid[i] == 0) continue;
      for (var c = 0; c < 3; c++) {
        channels[c].add(smooth[i * 3 + c]);
      }
    }
    var rangeSquared = 0.0, varianceSum = 0.0;
    for (final values in channels) {
      final mean = values.reduce((a, b) => a + b) / values.length;
      varianceSum +=
          values.fold<double>(
            0,
            (sum, value) => sum + (value - mean) * (value - mean),
          ) /
          values.length;
      values.sort();
      final low = values[(values.length * .1).floor()];
      final high = values[((values.length - 1) * .9).floor()];
      rangeSquared += (high - low) * (high - low);
    }
    final contrast = math
        .max(math.sqrt(rangeSquared / 3) / .75, math.sqrt(varianceSum / 3) * 3)
        .clamp(0.0, 1.0);

    var edgeCount = 0, usableEdges = 0;
    var tensorXX = 0.0, tensorYY = 0.0, tensorXY = 0.0;
    final gradient = List<double>.filled(grid.length * 6, 0);
    final validGradient = List<bool>.filled(grid.length, false);
    for (var y = 1; y < gridHeight - 1; y++) {
      for (var x = 1; x < gridWidth - 1; x++) {
        final i = y * gridWidth + x;
        if ([
          i,
          i - 1,
          i + 1,
          i - gridWidth,
          i + gridWidth,
        ].any((index) => grid[index] == 0)) {
          continue;
        }
        usableEdges++;
        validGradient[i] = true;
        var xx = 0.0, yy = 0.0, xy = 0.0;
        for (var c = 0; c < 3; c++) {
          final dx = (smooth[(i + 1) * 3 + c] - smooth[(i - 1) * 3 + c]) / 2;
          final dy =
              (smooth[(i + gridWidth) * 3 + c] -
                  smooth[(i - gridWidth) * 3 + c]) /
              2;
          gradient[i * 6 + c * 2] = dx;
          gradient[i * 6 + c * 2 + 1] = dy;
          xx += dx * dx;
          yy += dy * dy;
          xy += dx * dy;
        }
        // Small sensor noise and broad lighting gradients are not treated as
        // fabric detail. No skin-colour or brightness exclusion is used.
        if (math.sqrt((xx + yy) / 3) < .035) continue;
        edgeCount++;
        tensorXX += xx;
        tensorYY += yy;
        tensorXY += xy;
      }
    }
    if (usableEdges < 64) return null;
    final density = (edgeCount / usableEdges).clamp(0.0, 1.0);
    final tensorEnergy = tensorXX + tensorYY;
    final directional =
        density >= .04 && contrast >= .07 && tensorEnergy > 1e-8;
    final directionality = directional
        ? (math.sqrt(
                    math.pow(tensorXX - tensorYY, 2) + 4 * tensorXY * tensorXY,
                  ) /
                  tensorEnergy)
              .clamp(0.0, 1.0)
        : 0.0;
    final angle = directional
        ? ((math.atan2(2 * tensorXY, tensorXX - tensorYY) * 90 / math.pi + 90) %
              180)
        : 0.0;
    final regularity = density >= .10 && contrast >= .07
        ? math.max(
            _repetition(gradient, validGradient, gridWidth, gridHeight, true),
            _repetition(gradient, validGradient, gridWidth, gridHeight, false),
          )
        : 0.0;
    final palette = await _palette(colors);
    if (palette.isEmpty) return null;
    return GarmentVisualProfile(
      contrast: contrast,
      detailDensity: density,
      directionality: directionality,
      dominantAngle: angle,
      regularity: regularity,
      palette: palette,
      previewArgb: List.unmodifiable(_preview(grid, gridWidth, gridHeight)),
      sampleWidth: gridWidth,
      sampleHeight: gridHeight,
      opaqueCoverage: coverage,
    );
  }

  List<double> _smooth(List<int> grid, int width, int height) {
    final output = List<double>.filled(grid.length * 3, 0);
    const weights = [1, 2, 1];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var total = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final sx = x + dx, sy = y + dy;
            if (sx < 0 || sx >= width || sy < 0 || sy >= height) continue;
            final argb = grid[sy * width + sx];
            if (argb == 0) continue;
            final weight = weights[dx + 1] * weights[dy + 1];
            total += weight;
            for (var c = 0; c < 3; c++) {
              output[(y * width + x) * 3 + c] +=
                  ((argb >> (16 - c * 8)) & 255) / 255 * weight;
            }
          }
        }
        if (total == 0) continue;
        for (var c = 0; c < 3; c++) {
          output[(y * width + x) * 3 + c] /= total;
        }
      }
    }
    return output;
  }

  /// A repeated motif needs a correlation peak after a trough, and at least
  /// three potential repetitions across the crop. Smooth shadows or a single
  /// boundary cannot qualify merely because nearby pixels look similar.
  double _repetition(
    List<double> data,
    List<bool> valid,
    int width,
    int height,
    bool horizontal,
  ) {
    final limit = math.min(32, (horizontal ? width : height) ~/ 3);
    if (limit < 4) return 0;
    final correlations = <double>[];
    for (var lag = 1; lag <= limit; lag++) {
      var dot = 0.0, aEnergy = 0.0, bEnergy = 0.0;
      var pairs = 0;
      for (var y = 1; y < height - 1 - (horizontal ? 0 : lag); y++) {
        for (var x = 1; x < width - 1 - (horizontal ? lag : 0); x++) {
          final a = y * width + x;
          final b = a + (horizontal ? lag : lag * width);
          if (!valid[a] || !valid[b]) continue;
          pairs++;
          for (var c = 0; c < 6; c++) {
            final av = data[a * 6 + c], bv = data[b * 6 + c];
            dot += av * bv;
            aEnergy += av * av;
            bEnergy += bv * bv;
          }
        }
      }
      correlations.add(
        pairs >= 64 && aEnergy > 1e-6 && bEnergy > 1e-6
            ? (dot / math.sqrt(aEnergy * bEnergy)).clamp(-1.0, 1.0)
            : 0,
      );
    }
    var score = 0.0, trough = 1.0;
    for (var i = 0; i < correlations.length; i++) {
      final value = correlations[i];
      if (i >= 2 &&
          trough < .20 &&
          value >= .30 &&
          value >= correlations[i - 1] &&
          (i == correlations.length - 1 || value >= correlations[i + 1])) {
        score = math.max(score, ((value - .25) / .70).clamp(0.0, 1.0));
      }
      trough = math.min(trough, value);
    }
    return score;
  }

  Future<List<VisualColorShare>> _palette(List<int> colors) async {
    final count = math.min(maxPaletteSamples, colors.length);
    final samples = <int>[];
    for (var i = 0; i < count; i++) {
      final start = i * colors.length ~/ count;
      final end = (i + 1) * colors.length ~/ count;
      final jitter = ((i * 1103515245 + 12345) & 0x7fffffff) % (end - start);
      samples.add(colors[start + jitter]);
    }
    final result = await QuantizerCelebi().quantize(samples, 6);
    final entries = result.colorToCount.entries.toList()
      ..sort(
        (a, b) => b.value != a.value
            ? b.value.compareTo(a.value)
            : a.key.compareTo(b.key),
      );
    final merged = <({int argb, int count, List<double> lab})>[];
    for (final entry in entries) {
      if (entry.value <= 0) continue;
      final lab = ColorUtils.labFromArgb(entry.key);
      final existing = merged.indexWhere((swatch) {
        var distance = 0.0;
        for (var c = 0; c < 3; c++) {
          distance += math.pow(swatch.lab[c] - lab[c], 2);
        }
        return distance < 6 * 6;
      });
      if (existing < 0) {
        merged.add((argb: entry.key, count: entry.value, lab: lab));
      } else {
        final previous = merged[existing];
        merged[existing] = (
          argb: previous.argb,
          count: previous.count + entry.value,
          lab: previous.lab,
        );
      }
    }
    merged.sort(
      (a, b) => b.count != a.count
          ? b.count.compareTo(a.count)
          : a.argb.compareTo(b.argb),
    );
    return List.unmodifiable([
      for (final color in merged)
        VisualColorShare(
          color: PhotoAnalyzer.shirtColorFor(color.argb),
          share: color.count / samples.length,
        ),
    ]);
  }

  List<int> _preview(List<int> grid, int width, int height) {
    final output = <int>[];
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final left = x * width ~/ 16, top = y * height ~/ 16;
        final right = math.max(left + 1, (x + 1) * width ~/ 16);
        final bottom = math.max(top + 1, (y + 1) * height ~/ 16);
        var r = 0, g = 0, b = 0, count = 0;
        for (var sy = top; sy < bottom && sy < height; sy++) {
          for (var sx = left; sx < right && sx < width; sx++) {
            final argb = grid[sy * width + sx];
            if (argb == 0) continue;
            r += (argb >> 16) & 255;
            g += (argb >> 8) & 255;
            b += argb & 255;
            count++;
          }
        }
        output.add(
          count == 0
              ? 0
              : 0xFF000000 |
                    ((r / count).round() << 16) |
                    ((g / count).round() << 8) |
                    (b / count).round(),
        );
      }
    }
    return output;
  }
}
