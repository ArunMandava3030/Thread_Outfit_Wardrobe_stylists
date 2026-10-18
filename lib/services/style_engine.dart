import '../models/style_models.dart';

/// Local, explainable outfit suggestions. No photos or measurements leave the
/// device, and an unset profile is a valid starting point.
class StyleEngine {
  const StyleEngine();

  List<OutfitRecommendation> generate({
    required ShirtColor shirt,
    required Occasion occasion,
    required StyleProfile profile,
    bool includeLayer = true,
  }) {
    final palettes = _palettesFor(shirt);
    final silhouettes = _silhouettes[occasion]!;
    return List<OutfitRecommendation>.unmodifiable(
      List.generate(3, (index) {
        final palette = _personalizePalette(palettes[index], profile, index);
        final silhouette = silhouettes[index];
        final needsRidingGear = occasion == Occasion.bikeRide;
        final showLayer = includeLayer || needsRidingGear;
        final shoeColor = needsRidingGear ? _black : palette.shoes;
        final reasons = <String>[
          '${palette.pants.name} gives your ${shirt.name.toLowerCase()} shirt '
              '${index == 0
                  ? 'a clean, balanced pairing'
                  : index == 1
                  ? 'a softer alternative'
                  : 'a little more depth'}.',
          _occasionReason(occasion, index),
        ];
        final toneNote = _toneAdvice(profile, shirt);
        if (toneNote != null) reasons.add(toneNote);
        if (showLayer) {
          reasons.add(
            needsRidingGear
                ? 'Riding protection stays part of the outfit, even with optional layers off.'
                : 'A ${palette.layer.name.toLowerCase()} layer connects the palette without adding another strong color.',
          );
        } else {
          reasons.add(
            'Two main clothing colors keep this outfit easy to wear without a layer.',
          );
        }
        return OutfitRecommendation(
          id:
              '${occasion.name}-${shirt.hex.substring(1)}-$index-'
              '${palette.pants.argb.toRadixString(16)}-'
              '${shoeColor.argb.toRadixString(16)}-'
              '${showLayer ? palette.layer.argb.toRadixString(16) : 'light'}',
          title: silhouette.title,
          description: silhouette.description,
          occasion: occasion,
          shirt: shirt,
          pants: OutfitPiece(
            category: 'Pants',
            title: silhouette.pants,
            colorName: palette.pants.name,
            colorArgb: palette.pants.argb,
          ),
          shoes: OutfitPiece(
            category: 'Shoes',
            title: silhouette.shoes,
            colorName: shoeColor.name,
            colorArgb: shoeColor.argb,
          ),
          layer: OutfitPiece(
            category: 'Layer',
            title: showLayer ? silhouette.layer : 'Skip the layer',
            colorName: showLayer ? palette.layer.name : 'None',
            colorArgb: showLayer ? palette.layer.argb : 0x00000000,
          ),
          reasons: List<String>.unmodifiable(reasons),
          fitAdvice: _fitAdvice(profile, occasion),
          safetyNote: needsRidingGear
              ? 'For motorbike rides, wear a properly fitted helmet, gloves, '
                    'certified motorcycle jacket and trousers, and motorcycle boots. '
                    'Ordinary fashion layers are not protective riding gear. '
                    'Choose protection and visibility before color.'
              : null,
        );
      }),
    );
  }

  _Palette _personalizePalette(_Palette base, StyleProfile profile, int index) {
    if (!profile.useSkinTone) return base;
    var layer = switch (profile.undertone) {
      Undertone.warm => const [_sand, _ecru, _chocolate][index],
      Undertone.cool => const [_navy, _stone, _charcoal][index],
      Undertone.neutral || Undertone.unsure => base.layer,
    };
    // Offer a stronger contrast in the third look, while the first two retain
    // softer or tonal combinations. This is a style option, not a color ban.
    if (profile.skinToneArgb != null && index == 2) {
      final skin = _Rgb(profile.skinToneArgb!);
      final layerColor = _Rgb(layer.argb);
      if ((skin.lightness - layerColor.lightness).abs() < 0.25) {
        layer = skin.lightness < 0.5
            ? (profile.undertone == Undertone.cool ? _stone : _ecru)
            : (profile.undertone == Undertone.warm ? _chocolate : _navy);
      }
    }
    final shoes = switch (profile.undertone) {
      Undertone.warm => _cocoa,
      Undertone.cool => index == 1 ? _white : _black,
      Undertone.neutral || Undertone.unsure => base.shoes,
    };
    return _Palette(base.pants, shoes, layer);
  }

  List<_Palette> _palettesFor(ShirtColor shirt) {
    final rgb = _Rgb(shirt.argb);
    // Work from the sampled RGB value, rather than trusting a color's label.
    // This also supports arbitrary camera colors, not only the preset swatches.
    if (rgb.saturation < 0.12) {
      if (rgb.lightness < 0.28) {
        return const [
          _Palette(_stone, _white, _charcoal),
          _Palette(_olive, _black, _ecru),
          _Palette(_charcoal, _cocoa, _sand),
        ];
      }
      if (rgb.lightness > 0.78) {
        return const [
          _Palette(_navy, _cocoa, _sand),
          _Palette(_olive, _white, _navy),
          _Palette(_stone, _cocoa, _charcoal),
        ];
      }
      return const [
        _Palette(_navy, _white, _ecru),
        _Palette(_olive, _cocoa, _sand),
        _Palette(_black, _black, _navy),
      ];
    }
    final hue = rgb.hue;
    if (hue >= 65 && hue < 170) {
      return const [
        _Palette(_ecru, _cocoa, _navy),
        _Palette(_charcoal, _white, _stone),
        _Palette(_sand, _cocoa, _chocolate),
      ];
    }
    if (hue >= 170 && hue < 265) {
      return const [
        _Palette(_stone, _cocoa, _navy),
        _Palette(_sand, _white, _ecru),
        _Palette(_charcoal, _black, _olive),
      ];
    }
    if (hue >= 265 && hue < 345) {
      return const [
        _Palette(_charcoal, _black, _ecru),
        _Palette(_stone, _white, _navy),
        _Palette(_navy, _cocoa, _sand),
      ];
    }
    // Pale pink and muted warm colors pair well with cool, darker neutrals.
    if (rgb.lightness > 0.62) {
      return const [
        _Palette(_navy, _cocoa, _ecru),
        _Palette(_olive, _white, _stone),
        _Palette(_chocolate, _cocoa, _sand),
      ];
    }
    if (hue < 22 || hue >= 345) {
      return const [
        _Palette(_charcoal, _black, _stone),
        _Palette(_ecru, _cocoa, _navy),
        _Palette(_navy, _white, _sand),
      ];
    }
    return const [
      _Palette(_navy, _cocoa, _ecru),
      _Palette(_stone, _white, _olive),
      _Palette(_olive, _cocoa, _chocolate),
    ];
  }

  String _occasionReason(Occasion occasion, int index) => switch (occasion) {
    Occasion.office =>
      'Tailored separates and closed shoes work for a smart-casual office; follow your workplace dress code.',
    Occasion.date =>
      'Clean lines and a little texture make this feel considered for a dinner or a relaxed date.',
    Occasion.casual =>
      'Easy trousers and comfortable shoes keep the outfit relaxed for an everyday outing.',
    Occasion.beach =>
      'Light fabrics and ${index == 1 ? 'shorts' : 'relaxed trousers'} suit a warm, easy beach day.',
    Occasion.bikeRide =>
      'The colors are a styling guide for certified riding gear, with mobility and protection taking priority.',
  };

  String _fitAdvice(StyleProfile profile, Occasion occasion) {
    if (occasion == Occasion.bikeRide) {
      return 'Try riding gear in your seated riding position. Shoulders, elbows, '
          'knees and waist should move comfortably while protective armor stays '
          'in place. Follow the gear maker’s fit guidance.';
    }
    final suggestions = <String>[];
    if (profile.heightCm < 168) {
      suggestions.add(
        'Try a mid-rise or high-rise waist and a clean trouser hem for a longer, uninterrupted line.',
      );
    } else if (profile.heightCm > 185) {
      suggestions.add(
        'Check sleeve and trouser length first; a regular-length layer and a slight trouser break can feel balanced.',
      );
    } else {
      suggestions.add(
        'Start with a comfortable mid-rise and a trouser hem that just meets the top of your shoes.',
      );
    }
    suggestions.add(switch (profile.bodyShape) {
      BodyShape.balanced =>
        'Straight or gently tapered trousers keep the silhouette easy; choose the amount of looseness you enjoy.',
      BodyShape.broadShoulders =>
        'Try unpadded shoulders and straight or relaxed trousers for comfortable proportions.',
      BodyShape.widerHips =>
        'Give the hip and thigh room to move; a softly structured layer is an option if you like more shape up top.',
      BodyShape.fullerMidsection =>
        'Look for a waistband that feels comfortable sitting down and fabric that skims without pulling; an open layer is optional.',
      null =>
        'Fit the shoulders comfortably and leave room to move. Add your preferred proportions in your profile for more specific tips.',
    });
    if (occasion == Occasion.beach) {
      suggestions.add(
        'Choose breathable fabric and enough ease for warm weather.',
      );
    }
    return suggestions.join(' ');
  }

  String? _toneAdvice(StyleProfile profile, ShirtColor shirt) {
    if (!profile.useSkinTone) return null;
    final undertoneTip = switch (profile.undertone) {
      Undertone.warm =>
        'If you enjoy warm accents, try tan or cream near your face.',
      Undertone.cool =>
        'If you enjoy cool accents, try navy or soft grey near your face.',
      Undertone.neutral =>
        'Your neutral preference leaves room to mix warm and cool accents.',
      Undertone.unsure =>
        'Try both a warm and a cool accent in daylight and keep the one you enjoy.',
    };
    final skinTone = profile.skinToneArgb;
    if (skinTone == null) {
      return '$undertoneTip Any shirt color remains an option.';
    }
    final tone = _Rgb(skinTone);
    final top = _Rgb(shirt.argb);
    final contrast = (tone.lightness - top.lightness).abs();
    final contrastTip = contrast < 0.2
        ? 'Your sampled tone and shirt create a soft contrast; a lighter or darker collar or layer can add definition if you want it.'
        : 'Your sampled tone and shirt create visible contrast; the neutral pieces let that pairing lead.';
    return '$contrastTip $undertoneTip';
  }
}

class _Rgb {
  _Rgb(int argb)
    : r = ((argb >> 16) & 255) / 255,
      g = ((argb >> 8) & 255) / 255,
      b = (argb & 255) / 255;

  final double r;
  final double g;
  final double b;

  double get max => r > g ? (r > b ? r : b) : (g > b ? g : b);
  double get min => r < g ? (r < b ? r : b) : (g < b ? g : b);
  double get lightness => (max + min) / 2;
  double get saturation =>
      max == min ? 0 : (max - min) / (1 - (2 * lightness - 1).abs());
  double get hue {
    final delta = max - min;
    if (delta == 0) return 0;
    if (max == r) return (60 * ((g - b) / delta)) % 360;
    if (max == g) return 60 * ((b - r) / delta + 2);
    return 60 * ((r - g) / delta + 4);
  }
}

class _Color {
  const _Color(this.name, this.argb);
  final String name;
  final int argb;
}

const _navy = _Color('Navy', 0xFF293B50);
const _stone = _Color('Stone', 0xFFC7C2B6);
const _sand = _Color('Sand', 0xFFD9C6A6);
const _ecru = _Color('Ecru', 0xFFECE5D4);
const _olive = _Color('Olive', 0xFF747854);
const _charcoal = _Color('Charcoal', 0xFF484A49);
const _black = _Color('Black', 0xFF272928);
const _white = _Color('Off-white', 0xFFF2EFE6);
const _cocoa = _Color('Cocoa', 0xFF836248);
const _chocolate = _Color('Chocolate', 0xFF594536);

class _Palette {
  const _Palette(this.pants, this.shoes, this.layer);
  final _Color pants;
  final _Color shoes;
  final _Color layer;
}

class _Silhouette {
  const _Silhouette(
    this.title,
    this.description,
    this.pants,
    this.shoes,
    this.layer,
  );
  final String title;
  final String description;
  final String pants;
  final String shoes;
  final String layer;
}

const _silhouettes = <Occasion, List<_Silhouette>>{
  Occasion.office: [
    _Silhouette(
      'Quiet confidence',
      'A considered palette for your working day.',
      'Tailored trousers',
      'Leather loafers',
      'Unstructured blazer',
    ),
    _Silhouette(
      'A softer approach',
      'Relaxed texture with a polished finish.',
      'Straight-leg chinos',
      'Leather derbies',
      'Fine-knit cardigan',
    ),
    _Silhouette(
      'Everyday professional',
      'Comfortable separates, ready for the office.',
      'Pleated trousers',
      'Leather loafers',
      'Structured overshirt',
    ),
  ],
  Occasion.date: [
    _Silhouette(
      'A good first impression',
      'Understated color, a little extra intention.',
      'Straight-leg trousers',
      'Suede loafers',
      'Unstructured blazer',
    ),
    _Silhouette(
      'Easy chemistry',
      'Soft tones for a relaxed evening together.',
      'Relaxed chinos',
      'Minimal leather sneakers',
      'Textured cardigan',
    ),
    _Silhouette(
      'After hours',
      'A richer palette for dinner and wherever next.',
      'Pleated trousers',
      'Leather derbies',
      'Lightweight bomber',
    ),
  ],
  Occasion.casual: [
    _Silhouette(
      'Your everyday, elevated',
      'Easy pieces that naturally work together.',
      'Straight-leg chinos',
      'Everyday sneakers',
      'Cotton overshirt',
    ),
    _Silhouette(
      'Take it easy',
      'A softer palette for an unhurried day.',
      'Relaxed cotton trousers',
      'Canvas sneakers',
      'Lightweight zip jacket',
    ),
    _Silhouette(
      'Out and about',
      'A little depth, plenty of room to move.',
      'Straight-leg denim',
      'Low-top sneakers',
      'Textured overshirt',
    ),
  ],
  Occasion.beach: [
    _Silhouette(
      'Coastal state of mind',
      'Airy fabric and warm, natural texture.',
      'Linen trousers',
      'Leather sandals',
      'Open linen shirt',
    ),
    _Silhouette(
      'Chasing the sun',
      'Light layers for a laid-back beach day.',
      'Relaxed cotton shorts',
      'Canvas slip-ons',
      'Lightweight linen overshirt',
    ),
    _Silhouette(
      'Seaside slow-down',
      'An easy silhouette from boardwalk to sunset.',
      'Linen drawstring trousers',
      'Espadrilles',
      'Linen shirt',
    ),
  ],
  Occasion.bikeRide: [
    _Silhouette(
      'Ready for the road',
      'A coordinated palette for protective riding gear.',
      'Certified motorcycle riding trousers',
      'Protective motorcycle boots',
      'Certified armored motorcycle jacket',
    ),
    _Silhouette(
      'The scenic route',
      'Comfort and protection with a softer color direction.',
      'Certified motorcycle riding jeans',
      'Protective motorcycle boots',
      'Certified armored textile riding jacket',
    ),
    _Silhouette(
      'Weekend miles',
      'A grounded color palette for your riding kit.',
      'Certified motorcycle riding trousers',
      'Protective motorcycle boots',
      'Certified armored motorcycle jacket',
    ),
  ],
};
