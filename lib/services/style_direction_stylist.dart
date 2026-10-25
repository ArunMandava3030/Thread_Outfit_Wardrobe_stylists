import '../models/style_discovery_models.dart';
import '../models/style_models.dart';

class StyleDirectionStylist {
  const StyleDirectionStylist();

  List<OutfitRecommendation> adapt(
    List<OutfitRecommendation> outfits,
    StyleDirection direction,
  ) {
    if (direction == StyleDirection.everyday) return outfits;
    return List.unmodifiable(
      outfits.map((outfit) {
        if (outfit.occasion == Occasion.bikeRide) {
          return _rebuild(
            outfit,
            direction,
            reason:
                '${direction.label} is a styling preference; certified motorcycle gear remains the priority for this occasion.',
          );
        }
        final recipe = _recipe(direction, outfit.occasion);
        final hasLayer = outfit.layer.colorArgb != 0;
        final garmentAware =
            outfit.topDetails.isSpecified || outfit.pantsDetails.isSpecified;
        final quietLayer =
            outfit.topDetails.needsQuietLayer ||
            outfit.pantsDetails.needsQuietLayer;
        final layerTitle = quietLayer
            ? 'Plain ${recipe.$3.replaceAll(RegExp(r'[Tt]extured ?'), '').toLowerCase()}'
            : outfit.topDetails.measuredVisual != null ||
                  outfit.pantsDetails.measuredVisual != null
            ? outfit.layer.title
            : recipe.$3;
        return _rebuild(
          outfit,
          direction,
          pants: outfit.startingPiece == StartingPiece.pants || garmentAware
              ? outfit.pants
              : _rename(outfit.pants, recipe.$1),
          shirtTitle:
              outfit.startingPiece == StartingPiece.pants && !garmentAware
              ? _topRecipe(direction, outfit.occasion)
              : outfit.shirtTitle,
          shoes: _rename(outfit.shoes, recipe.$2),
          layer: hasLayer ? _rename(outfit.layer, layerTitle) : outfit.layer,
          reason:
              (outfit.occasion == Occasion.office ||
                      outfit.occasion == Occasion.special) &&
                  (direction == StyleDirection.streetwear ||
                      direction == StyleDirection.athleisure)
              ? '${direction.label} is softened with tailored pieces and closed shoes; follow the dress code for your ${outfit.occasion.label.toLowerCase()}.'
              : '${direction.label} shapes the finishing pieces while your ${outfit.startingPiece.itemLabel.toLowerCase()}, chosen colors and ${outfit.occasion.label.toLowerCase()} plans stay the starting point.',
        );
      }),
    );
  }
}

(String, String, String) _recipe(StyleDirection direction, Occasion occasion) {
  final office = occasion == Occasion.office || occasion == Occasion.special;
  final beach = occasion == Occasion.beach;
  final celebration =
      occasion == Occasion.party || occasion == Occasion.special;
  return switch (direction) {
    StyleDirection.everyday => (
      'Straight-leg chinos',
      'Everyday sneakers',
      'Cotton overshirt',
    ),
    StyleDirection.smartCasual =>
      beach
          ? ('Linen trousers', 'Canvas slip-ons', 'Open linen shirt')
          : celebration
          ? (
              'Tailored dress trousers',
              'Leather loafers',
              'Textured tailored blazer',
            )
          : ('Straight-leg chinos', 'Leather loafers', 'Unstructured blazer'),
    StyleDirection.streetwear =>
      office
          ? (
              'Relaxed tailored trousers',
              'Minimal leather sneakers',
              occasion == Occasion.special
                  ? 'Softly structured blazer'
                  : 'Structured overshirt',
            )
          : beach
          ? (
              'Relaxed cotton shorts',
              'Canvas slip-ons',
              'Lightweight cotton overshirt',
            )
          : occasion == Occasion.party
          ? (
              'Relaxed tailored trousers',
              'Minimal leather sneakers',
              'Textured bomber',
            )
          : ('Relaxed cargo trousers', 'Low-top sneakers', 'Relaxed overshirt'),
    StyleDirection.athleisure =>
      office
          ? (
              'Tailored stretch trousers',
              'Minimal leather sneakers',
              'Unstructured stretch blazer',
            )
          : beach
          ? (
              'Lightweight athletic shorts',
              'Sport sandals',
              'Lightweight technical overshirt',
            )
          : occasion == Occasion.party
          ? (
              'Tailored stretch trousers',
              'Minimal leather sneakers',
              'Unstructured stretch blazer',
            )
          : (
              'Tapered track trousers',
              'Everyday trainers',
              'Lightweight technical jacket',
            ),
    StyleDirection.preppy =>
      beach
          ? (
              'Cotton chino shorts',
              'Canvas boat shoes',
              'Lightweight cotton cardigan',
            )
          : occasion == Occasion.special
          ? (
              'Pleated dress trousers',
              'Polished leather derbies',
              'Tailored blazer',
            )
          : ('Straight-leg chinos', 'Penny loafers', 'Fine-knit cardigan'),
  };
}

String _topRecipe(StyleDirection direction, Occasion occasion) {
  if (occasion == Occasion.special) return 'Crisp dress shirt';
  if (occasion == Occasion.beach) {
    return direction == StyleDirection.athleisure
        ? 'Breathable cotton T-shirt'
        : 'Relaxed linen shirt';
  }
  final polished =
      occasion == Occasion.office ||
      occasion == Occasion.party ||
      occasion == Occasion.date;
  return switch (direction) {
    StyleDirection.everyday => 'Casual button-down shirt',
    StyleDirection.smartCasual => 'Textured button-down shirt',
    StyleDirection.streetwear =>
      polished ? 'Clean-cut cotton shirt' : 'Relaxed cotton T-shirt',
    StyleDirection.athleisure =>
      polished ? 'Fine-knit polo' : 'Breathable cotton T-shirt',
    StyleDirection.preppy => 'Oxford button-down shirt',
  };
}

OutfitPiece _rename(OutfitPiece original, String title) => OutfitPiece(
  category: original.category,
  title: title,
  colorName: original.colorName,
  colorArgb: original.colorArgb,
);

OutfitRecommendation _rebuild(
  OutfitRecommendation original,
  StyleDirection direction, {
  OutfitPiece? pants,
  OutfitPiece? shoes,
  OutfitPiece? layer,
  String? shirtTitle,
  required String reason,
}) {
  final riding = original.occasion == Occasion.bikeRide;
  final selectedPants = pants ?? original.pants;
  final selectedShoes = shoes ?? original.shoes;
  final selectedLayer = layer ?? original.layer;
  final selectedShirtTitle = shirtTitle ?? original.shirtTitle;
  final garmentSignature = [
    selectedPants,
    selectedShoes,
    selectedLayer,
  ].map((piece) => '${piece.title}:${piece.colorArgb}').join('|');
  final signature = '$garmentSignature|$selectedShirtTitle';
  final reasons = original.reasons
      .where(
        (text) =>
            !(text.startsWith('Light fabrics and ') &&
                original.occasion == Occasion.beach),
      )
      .toList();
  return OutfitRecommendation(
    id: riding
        ? original.id
        : '${original.id}-style-${direction.name}-${Uri.encodeComponent(signature)}',
    title: original.title,
    description: riding
        ? original.description
        : '${direction.label} pieces, coordinated for your ${original.occasion.label.toLowerCase()}.',
    occasion: original.occasion,
    shirt: original.shirt,
    shirtTitle: selectedShirtTitle,
    startingPiece: original.startingPiece,
    topDetails: original.topDetails,
    pantsDetails: original.pantsDetails,
    pants: selectedPants,
    shoes: selectedShoes,
    layer: selectedLayer,
    reasons: List.unmodifiable([...reasons, reason]),
    fitAdvice: original.fitAdvice,
    safetyNote: original.safetyNote,
  );
}
