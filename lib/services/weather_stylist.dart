import '../models/style_models.dart';
import '../models/weather_models.dart';

/// Weather adjusts fabrics and footwear within the selected occasion. These
/// are transparent styling rules; preference learning is handled separately.
class WeatherStylist {
  const WeatherStylist();

  List<OutfitRecommendation> adapt(
    List<OutfitRecommendation> outfits,
    WeatherSnapshot weather, {
    required bool includeLayer,
  }) {
    if (weather.isStale) return outfits;
    final feelsLike = weather.apparentTemperatureC;
    final cold = feelsLike <= 16;
    final veryCold = feelsLike <= 8;
    final warm = feelsLike >= 27;
    final windy = weather.windKmh >= 25;
    final wet =
        weather.precipitationMm > 0 ||
        const {
          51,
          53,
          55,
          56,
          57,
          61,
          63,
          65,
          66,
          67,
          71,
          73,
          75,
          77,
          80,
          81,
          82,
          85,
          86,
          95,
          96,
          99,
        }.contains(weather.weatherCode);
    if (!cold && !warm && !windy && !wet) return outfits;

    return List.unmodifiable(
      outfits.map((outfit) {
        if (outfit.occasion == Occasion.bikeRide) {
          final advice = <String>[
            if (wet)
              'Wet weather: choose weather protection designed to work with your certified riding gear.',
            if (cold)
              'Cool conditions: consider a compatible thermal liner while keeping the riding armor correctly fitted.',
            if (warm)
              'Warm conditions: consider ventilation options within certified motorcycle gear.',
            if (windy)
              'Windy conditions: check local conditions before setting out.',
          ];
          return _copy(
            outfit,
            description: '${outfit.description} ${advice.join(' ')}',
            reasons: [...outfit.reasons, ...advice],
          );
        }

        var pants = outfit.pants;
        var shoes = outfit.shoes;
        var layer = includeLayer ? outfit.layer : _noLayer;
        final polished =
            outfit.occasion == Occasion.office ||
            outfit.occasion == Occasion.date ||
            outfit.occasion == Occasion.party ||
            outfit.occasion == Occasion.special;
        final notes = <String>[];
        if (wet) {
          pants = _rename(
            pants,
            polished
                ? 'Quick-drying tailored trousers'
                : 'Quick-drying relaxed trousers',
          );
          shoes = _rename(
            shoes,
            polished
                ? 'Water-resistant leather derbies'
                : 'Water-resistant closed shoes',
          );
          if (includeLayer) {
            layer = _layer(
              outfit,
              veryCold
                  ? 'Insulated weather-resistant coat'
                  : 'Lightweight rain shell',
            );
          }
          notes.add(
            'Wet conditions favor quick-drying trousers and closed, water-resistant shoes; leave suede and absorbent canvas for a dry day.',
          );
          if (cold) {
            notes.add(
              'It feels cool outside; add warmth underneath your outerwear.',
            );
          }
        } else if (cold) {
          pants = _rename(
            pants,
            polished
                ? 'Wool-blend tailored trousers'
                : 'Heavier straight-leg trousers',
          );
          shoes = _rename(
            shoes,
            polished ? 'Leather ankle boots' : 'Closed leather boots',
          );
          if (includeLayer) {
            layer = _layer(
              outfit,
              polished
                  ? 'Wool-blend coat'
                  : (veryCold ? 'Insulated jacket' : 'Warm overshirt'),
            );
          }
          notes.add(
            'Cool conditions favor heavier trousers and closed shoes; adjust the amount of warmth to how you feel.',
          );
        } else if (warm) {
          final shorts = outfit.pants.title.toLowerCase().contains('shorts');
          pants = _rename(
            pants,
            polished
                ? 'Breathable cotton-linen trousers'
                : (shorts
                      ? 'Breathable cotton shorts'
                      : 'Relaxed linen-blend trousers'),
          );
          if (includeLayer) {
            layer = _layer(
              outfit,
              polished ? 'Airy unlined blazer' : 'Lightweight linen overshirt',
            );
          }
          notes.add(
            'Warm conditions favor breathable fabric and an airy fit; keep any optional layer light.',
          );
        }
        if (windy && !wet && includeLayer) {
          layer = _layer(
            outfit,
            cold
                ? 'Warm wind-resistant coat'
                : 'Lightweight wind-resistant jacket',
          );
          notes.add('The breeze favors an outer layer that blocks some wind.');
        }
        if (!includeLayer && (cold || wet || windy)) {
          notes.add(
            'Optional layers are off. Consider bringing ${wet
                ? 'a rain layer'
                : cold
                ? 'a warm layer'
                : 'a wind layer'} if you will be outdoors.',
          );
        }

        if (outfit.startingPiece == StartingPiece.pants) {
          pants = outfit.pants;
          notes.add(
            'Your pants stay as selected. Check whether their fabric is comfortable for these conditions; weather tips are options to consider, not a change to the item you are wearing.',
          );
        }

        if (outfit.pantsDetails.type != null &&
            outfit.startingPiece != StartingPiece.pants) {
          // Keep the garment category selected around the anchor (e.g. jeans
          // beside flannel); weather adds fabric advice and outer protection.
          pants = outfit.pants;
          notes.add(
            'Keep this ${outfit.pantsDetails.type!.label.toLowerCase()} option if its fabric suits the weather; check warmth and drying time before heading out.',
          );
        }
        final quietLayer =
            outfit.topDetails.needsQuietLayer ||
            outfit.pantsDetails.needsQuietLayer;
        if (quietLayer &&
            layer.colorArgb != 0 &&
            !layer.title.toLowerCase().startsWith('plain ')) {
          layer = _rename(
            layer,
            'Plain ${layer.title.replaceAll(RegExp(r'[Tt]extured ?'), '').toLowerCase()}',
          );
        }

        final context = wet
            ? 'wet'
            : cold
            ? 'cool'
            : warm
            ? 'warm'
            : 'breezy';
        final reasons = outfit.reasons
            .where(
              (reason) =>
                  !reason.startsWith('A ') ||
                  !reason.contains('layer connects the palette'),
            )
            .where(
              (reason) =>
                  !(reason.startsWith('Light fabrics and ') && (wet || cold)),
            )
            .toList();
        // Preserve palette, profile and occasion explanations while replacing
        // statements that described the layer or warm beach fabrics we changed.
        reasons.addAll(notes);
        return _copy(
          outfit,
          pants: pants,
          shoes: shoes,
          layer: layer,
          description:
              'Adapted for $context conditions while keeping your ${outfit.occasion.label.toLowerCase()} palette.',
          reasons: reasons,
          fitAdvice: cold || wet
              ? outfit.fitAdvice.replaceAll(
                  'Choose breathable fabric and enough ease for warm weather.',
                  'Leave room for comfortable movement and any additional warmth.',
                )
              : outfit.fitAdvice,
        );
      }),
    );
  }
}

const _noLayer = OutfitPiece(
  category: 'Layer',
  title: 'Skip the layer',
  colorName: 'None',
  colorArgb: 0,
);

OutfitPiece _rename(OutfitPiece original, String title) => OutfitPiece(
  category: original.category,
  title: title,
  colorName: original.colorName,
  colorArgb: original.colorArgb,
);

OutfitPiece _layer(OutfitRecommendation outfit, String title) => OutfitPiece(
  category: 'Layer',
  title: title,
  colorName: outfit.layer.colorArgb == 0 ? 'Navy' : outfit.layer.colorName,
  colorArgb: outfit.layer.colorArgb == 0 ? 0xFF293B50 : outfit.layer.colorArgb,
);

OutfitRecommendation _copy(
  OutfitRecommendation original, {
  OutfitPiece? pants,
  OutfitPiece? shoes,
  OutfitPiece? layer,
  required String description,
  required List<String> reasons,
  String? fitAdvice,
}) {
  final newPants = pants ?? original.pants;
  final newShoes = shoes ?? original.shoes;
  final newLayer = layer ?? original.layer;
  final changed =
      newPants.title != original.pants.title ||
      newShoes.title != original.shoes.title ||
      newLayer.title != original.layer.title ||
      newLayer.colorArgb != original.layer.colorArgb;
  final signature = [
    newPants,
    newShoes,
    newLayer,
  ].map((piece) => '${piece.title}:${piece.colorArgb}').join('|');
  // A deterministic signature avoids saved-outfit collisions between different
  // weather garments, without creating a new identity on every weather refresh.
  final suffix = Uri.encodeComponent(signature);
  return OutfitRecommendation(
    id: changed ? '${original.id}-weather-$suffix' : original.id,
    title: original.title,
    description: description,
    occasion: original.occasion,
    shirt: original.shirt,
    shirtTitle: original.shirtTitle,
    startingPiece: original.startingPiece,
    topDetails: original.topDetails,
    pantsDetails: original.pantsDetails,
    pants: newPants,
    shoes: newShoes,
    layer: newLayer,
    reasons: List.unmodifiable(reasons),
    fitAdvice: fitAdvice ?? original.fitAdvice,
    safetyNote: original.safetyNote,
  );
}
