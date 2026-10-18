import 'dart:math' as math;

import '../models/style_models.dart';
import '../models/wardrobe_models.dart';

/// Finds nearby wardrobe colors without changing any garment, occasion, weather
/// or protection requirements. A color match does not establish garment fit.
class WardrobeStylist {
  const WardrobeStylist();

  /// Number of pants, shoes and optional layer colors found in the wardrobe.
  int coverage(OutfitRecommendation outfit, List<WardrobeItem> items) =>
      matchesFor(outfit, items).length;

  Map<WardrobeCategory, WardrobeItem> matchesFor(
    OutfitRecommendation outfit,
    List<WardrobeItem> items,
  ) {
    // A typed item name/color cannot certify motorcycle protection. Never count
    // fashion items as ownership of required riding equipment.
    if (outfit.occasion == Occasion.bikeRide) return const {};
    final pieces = <WardrobeCategory, OutfitPiece>{
      WardrobeCategory.pants: outfit.pants,
      WardrobeCategory.shoes: outfit.shoes,
      if (outfit.layer.colorArgb != 0) WardrobeCategory.layer: outfit.layer,
    };
    final matches = <WardrobeCategory, WardrobeItem>{};
    for (final entry in pieces.entries) {
      final target = _lab(entry.value.colorArgb);
      var closest = 12.0;
      for (final item in items) {
        if (item.category != entry.key) continue;
        final lab = _lab(item.colorArgb);
        final delta = math.sqrt(
          math.pow(target.$1 - lab.$1, 2) +
              math.pow(target.$2 - lab.$2, 2) +
              math.pow(target.$3 - lab.$3, 2),
        );
        if (delta < closest) {
          closest = delta;
          matches[entry.key] = item;
        }
      }
    }
    return Map.unmodifiable(matches);
  }

  /// Stable ranking: equal color coverage keeps the existing adaptive ordering.
  /// Objects themselves are untouched, including reasons and safety guidance.
  List<OutfitRecommendation> rankByOwnership(
    List<OutfitRecommendation> candidates,
    List<WardrobeItem> items,
  ) {
    final scored =
        candidates.indexed
            .map(
              (entry) => (
                index: entry.$1,
                outfit: entry.$2,
                matches: coverage(entry.$2, items),
              ),
            )
            .toList()
          ..sort((a, b) {
            final score = b.matches.compareTo(a.matches);
            return score == 0 ? a.index.compareTo(b.index) : score;
          });
    return List.unmodifiable(scored.map((entry) => entry.outfit));
  }
}

// sRGB -> CIE Lab (D65). Delta E 1976 keeps nearby shades together while avoiding
// an RGB threshold that treats every channel as equally perceptible.
(double, double, double) _lab(int argb) {
  double linear(int channel) {
    final value = channel / 255;
    return value <= .04045
        ? value / 12.92
        : math.pow((value + .055) / 1.055, 2.4).toDouble();
  }

  final red = linear((argb >> 16) & 255);
  final green = linear((argb >> 8) & 255);
  final blue = linear(argb & 255);
  final x = (red * .4124564 + green * .3575761 + blue * .1804375) / .95047;
  final y = red * .2126729 + green * .7151522 + blue * .0721750;
  final z = (red * .0193339 + green * .1191920 + blue * .9503041) / 1.08883;
  double transform(double value) => value > 216 / 24389
      ? math.pow(value, 1 / 3).toDouble()
      : (24389 / 27 * value + 16) / 116;
  final fx = transform(x), fy = transform(y), fz = transform(z);
  return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}
