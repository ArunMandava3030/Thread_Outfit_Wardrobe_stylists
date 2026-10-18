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
        return _rebuild(
          outfit,
          direction,
          pants: _rename(outfit.pants, recipe.$1),
          shoes: _rename(outfit.shoes, recipe.$2),
          layer: hasLayer ? _rename(outfit.layer, recipe.$3) : outfit.layer,
          reason:
              outfit.occasion == Occasion.office &&
                  (direction == StyleDirection.streetwear ||
                      direction == StyleDirection.athleisure)
              ? '${direction.label} is softened for a smart-casual office with tailored trousers and closed shoes; follow your workplace dress code.'
              : '${direction.label} shapes the garments while your shirt, color palette and ${outfit.occasion.label.toLowerCase()} plans stay the starting point.',
        );
      }),
    );
  }
}

(String, String, String) _recipe(StyleDirection direction, Occasion occasion) {
  final office = occasion == Occasion.office;
  final beach = occasion == Occasion.beach;
  return switch (direction) {
    StyleDirection.everyday => (
      'Straight-leg chinos',
      'Everyday sneakers',
      'Cotton overshirt',
    ),
    StyleDirection.smartCasual =>
      beach
          ? ('Linen trousers', 'Canvas slip-ons', 'Open linen shirt')
          : ('Straight-leg chinos', 'Leather loafers', 'Unstructured blazer'),
    StyleDirection.streetwear =>
      office
          ? (
              'Relaxed tailored trousers',
              'Minimal leather sneakers',
              'Structured overshirt',
            )
          : beach
          ? (
              'Relaxed cotton shorts',
              'Canvas slip-ons',
              'Lightweight cotton overshirt',
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
          : ('Straight-leg chinos', 'Penny loafers', 'Fine-knit cardigan'),
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
  required String reason,
}) {
  final riding = original.occasion == Occasion.bikeRide;
  final selectedPants = pants ?? original.pants;
  final selectedShoes = shoes ?? original.shoes;
  final selectedLayer = layer ?? original.layer;
  final signature = [
    selectedPants,
    selectedShoes,
    selectedLayer,
  ].map((piece) => '${piece.title}:${piece.colorArgb}').join('|');
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
    pants: selectedPants,
    shoes: selectedShoes,
    layer: selectedLayer,
    reasons: List.unmodifiable([...reasons, reason]),
    fitAdvice: original.fitAdvice,
    safetyNote: original.safetyNote,
  );
}
