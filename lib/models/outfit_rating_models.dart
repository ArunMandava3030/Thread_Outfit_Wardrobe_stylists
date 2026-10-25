import 'style_discovery_models.dart';
import 'style_models.dart';
import 'trend_models.dart';

enum RatingTop {
  tee('T-shirt'),
  shirt('Button-up shirt'),
  flannel('Flannel shirt'),
  polo('Polo shirt'),
  knit('Knit top');

  const RatingTop(this.label);
  final String label;

  GarmentType get garmentType => switch (this) {
    tee => GarmentType.tShirt,
    shirt => GarmentType.shirt,
    flannel => GarmentType.flannel,
    polo => GarmentType.polo,
    knit => GarmentType.knit,
  };
}

enum RatingBottom {
  jeans('Jeans'),
  chinos('Chinos'),
  tailored('Tailored trousers'),
  shorts('Shorts'),
  track('Track trousers'),
  riding('Motorcycle trousers');

  const RatingBottom(this.label);
  final String label;

  GarmentType? get garmentType => switch (this) {
    jeans => GarmentType.jeans,
    chinos => GarmentType.chinos,
    tailored => GarmentType.trousers,
    shorts => GarmentType.shorts,
    track => GarmentType.joggers,
    riding => null,
  };
}

enum RatingShoes {
  sneakers('Sneakers'),
  loafers('Loafers'),
  dress('Dress shoes'),
  sandals('Sandals'),
  riding('Motorcycle boots');

  const RatingShoes(this.label);
  final String label;
}

enum RatingLayer {
  none('No layer'),
  overshirt('Overshirt'),
  cardigan('Cardigan'),
  blazer('Blazer'),
  jacket('Casual jacket'),
  riding('Motorcycle jacket');

  const RatingLayer(this.label);
  final String label;
}

enum DressExpectation {
  occasionDefault('Use the occasion'),
  relaxed('Relaxed'),
  smart('Smart casual'),
  formal('Formal dress code');

  const DressExpectation(this.label);
  final String label;
}

enum FitComfort {
  unknown('Not checked'),
  comfortable('Easy to sit and move'),
  restrictive('Pulling or restrictive');

  const FitComfort(this.label);
  final String label;
}

enum TrouserHem {
  unknown('Not checked'),
  clear('Clears the ground'),
  dragging('Dragging on the ground');

  const TrouserHem(this.label);
  final String label;
}

enum SilhouetteFit {
  unknown('Not checked'),
  intended('Matches the fit I want'),
  different('Too loose or tight for my taste');

  const SilhouetteFit(this.label);
  final String label;
}

/// User-confirmed garments and observations, not an automatic photo assessment.
class OutfitRatingInput {
  const OutfitRatingInput({
    required this.topColor,
    required this.pantsColor,
    required this.shoesColor,
    required this.layerColor,
    this.top = RatingTop.shirt,
    this.bottom = RatingBottom.chinos,
    this.shoes = RatingShoes.sneakers,
    this.layer = RatingLayer.none,
    this.occasion = Occasion.casual,
    this.direction = StyleDirection.everyday,
    this.dressExpectation = DressExpectation.occasionDefault,
    this.comfort = FitComfort.unknown,
    this.hem = TrouserHem.unknown,
    this.silhouette = SilhouetteFit.unknown,
    this.includeTrends = false,
    this.topDetails = const GarmentDetails(),
    this.pantsDetails = const GarmentDetails(),
  });

  final ShirtColor topColor, pantsColor, shoesColor, layerColor;
  final RatingTop top;
  final RatingBottom bottom;
  final RatingShoes shoes;
  final RatingLayer layer;
  final Occasion occasion;
  final StyleDirection direction;
  final DressExpectation dressExpectation;
  final FitComfort comfort;
  final TrouserHem hem;
  final SilhouetteFit silhouette;
  final bool includeTrends;
  final GarmentDetails topDetails, pantsDetails;

  bool get hasLayer => layer != RatingLayer.none;
  int get fitObservationCount =>
      (comfort == FitComfort.unknown ? 0 : 1) +
      (hem == TrouserHem.unknown || bottom == RatingBottom.shorts ? 0 : 1) +
      (silhouette == SilhouetteFit.unknown ? 0 : 1);

  OutfitRecommendation toOutfit({
    List<String> reasons = const [],
    String fitAdvice =
        'Check comfort and garment lengths while standing and sitting.',
  }) {
    // IDs depend on actual pieces, not the current score, date or photo filename.
    final signature = [
      occasion.name,
      top.name,
      topColor.argb.toRadixString(16),
      bottom.name,
      pantsColor.argb.toRadixString(16),
      shoes.name,
      shoesColor.argb.toRadixString(16),
      layer.name,
      if (hasLayer) layerColor.argb.toRadixString(16),
      if (topDetails.pattern != GarmentPattern.solid ||
          topDetails.accentColors.isNotEmpty ||
          topDetails.visualProfile != null)
        topDetails.copyWith(type: top.garmentType).signature,
      if (pantsDetails.pattern != GarmentPattern.solid ||
          pantsDetails.accentColors.isNotEmpty ||
          pantsDetails.visualProfile != null)
        pantsDetails.copyWith(type: bottom.garmentType).signature,
    ].join('-');
    return OutfitRecommendation(
      id: 'rated-$signature',
      title: 'My ${occasion.label.toLowerCase()} outfit',
      description:
          '${top.label}, ${bottom.label.toLowerCase()} and ${shoes.label.toLowerCase()}.',
      occasion: occasion,
      shirt: topColor,
      shirtTitle: top.label,
      topDetails: topDetails.copyWith(type: top.garmentType),
      pantsDetails: pantsDetails.copyWith(type: bottom.garmentType),
      pants: OutfitPiece(
        category: 'Pants',
        title: bottom.label,
        colorName: pantsColor.name,
        colorArgb: pantsColor.argb,
      ),
      shoes: OutfitPiece(
        category: 'Shoes',
        title: shoes.label,
        colorName: shoesColor.name,
        colorArgb: shoesColor.argb,
      ),
      layer: OutfitPiece(
        category: 'Layer',
        title: layer.label,
        colorName: hasLayer ? layerColor.name : 'None',
        colorArgb: hasLayer ? layerColor.argb : 0,
      ),
      reasons: reasons,
      fitAdvice: fitAdvice,
      safetyNote: occasion == Occasion.bikeRide
          ? 'A style rating cannot verify motorcycle protection. Wear a certified helmet, jacket, trousers, gloves and over-ankle boots appropriate for your ride.'
          : null,
    );
  }
}

class RatingComponent {
  const RatingComponent(this.label, this.score, this.explanation);
  final String label;
  final double score;
  final String explanation;
}

class OutfitRating {
  const OutfitRating({
    required this.score,
    required this.baseScore,
    required this.preferenceAdjustment,
    required this.trendAdjustment,
    required this.components,
    required this.suggestions,
    required this.profileAdvice,
    required this.preferenceNote,
    required this.trendNote,
    required this.outfit,
    this.trendEvidence,
  });

  final double score, baseScore, preferenceAdjustment, trendAdjustment;
  final List<RatingComponent> components;
  final List<String> suggestions, profileAdvice;
  final String preferenceNote, trendNote;
  final OutfitRecommendation outfit;
  final TrendHeadline? trendEvidence;
}
