import 'dart:math' as math;
import 'dart:typed_data';

import '../models/style_models.dart';

/// The user's confirmed, approximate observations from one photograph.
class PhotoAnalysisResult {
  const PhotoAnalysisResult({
    this.shirtColor,
    this.skinToneArgb,
    this.bodyShape,
    this.garmentPalette = const [],
  });

  final ShirtColor? shirtColor;
  final int? skinToneArgb;
  final BodyShape? bodyShape;

  /// Only populated after the user deliberately selects a garment region.
  /// The confirmed main colour comes first; no fabric/pattern is inferred.
  final List<ShirtColor> garmentPalette;
}

/// Local image helpers. These do not detect a person or infer measurements.
class PhotoAnalyzer {
  const PhotoAnalyzer._();

  /// Maps a tap through a centred, contain-fit image, excluding letterboxing.
  static ({int x, int y})? pixelAtContainedPosition({
    required double localX,
    required double localY,
    required double viewportWidth,
    required double viewportHeight,
    required int imageWidth,
    required int imageHeight,
  }) {
    if (![
          localX,
          localY,
          viewportWidth,
          viewportHeight,
        ].every((value) => value.isFinite) ||
        viewportWidth <= 0 ||
        viewportHeight <= 0 ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      return null;
    }
    final scale = math.min(
      viewportWidth / imageWidth,
      viewportHeight / imageHeight,
    );
    final left = (viewportWidth - imageWidth * scale) / 2;
    final top = (viewportHeight - imageHeight * scale) / 2;
    final x = (localX - left) / scale;
    final y = (localY - top) / scale;
    if (x < 0 || y < 0 || x >= imageWidth || y >= imageHeight) return null;
    return (x: x.floor(), y: y.floor());
  }

  /// Samples an opaque patch around [x], [y], ignoring transparent pixels.
  ///
  /// A channel median makes isolated highlights less influential. Coordinates
  /// outside the image, malformed buffers and empty patches return null.
  static int? sampleRgba({
    required Uint8List rgba,
    required int width,
    required int height,
    required int x,
    required int y,
    int radius = 4,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        rgba.length < width * height * 4 ||
        x < 0 ||
        y < 0 ||
        x >= width ||
        y >= height ||
        radius < 0) {
      return null;
    }
    final red = <int>[];
    final green = <int>[];
    final blue = <int>[];
    final left = math.max(0, x - radius);
    final right = math.min(width - 1, x + radius);
    final top = math.max(0, y - radius);
    final bottom = math.min(height - 1, y + radius);
    for (var row = top; row <= bottom; row++) {
      for (var column = left; column <= right; column++) {
        final index = (row * width + column) * 4;
        if (rgba[index + 3] < 128) continue;
        red.add(rgba[index]);
        green.add(rgba[index + 1]);
        blue.add(rgba[index + 2]);
      }
    }
    if (red.isEmpty) return null;
    red.sort();
    green.sort();
    blue.sort();
    final middle = red.length ~/ 2;
    return 0xFF000000 |
        (red[middle] << 16) |
        (green[middle] << 8) |
        blue[middle];
  }

  /// Labels a sampled colour without replacing its actual RGB values.
  static ShirtColor shirtColorFor(int argb) {
    var best = ShirtColor.presets.first;
    var bestDistance = double.infinity;
    for (final candidate in ShirtColor.presets) {
      final distance = _colorDistance(argb, candidate.argb);
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return ShirtColor(name: best.name, argb: argb);
  }

  static double _colorDistance(int first, int second) {
    final redA = (first >> 16) & 255;
    final redB = (second >> 16) & 255;
    final red = redA - redB;
    final green = ((first >> 8) & 255) - ((second >> 8) & 255);
    final blue = (first & 255) - (second & 255);
    final redMean = (redA + redB) / 2;
    return (2 + redMean / 256) * red * red +
        4 * green * green +
        (2 + (255 - redMean) / 256) * blue * blue;
  }

  /// Returns a broad styling guide from three user-marked relative widths.
  ///
  /// Widths must use the same units and require a straight-on photograph.
  /// This cannot determine anatomical measurements or health information.
  static BodyShape? classifyProportions({
    required double shoulderWidth,
    required double waistWidth,
    required double hipWidth,
  }) {
    final widths = [shoulderWidth, waistWidth, hipWidth];
    if (widths.any((width) => !width.isFinite || width <= 0)) return null;
    if (waistWidth > math.max(shoulderWidth, hipWidth) * 1.04) {
      return BodyShape.fullerMidsection;
    }
    if (shoulderWidth > hipWidth * 1.08) {
      return BodyShape.broadShoulders;
    }
    if (hipWidth > shoulderWidth * 1.08) return BodyShape.widerHips;
    return BodyShape.balanced;
  }
}
