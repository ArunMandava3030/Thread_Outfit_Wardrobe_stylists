import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/models/style_discovery_models.dart';
import 'package:thread_style/models/outfit_rating_models.dart';
import 'package:thread_style/models/learning_models.dart';
import 'package:thread_style/models/wardrobe_models.dart';
import 'package:thread_style/models/weather_models.dart';
import 'package:thread_style/services/style_engine.dart';
import 'package:thread_style/services/style_direction_stylist.dart';
import 'package:thread_style/services/weather_stylist.dart';
import 'package:thread_style/services/adaptive_stylist.dart';
import 'package:thread_style/services/wardrobe_stylist.dart';
import 'package:thread_style/services/outfit_rater.dart';

const _blue = ShirtColor(name: 'Blue', argb: 0xFF7898B3);
const _navy = ShirtColor(name: 'Navy', argb: 0xFF25394F);
const _rust = ShirtColor(name: 'Rust', argb: 0xFFB96643);
const _black = ShirtColor(name: 'Black', argb: 0xFF262626);

GarmentVisualProfile _visual({
  double contrast = .85,
  double density = .85,
  double direction = .6,
  double regularity = .7,
  bool reverseShares = false,
}) => GarmentVisualProfile(
  contrast: contrast,
  detailDensity: density,
  directionality: direction,
  regularity: regularity,
  sampleWidth: 32,
  sampleHeight: 32,
  opaqueCoverage: 1,
  previewArgb: List.filled(256, _blue.argb),
  palette: [
    const VisualColorShare(color: _blue, share: .65),
    VisualColorShare(color: _navy, share: reverseShares ? .1 : .25),
    VisualColorShare(color: _rust, share: reverseShares ? .25 : .1),
  ],
);
GarmentDetails _details(
  GarmentVisualProfile visual, {
  GarmentType? type = GarmentType.shirt,
}) => GarmentDetails(type: type, visualProfile: visual);
List<OutfitRecommendation> _looks(
  GarmentVisualProfile visual, {
  StartingPiece piece = StartingPiece.shirt,
  ShirtColor? match,
  Occasion occasion = Occasion.casual,
  bool layer = true,
}) => const StyleEngine().generateForItem(
  startingPiece: piece,
  color: _blue,
  matchingColor: match,
  details: _details(
    visual,
    type: piece == StartingPiece.shirt
        ? GarmentType.shirt
        : GarmentType.trousers,
  ),
  occasion: occasion,
  profile: const StyleProfile(),
  includeLayer: layer,
);
OutfitRatingInput _rating(GarmentDetails top, GarmentDetails pants) =>
    OutfitRatingInput(
      topColor: _blue,
      pantsColor: _navy,
      shoesColor: _black,
      layerColor: _black,
      topDetails: top,
      pantsDetails: pants,
    );

void main() {
  test(
    'visual profile persists without labels and clears independently of garment type',
    () {
      final details = _details(_visual());
      final restored = GarmentDetails.fromJson(
        jsonDecode(jsonEncode(details.toJson())),
      );
      expect(restored.visualProfile?.isReliable, isTrue);
      expect(restored.signature, details.signature);
      expect(
        restored.summary(StartingPiece.shirt),
        contains(details.visualProfile!.shortDescription),
      );
      expect(details.pattern, GarmentPattern.solid);
      expect(
        details.copyWith(type: GarmentType.flannel).visualProfile,
        details.visualProfile,
      );
      expect(details.copyWith(visualProfile: null).visualProfile, isNull);
      expect(GarmentDetails.fromJson({'type': 'shirt'}).visualProfile, isNull);
      expect(
        GarmentDetails.fromJson({'visualProfile': 'broken'}).measuredVisual,
        isNull,
      );
      final old = const GarmentDetails(type: GarmentType.shirt);
      expect(old.signature, 'shirt-solid-');
    },
  );

  test(
    'measured palette shares change companion colors in both directions',
    () {
      for (final piece in StartingPiece.values) {
        List<ShirtColor> matches(GarmentVisualProfile visual) =>
            const StyleEngine().matchingColors(
              startingPiece: piece,
              color: _blue,
              details: _details(visual),
            );
        final first = matches(_visual());
        final shifted = matches(_visual(reverseShares: true));
        expect(first[1].argb, _navy.argb);
        expect(first[2].argb, _rust.argb);
        expect(
          first.map(
            (match) => const StyleEngine().matchingColorHint(
              color: _blue,
              matchingColor: match,
              details: _details(_visual()),
            ),
          ),
          ['Quiet neutral', 'Color echo', 'Accent pick'],
        );
        expect(shifted[1].argb, _rust.argb);
        expect(shifted[2].argb, _navy.argb);
        final looks = _looks(_visual(), piece: piece);
        final colors = looks
            .map(
              (look) => piece == StartingPiece.shirt
                  ? look.pants.colorArgb
                  : look.shirt.argb,
            )
            .toSet();
        expect(colors, hasLength(3));
      }
    },
  );

  test(
    'contrast and density alter neutral priority and actual layer treatment',
    () {
      final quiet = _visual(
        contrast: .1,
        density: .1,
        direction: .2,
        regularity: .2,
      );
      final loud = _visual();
      final quietLooks = _looks(quiet), loudLooks = _looks(loud);
      expect(quietLooks.first.pants.colorArgb, _navy.argb);
      expect(loudLooks.first.pants.colorArgb, isNot(_navy.argb));
      expect(quietLooks.first.layer.title, contains('textured'));
      expect(loudLooks.first.layer.title, startsWith('Plain '));
      expect(quietLooks[1].layer.colorArgb, _navy.argb);
      expect(loudLooks[1].layer.colorArgb, isNot(_navy.argb));
      final lowContrast = _looks(
        _visual(contrast: .1, density: .4, direction: .4, regularity: .4),
      );
      final highContrast = _looks(
        _visual(contrast: .9, density: .4, direction: .4, regularity: .4),
      );
      expect(lowContrast.first.layer.title, isNot(startsWith('Plain ')));
      expect(highContrast.first.layer.title, startsWith('Plain '));
      final lowDensity = _looks(
        _visual(contrast: .5, density: .1, direction: .2, regularity: .2),
      );
      final highDensity = _looks(
        _visual(contrast: .5, density: .9, direction: .2, regularity: .2),
      );
      expect(lowDensity.first.layer.title, isNot(startsWith('Plain ')));
      expect(highDensity.first.layer.title, startsWith('Plain '));
    },
  );

  test(
    'directionality and regularity guide quieter textures without naming a pattern',
    () {
      final directional = _looks(
        _visual(contrast: .1, density: .1, direction: .9, regularity: .2),
      );
      final regular = _looks(
        _visual(contrast: .1, density: .1, direction: .2, regularity: .9),
      );
      final irregular = _looks(
        _visual(contrast: .1, density: .1, direction: .2, regularity: .2),
      );
      expect(directional.first.layer.title, contains('Smooth'));
      expect(regular.first.layer.title, 'Fine-knit cardigan');
      expect(irregular.first.layer.title, contains('textured'));
      for (final look in [directional.first, regular.first, irregular.first]) {
        expect(look.topDetails.pattern, GarmentPattern.solid);
        expect(look.reasons.join(' '), contains('sampled'));
      }
    },
  );

  test(
    'explicit companion color stays fixed while finishing options use measured small accents',
    () {
      final looks = _looks(_visual(), match: _black);
      expect(
        looks.every((look) => look.pants.colorArgb == _black.argb),
        isTrue,
      );
      expect(looks[1].shoes.colorArgb, _navy.argb);
      expect(looks.last.shoes.colorArgb, _rust.argb);
      expect(
        _looks(
          _visual(reverseShares: true),
          match: _black,
        ).last.shoes.colorArgb,
        _navy.argb,
      );
      expect(
        _looks(
          _visual(),
          match: _black,
          occasion: Occasion.office,
        ).last.shoes.colorArgb,
        isNot(_rust.argb),
      );
      expect(
        _looks(
          _visual(),
          layer: false,
        ).every((look) => look.layer.colorArgb == 0),
        isTrue,
      );
    },
  );

  test(
    'style and weather retain measured anchor and high-detail quiet treatment',
    () {
      final visual = _visual();
      for (final piece in StartingPiece.values) {
        final original = _looks(visual, piece: piece, match: _black);
        final style = const StyleDirectionStylist().adapt(
          original,
          StyleDirection.smartCasual,
        );
        final weather = const WeatherStylist().adapt(
          style,
          WeatherSnapshot(
            location: const CityLocation(
              name: 'Test',
              latitude: 0,
              longitude: 0,
            ),
            temperatureC: 5,
            apparentTemperatureC: 4,
            windKmh: 30,
            precipitationMm: 2,
            weatherCode: 61,
            fetchedAt: DateTime.now().toUtc(),
          ),
          includeLayer: true,
        );
        for (final look in weather) {
          final anchor = piece == StartingPiece.shirt
              ? look.topDetails
              : look.pantsDetails;
          expect(anchor.visualProfile?.signature, visual.signature);
          expect(look.layer.title, startsWith('Plain '));
          expect(
            piece == StartingPiece.shirt
                ? look.pants.colorArgb
                : look.shirt.argb,
            _black.argb,
          );
        }
      }
    },
  );

  test('measured visuals cannot replace mandatory certified riding pieces', () {
    final looks = _looks(_visual(), occasion: Occasion.bikeRide, layer: false);
    for (final look in looks) {
      expect(look.pants.title, contains('Certified motorcycle'));
      expect(look.pantsDetails.type, isNull);
      expect(look.layer.title, contains('Certified armored'));
      expect(look.shoes.title, contains('Protective motorcycle'));
      expect(look.shoes.colorArgb, isNot(_rust.argb));
    }
    final pants = _looks(
      _visual(),
      piece: StartingPiece.pants,
      occasion: Occasion.bikeRide,
    ).first;
    expect(pants.pants.title, isNot(contains('Certified')));
    expect(pants.reasons.join(' '), contains('only if they are certified'));
  });

  test(
    'rating visual balance scales continuously and shares affect palette echo',
    () {
      const rater = OutfitRater();
      final subtle = _details(
        _visual(contrast: .15, density: .15, direction: .15, regularity: .15),
      );
      final medium = _details(
        _visual(contrast: .5, density: .5, direction: .5, regularity: .5),
      );
      final strong = _details(
        _visual(contrast: .9, density: .9, direction: .9, regularity: .9),
      );
      double coordination(GarmentDetails top, GarmentDetails pants) =>
          rater.rate(_rating(top, pants)).components.first.score;
      expect(
        coordination(subtle, subtle),
        greaterThan(coordination(medium, medium)),
      );
      expect(
        coordination(medium, medium),
        greaterThan(coordination(strong, strong)),
      );
      expect(
        coordination(_details(_visual()), const GarmentDetails()),
        greaterThan(
          coordination(
            _details(_visual(reverseShares: true)),
            const GarmentDetails(),
          ),
        ),
      );
      final rated = rater.rate(_rating(strong, strong));
      expect(
        rated.suggestions.join(' '),
        contains('balance adjustment scales'),
      );
      expect(
        rated.outfit.topDetails.visualProfile?.signature,
        strong.visualProfile?.signature,
      );
      expect(rated.score, inInclusiveRange(0, 5));
    },
  );

  test(
    'ratings and stored outfit identities distinguish measured feature changes',
    () {
      final first = _rating(
        _details(_visual()),
        const GarmentDetails(),
      ).toOutfit();
      final second = _rating(
        _details(_visual(density: .2)),
        const GarmentDetails(),
      ).toOutfit();
      expect(first.id, isNot(second.id));
      final restored = OutfitRecommendation.fromJson(
        jsonDecode(jsonEncode(first.toJson())) as Map<String, dynamic>,
      );
      expect(restored.id, first.id);
      expect(
        restored.topDetails.visualProfile?.signature,
        first.topDetails.visualProfile?.signature,
      );
    },
  );

  test(
    'local preference learning transfers measured detail preferences to unseen outfits',
    () {
      final base = _looks(_visual()).first;
      OutfitRecommendation sample(String id, double density) =>
          OutfitRecommendation.fromJson({
            ...base.toJson(),
            'id': id,
            'topDetails': _details(_visual(density: density)).toJson(),
          });
      const learner = AdaptiveStylist();
      final history = learner.record(
        learner.record([], sample('like', .1), StyleFeedback.like),
        sample('dislike', .95),
        StyleFeedback.dislike,
      );
      expect(
        learner.preferenceScore(sample('new-low', .15), history),
        greaterThan(learner.preferenceScore(sample('new-high', .9), history)),
      );
    },
  );

  test(
    'wardrobe compatibility compares measured detail and palette proportions',
    () {
      final look = _looks(_visual(), piece: StartingPiece.pants).first;
      WardrobeItem owned(GarmentVisualProfile visual) => WardrobeItem(
        id: 'scan',
        name: 'My trousers',
        colorName: _blue.name,
        colorArgb: _blue.argb,
        category: WardrobeCategory.pants,
        details: _details(visual, type: GarmentType.trousers),
      );
      const stylist = WardrobeStylist();
      expect(stylist.coverage(look, [owned(_visual())]), 1);
      expect(
        stylist.coverage(look, [
          owned(
            _visual(
              contrast: .05,
              density: .05,
              direction: .05,
              regularity: .05,
            ),
          ),
        ]),
        0,
      );
      final plain = const StyleEngine()
          .generateForItem(
            startingPiece: StartingPiece.shirt,
            color: _navy,
            matchingColor: _blue,
            occasion: Occasion.casual,
            details: const GarmentDetails(type: GarmentType.knit),
            profile: const StyleProfile(),
          )
          .first;
      expect(stylist.coverage(plain, [owned(_visual())]), 0);
    },
  );
}
