import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../models/learning_models.dart';
import '../models/outfit_rating_models.dart';
import '../models/style_discovery_models.dart';
import '../models/style_models.dart';
import '../models/trend_models.dart';
import 'adaptive_stylist.dart';

/// A subjective, explainable style estimate. Physical attributes never affect
/// the numeric score. Preference learning has a bounded, optional influence.
class OutfitRater {
  const OutfitRater();

  OutfitRating rate(
    OutfitRatingInput input, {
    StyleProfile profile = const StyleProfile(),
    bool hasProfile = false,
    List<StyleFeedbackEntry> history = const [],
    TrendSnapshot? trends,
    DateTime? now,
  }) {
    final suggestions = <String>[];
    final colors = _coordination(input, suggestions);
    final occasion = _occasion(input, suggestions);
    final fit = _fit(input, suggestions);
    final components = [colors, occasion, ?fit];
    final base = fit == null
        ? (colors.score * .45 + occasion.score * .4) / .85
        : colors.score * .45 + occasion.score * .4 + fit.score * .15;

    final uniqueVotes = history.map((entry) => entry.outfit.id).toSet().length;
    final preference = uniqueVotes == 0
        ? 0.0
        : (const AdaptiveStylist().preferenceScore(input.toOutfit(), history) -
                  .5) *
              .5 *
              math.min(uniqueVotes / 6, 1);
    final preferenceNote = uniqueVotes == 0
        ? 'No style votes yet. Like or dislike suggested outfits to teach your local preference model.'
        : 'Your local model used explicit outfit votes. Its adjustment is limited to ±0.25 points; it is not a quality prediction.';

    final checkedAt = (now ?? DateTime.now()).toUtc();
    TrendHeadline? evidence;
    String trendNote =
        'Recent headlines are optional and have not affected this rating.';
    if (input.includeTrends) {
      if (trends == null) {
        trendNote =
            'Headlines could not be checked. There is no score penalty.';
      } else if (trends.isStaleAt(checkedAt) ||
          trends.fetchedAt.isAfter(checkedAt.add(const Duration(minutes: 5)))) {
        trendNote =
            'The headline snapshot is out of date. There is no score penalty.';
      } else if (!_matchesDirection(input)) {
        trendNote =
            'The selected garments do not meet the simple matching rules for this style direction. No headline bonus applies, and there is no penalty.';
      } else {
        for (final headline in trends.headlines) {
          final age = checkedAt.difference(headline.publishedAt);
          final available = trends.sources.any(
            (source) => source.name == headline.publisher && source.available,
          );
          if (available &&
              !age.isNegative &&
              age <= const Duration(days: 30) &&
              isTrendSource(headline.url, headline.publisher) &&
              headline.suggestedDirection == input.direction) {
            evidence = headline;
            break;
          }
        }
        trendNote = evidence == null
            ? 'No recent headline keyword matched your selected style. There is no score penalty.'
            : 'A recent headline mentions your selected style, and your garment categories fit its basic matching rules: +0.10. This does not measure popularity or recognize the featured look.';
      }
    }
    final trendBoost = evidence == null ? 0.0 : .1;
    final profileAdvice = _profileAdvice(input, profile, hasProfile);
    if (fit == null) {
      suggestions.add(
        'Add the optional fit observations to include comfort, hem clearance and your preferred silhouette. Fit is currently unscored.',
      );
    }
    if (suggestions.isEmpty) {
      suggestions.add(
        'The selected pieces make a coherent starting point. Check the venue dress code, weather and how the outfit feels when you move.',
      );
    }
    final score = (base + preference + trendBoost).clamp(0.0, 5.0);
    return OutfitRating(
      score: score,
      baseScore: base,
      preferenceAdjustment: preference,
      trendAdjustment: trendBoost,
      components: List.unmodifiable(components),
      suggestions: List.unmodifiable(suggestions),
      profileAdvice: List.unmodifiable(profileAdvice),
      preferenceNote: preferenceNote,
      trendNote: trendNote,
      trendEvidence: evidence,
      outfit: input.toOutfit(
        reasons: [
          for (final component in components) component.explanation,
          ...suggestions,
        ],
        fitAdvice: profileAdvice.join(' '),
      ),
    );
  }

  bool _matchesDirection(OutfitRatingInput input) {
    if (input.occasion == Occasion.bikeRide ||
        input.bottom == RatingBottom.riding ||
        input.shoes == RatingShoes.riding ||
        input.layer == RatingLayer.riding) {
      return false;
    }
    return switch (input.direction) {
      StyleDirection.everyday =>
        {
              RatingBottom.jeans,
              RatingBottom.chinos,
              RatingBottom.shorts,
            }.contains(input.bottom) &&
            input.shoes != RatingShoes.dress &&
            input.layer != RatingLayer.blazer,
      StyleDirection.smartCasual =>
        {
              RatingBottom.chinos,
              RatingBottom.tailored,
              RatingBottom.jeans,
            }.contains(input.bottom) &&
            input.shoes != RatingShoes.sandals &&
            (input.top != RatingTop.tee ||
                input.layer == RatingLayer.blazer ||
                input.layer == RatingLayer.overshirt),
      StyleDirection.streetwear =>
        {RatingBottom.jeans, RatingBottom.track}.contains(input.bottom) &&
            input.shoes == RatingShoes.sneakers &&
            {RatingTop.tee, RatingTop.knit}.contains(input.top) &&
            {
              RatingLayer.none,
              RatingLayer.overshirt,
              RatingLayer.jacket,
            }.contains(input.layer),
      StyleDirection.athleisure =>
        input.bottom == RatingBottom.track &&
            input.shoes == RatingShoes.sneakers &&
            input.top != RatingTop.shirt &&
            input.top != RatingTop.flannel &&
            {RatingLayer.none, RatingLayer.jacket}.contains(input.layer),
      StyleDirection.preppy =>
        {
              RatingBottom.chinos,
              RatingBottom.tailored,
              RatingBottom.shorts,
            }.contains(input.bottom) &&
            {RatingShoes.loafers, RatingShoes.sneakers}.contains(input.shoes) &&
            input.top != RatingTop.tee &&
            {
              RatingLayer.none,
              RatingLayer.cardigan,
              RatingLayer.blazer,
            }.contains(input.layer),
    };
  }

  RatingComponent _coordination(
    OutfitRatingInput input,
    List<String> suggestions,
  ) {
    final palette = [
      input.topColor.argb,
      input.pantsColor.argb,
      input.shoesColor.argb,
      if (input.hasLayer) input.layerColor.argb,
    ];
    final hsv = palette
        .map((color) => HSVColor.fromColor(Color(color)))
        .toList();
    final accents = hsv
        .where((color) => color.saturation > .48 && color.value > .35)
        .length;
    var score = 4.4;
    if (accents >= 3) {
      score -= .9;
      suggestions.add(
        'For a calmer palette, keep one or two bold pieces and try neutral shoes or a neutral layer. Multiple accents can also be an intentional choice.',
      );
    }
    final top = hsv[0], bottom = hsv[1];
    final distance = (top.hue - bottom.hue).abs();
    final hueDistance = math.min(distance, 360 - distance);
    final neutral =
        top.saturation < .24 ||
        bottom.saturation < .24 ||
        top.value < .25 ||
        bottom.value < .25;
    if (!neutral &&
        top.saturation > .48 &&
        bottom.saturation > .48 &&
        hueDistance > 55 &&
        hueDistance < 125) {
      score -= .45;
      suggestions.add(
        'The top and trousers create a bold color contrast. A neutral layer or shoes can connect them if you want a quieter look.',
      );
    }
    if (accents <= 1) score += .15;
    final patternedTop =
        input.topDetails.pattern != GarmentPattern.solid ||
        input.topDetails.accentColors.isNotEmpty;
    final patternedPants =
        input.pantsDetails.pattern != GarmentPattern.solid ||
        input.pantsDetails.accentColors.isNotEmpty;
    final measured =
        input.topDetails.measuredVisual != null ||
        input.pantsDetails.measuredVisual != null;
    if (measured) {
      double weight(GarmentDetails details, bool patterned) =>
          details.measuredVisual != null
          ? details.visualIntensity
          : patterned
          ? .5
          : 0;
      final topWeight = weight(input.topDetails, patternedTop);
      final bottomWeight = weight(input.pantsDetails, patternedPants);
      final balanceAdjustment = .8 * topWeight * bottomWeight;
      score -= balanceAdjustment;
      if (topWeight > .15 && bottomWeight > .15) {
        suggestions.add(
          'Both pieces carry visible detail. The balance adjustment scales with measured contrast, detail density, directionality and regularity; try a quieter companion if you want the more detailed garment to lead. Mixing detail remains a style choice.',
        );
      }
      final dominantDetails = topWeight >= bottomWeight
          ? input.topDetails
          : input.pantsDetails;
      final otherColor = topWeight >= bottomWeight
          ? input.pantsColor
          : input.topColor;
      final otherWeight = math.min(topWeight, bottomWeight);
      final visual = dominantDetails.measuredVisual;
      if (visual != null && otherWeight < .35) {
        var echoedShare = 0.0;
        for (final entry in visual.palette) {
          if (_similarColor(entry.color.argb, otherColor.argb)) {
            echoedShare += entry.share;
          }
        }
        score += .15 * math.sqrt(echoedShare.clamp(0.0, 1.0));
        suggestions.add(
          echoedShare > 0
              ? 'The quieter piece repeats a color covering about ${(echoedShare * 100).round()}% of the sampled garment area. This links the palette without needing to name the pattern.'
              : 'A quiet neutral or one of the larger colors in the sampled palette can balance this garment. The scan describes visible detail, not a named pattern.',
        );
        suggestions.add(visual.stylingDescription);
      }
    } else if (patternedTop && patternedPants) {
      score -= .35;
      suggestions.add(
        'Both the top and pants have patterns or multiple colors. For an easier pairing, make one piece solid; if you enjoy mixing patterns, vary their scale and repeat a shared color.',
      );
    } else if (patternedTop || patternedPants) {
      final details = patternedTop ? input.topDetails : input.pantsDetails;
      final otherColor = patternedTop ? input.pantsColor : input.topColor;
      final design = details.pattern == GarmentPattern.solid
          ? 'palette'
          : 'pattern';
      final sharesAccent = details.accentColors.any(
        (color) => _similarColor(color.argb, otherColor.argb),
      );
      if (sharesAccent) {
        score += .15;
        suggestions.add(
          'Your solid ${patternedTop ? 'pants' : 'top'} repeats a color from the $design, which helps connect the outfit. Keep extra layers simple.',
        );
      } else {
        suggestions.add(
          details.accentColors.isEmpty
              ? 'Keep the ${patternedTop ? 'pants' : 'top'} solid so the pattern stands out. Add its other colors in Edit for a more specific palette check.'
              : 'For another combination, try solid ${patternedTop ? 'pants' : 'tops'} in ${details.accentColors.map((color) => color.name.toLowerCase()).join(' or ')} to repeat a color from the $design.',
        );
      }
    }
    return RatingComponent(
      measured
          ? 'Color and visual balance'
          : patternedTop || patternedPants
          ? 'Color and pattern coordination'
          : 'Color coordination',
      score.clamp(0.0, 5.0),
      measured
          ? 'Visual balance uses the sampled palette shares and continuous detail measurements. Two visually detailed pieces have a proportional balance adjustment of up to 0.8 here; a palette echo with a quieter piece adds up to 0.15. This is a styling heuristic, not pattern recognition.'
          : patternedTop || patternedPants
          ? 'Palette balance uses the main colors and confirmed accents. A shared accent with a solid piece adds 0.15 here; two patterned or multicolor pieces subtract 0.35 for visual complexity. Pattern mixing can be intentional.'
          : 'Palette balance is estimated from the selected garment colors, with room for intentional bold combinations.',
    );
  }

  bool _similarColor(int left, int right) {
    if (left == right) return true;
    final a = HSVColor.fromColor(Color(left));
    final b = HSVColor.fromColor(Color(right));
    final distance = (a.hue - b.hue).abs();
    final hueDistance = math.min(distance, 360 - distance);
    return (a.value - b.value).abs() < .18 &&
        (a.saturation - b.saturation).abs() < .20 &&
        ((a.saturation < .18 && b.saturation < .18) || hueDistance < 18);
  }

  RatingComponent _occasion(OutfitRatingInput input, List<String> suggestions) {
    if (input.occasion == Occasion.bikeRide) {
      final hasGear =
          input.bottom == RatingBottom.riding &&
          input.shoes == RatingShoes.riding &&
          input.layer == RatingLayer.riding;
      suggestions.add(
        'For a motorcycle ride, verify certified protective gear, helmet and gloves separately. Color or a high style score cannot confirm protection.',
      );
      return RatingComponent(
        'Occasion readiness',
        hasGear ? 4.3 : 1.3,
        hasGear
            ? 'Motorcycle garment categories are selected, but their protection has not been verified.'
            : 'The selected pieces do not include the main motorcycle garment categories.',
      );
    }
    final expectation =
        input.dressExpectation == DressExpectation.occasionDefault
        ? switch (input.occasion) {
            Occasion.office ||
            Occasion.date ||
            Occasion.party => DressExpectation.smart,
            Occasion.special => DressExpectation.formal,
            _ => DressExpectation.relaxed,
          }
        : input.dressExpectation;
    var score = 4.4;
    if (expectation == DressExpectation.formal) {
      if (input.top != RatingTop.shirt) {
        score -= .7;
        suggestions.add(
          'For the selected formal dress code, try a button-up shirt.',
        );
      }
      if (input.bottom != RatingBottom.tailored) {
        score -= .8;
        suggestions.add(
          'Tailored trousers are a stronger starting point for the selected formal dress code.',
        );
      }
      if (input.shoes != RatingShoes.dress &&
          input.shoes != RatingShoes.loafers) {
        score -= .7;
        suggestions.add(
          'Swap to dress shoes or polished loafers if the invitation calls for formal clothing.',
        );
      }
      if (input.layer != RatingLayer.blazer) {
        score -= .4;
        suggestions.add(
          'Consider a coordinated blazer for a formal event; check whether the invitation requires a suit or black tie.',
        );
      }
    } else if (expectation == DressExpectation.smart) {
      if (input.bottom == RatingBottom.shorts ||
          input.bottom == RatingBottom.track) {
        score -= .8;
        suggestions.add(
          'Chinos or tailored trousers can make this outfit feel more dressed up for ${input.occasion.label.toLowerCase()}.',
        );
      }
      if (input.shoes == RatingShoes.sandals) {
        score -= .6;
        suggestions.add(
          'Try closed shoes for this smart-casual setting, unless the venue is explicitly relaxed.',
        );
      }
      if (input.top == RatingTop.tee && !input.hasLayer) {
        score -= .25;
        suggestions.add(
          'A lightweight overshirt or unstructured blazer can dress up your T-shirt.',
        );
      }
      if (input.top == RatingTop.flannel) {
        suggestions.add(
          'A flannel shirt reads relaxed. Keep the pants and shoes neat for smart casual; use a lighter button-up if the venue expects a dressier look.',
        );
      }
      if ((input.occasion == Occasion.date ||
              input.occasion == Occasion.party) &&
          !input.hasLayer) {
        suggestions.add(
          'For an evening ${input.occasion == Occasion.date ? 'date' : 'party'}, an open overshirt or light blazer is an optional finishing layer. Skip it if it is warm.',
        );
      }
    } else if (input.occasion == Occasion.beach &&
        (input.layer == RatingLayer.blazer ||
            input.layer == RatingLayer.riding)) {
      score -= .5;
      suggestions.add(
        'For beach comfort, try a breathable overshirt or skip the heavy layer; dress for the actual weather.',
      );
    }
    return RatingComponent(
      'Occasion readiness',
      score.clamp(0.0, 5.0),
      'Garment categories are compared with ${expectation.label.toLowerCase()} expectations. Your venue and invitation take priority.',
    );
  }

  RatingComponent? _fit(OutfitRatingInput input, List<String> suggestions) {
    if (input.fitObservationCount == 0) return null;
    final scores = <double>[];
    if (input.comfort != FitComfort.unknown) {
      scores.add(input.comfort == FitComfort.comfortable ? 4.7 : 2);
      if (input.comfort == FitComfort.restrictive) {
        suggestions.add(
          'Try a different cut or size where fabric pulls, then check sitting, reaching and walking again.',
        );
      }
    }
    if (input.hem != TrouserHem.unknown &&
        input.bottom != RatingBottom.shorts) {
      scores.add(input.hem == TrouserHem.clear ? 4.7 : 2);
      if (input.hem == TrouserHem.dragging) {
        suggestions.add(
          'Shorten or cuff the trouser hem so it clears the ground in these shoes.',
        );
      }
    }
    if (input.silhouette != SilhouetteFit.unknown) {
      scores.add(input.silhouette == SilhouetteFit.intended ? 4.7 : 2.7);
      if (input.silhouette == SilhouetteFit.different) {
        suggestions.add(
          'Choose a cut closer to your preferred silhouette. Relaxed and fitted shapes can both work when intentional and comfortable.',
        );
      }
    }
    return RatingComponent(
      'Observed fit',
      scores.reduce((a, b) => a + b) / scores.length,
      'Only your ${scores.length} reported fit ${scores.length == 1 ? 'observation is' : 'observations are'} scored; measurements alone cannot establish fit.',
    );
  }

  List<String> _profileAdvice(
    OutfitRatingInput input,
    StyleProfile profile,
    bool hasProfile,
  ) {
    if (!hasProfile) {
      return [
        'Add your optional profile for height, shoulder proportion and palette suggestions. The outfit score does not require a profile.',
      ];
    }
    final advice = <String>[];
    if (profile.heightCm.isFinite &&
        profile.heightCm >= 100 &&
        profile.heightCm <= 250) {
      advice.add(
        'At your saved height of ${profile.heightCm.round()} cm, use the actual garment length and your inseam to choose a hem. Height alone cannot tell whether trousers fit.',
      );
    }
    final bodyAdvice = switch (profile.bodyShape) {
      BodyShape.broadShoulders =>
        'With your saved broader-shoulder proportions, check shoulder and upper-arm ease first; try a straighter trouser cut if you want a more even silhouette.',
      BodyShape.widerHips =>
        'With your saved wider-hip proportions, check ease through the seat and thighs; an open structured layer is an optional way to define the upper outline.',
      BodyShape.fullerMidsection =>
        'With your saved fuller-midsection proportions, check comfortable button and waist ease while sitting; an open overshirt can create the relaxed line you may prefer.',
      BodyShape.balanced =>
        'With your saved balanced proportions, choose the silhouette you enjoy and check shoulder seams, seat ease and hem length on the actual garments.',
      null => null,
    };
    if (bodyAdvice != null) advice.add(bodyAdvice);
    if (profile.useSkinTone && profile.skinToneArgb != null) {
      final contrast =
          (Color(profile.skinToneArgb!).computeLuminance() -
                  Color(input.topColor.argb).computeLuminance())
              .abs();
      advice.add(
        contrast < .12
            ? 'Your selected top and saved skin swatch have similar lightness. If you want more contrast near your face, try a lighter or darker collar or layer. Either palette is a personal choice.'
            : 'Your selected top creates lightness contrast with your saved skin swatch. Check the colors together in daylight because a photo swatch can shift with lighting.',
      );
      if (profile.undertone == Undertone.warm) {
        advice.add(
          'Your chosen warm undertone can be a prompt to try cream, olive or rust near the face, if you like those colors.',
        );
      }
      if (profile.undertone == Undertone.cool) {
        advice.add(
          'Your chosen cool undertone can be a prompt to try navy, blue or burgundy near the face, if you like those colors.',
        );
      }
    }
    advice.add(
      'Skin tone, body proportions and height guide optional suggestions and never lower your score.',
    );
    return advice;
  }
}
