import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/learning_models.dart';
import 'package:thread_style/models/style_discovery_models.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/models/wardrobe_models.dart';
import 'package:thread_style/models/weather_models.dart';
import 'package:thread_style/services/adaptive_stylist.dart';
import 'package:thread_style/services/style_direction_stylist.dart';
import 'package:thread_style/services/style_engine.dart';
import 'package:thread_style/services/wardrobe_stylist.dart';
import 'package:thread_style/services/weather_stylist.dart';

const _red = ShirtColor(name: 'Red', argb: 0xFFC94F4F);
const _navy = ShirtColor(name: 'Navy', argb: 0xFF25394F);
const _cream = ShirtColor(name: 'Cream', argb: 0xFFECE5D4);
const _checkedFlannel = GarmentDetails(
  type: GarmentType.flannel,
  pattern: GarmentPattern.checks,
  accentColors: [_navy, _cream],
);

List<OutfitRecommendation> _looks({
  StartingPiece piece = StartingPiece.shirt,
  GarmentDetails details = _checkedFlannel,
  Occasion occasion = Occasion.casual,
  bool includeLayer = true,
}) => const StyleEngine().generateForItem(
  startingPiece: piece,
  color: _red,
  matchingColor: _navy,
  details: details,
  occasion: occasion,
  profile: const StyleProfile(),
  includeLayer: includeLayer,
);

WeatherSnapshot _coldRain() => WeatherSnapshot(
  location: const CityLocation(name: 'Test', latitude: 10, longitude: 20),
  temperatureC: 6,
  apparentTemperatureC: 4,
  windKmh: 30,
  precipitationMm: 2,
  weatherCode: 61,
  fetchedAt: DateTime.now().toUtc(),
);

void main() {
  test('checked flannel keeps its fabric, pattern and all colors', () {
    final looks = _looks();
    for (final look in looks) {
      expect(look.shirt, _red);
      expect(look.topDetails.signature, _checkedFlannel.signature);
      expect(look.topDetails.accentColors, [_navy, _cream]);
      expect(look.shirtTitle, contains('checked flannel'));
      expect(look.pants.colorArgb, _navy.argb);
      expect(look.pantsDetails.pattern, GarmentPattern.solid);
      expect(look.pants.title.toLowerCase(), startsWith('plain '));
      expect(look.layer.title.toLowerCase(), startsWith('plain '));
      expect(look.reasons.join(' '), contains('Echo one color'));
    }
    expect(looks.first.pantsDetails.type, GarmentType.jeans);
  });

  test('patterned pants keep their details and suggest plain tops', () {
    const details = GarmentDetails(
      type: GarmentType.trousers,
      pattern: GarmentPattern.stripes,
      accentColors: [_cream],
    );
    final looks = _looks(piece: StartingPiece.pants, details: details);
    for (final look in looks) {
      expect(look.pants.colorArgb, _red.argb);
      expect(look.pantsDetails.signature, details.signature);
      expect(look.pants.title, contains('striped tailored trousers'));
      expect(look.shirt, _navy);
      expect(look.topDetails.pattern, GarmentPattern.solid);
      expect(look.shirtTitle.toLowerCase(), startsWith('plain '));
    }
    expect(looks.first.topDetails.type, GarmentType.knit);
  });

  test(
    'palette matching echoes an actual accent instead of averaging colors',
    () {
      const engine = StyleEngine();
      final plain = engine.matchingColors(
        startingPiece: StartingPiece.shirt,
        color: _red,
      );
      final checks = engine.matchingColors(
        startingPiece: StartingPiece.shirt,
        color: _red,
        details: const GarmentDetails(
          pattern: GarmentPattern.checks,
          accentColors: [_navy],
        ),
      );
      expect(checks.length, 3);
      expect(checks.first.argb, _navy.argb);
      expect(
        checks.map((color) => color.argb),
        isNot(plain.map((color) => color.argb)),
      );
      expect(checks.map((color) => color.argb).toSet().length, 3);
      final otherAccent = engine.matchingColors(
        startingPiece: StartingPiece.pants,
        color: _red,
        details: const GarmentDetails(
          pattern: GarmentPattern.checks,
          accentColors: [_cream],
        ),
      );
      expect(otherAccent.first.argb, _cream.argb);
    },
  );

  test('shirt type changes companion cuts while occasion adds polish', () {
    final tee = _looks(details: const GarmentDetails(type: GarmentType.tShirt));
    final shirt = _looks(
      details: const GarmentDetails(type: GarmentType.shirt),
    );
    final knit = _looks(details: const GarmentDetails(type: GarmentType.knit));
    expect(tee.first.pantsDetails.type, GarmentType.jeans);
    expect(shirt.first.pantsDetails.type, GarmentType.chinos);
    expect(knit.first.pantsDetails.type, GarmentType.trousers);
    expect(tee.last.pantsDetails.type, GarmentType.joggers);
    final special = _looks(
      details: const GarmentDetails(type: GarmentType.tShirt),
      occasion: Occasion.special,
    );
    expect(special.first.pantsDetails.type, GarmentType.trousers);
    expect(special.first.topDetails.type, GarmentType.tShirt);
    expect(
      special.first.reasons.join(' '),
      contains('do not make casual clothing formal'),
    );
  });

  test('jeans chinos and tailored pants lead to different suggested tops', () {
    GarmentType? topFor(GarmentType pants) => _looks(
      piece: StartingPiece.pants,
      details: GarmentDetails(type: pants),
    ).first.topDetails.type;
    expect(topFor(GarmentType.jeans), GarmentType.tShirt);
    expect(topFor(GarmentType.chinos), GarmentType.polo);
    expect(topFor(GarmentType.trousers), GarmentType.knit);
    expect(topFor(GarmentType.shorts), GarmentType.tShirt);
    final office = _looks(
      piece: StartingPiece.pants,
      details: const GarmentDetails(type: GarmentType.joggers),
      occasion: Occasion.office,
    ).first;
    expect(office.pantsDetails.type, GarmentType.joggers);
    expect(office.reasons.join(' '), contains('dress code allows'));
  });

  test(
    'flannel is independent of pattern and extra colors remain optional',
    () {
      final solid = _looks(
        details: const GarmentDetails(type: GarmentType.flannel),
      ).first;
      expect(solid.topDetails.pattern, GarmentPattern.solid);
      expect(solid.topDetails.accentColors, isEmpty);
      expect(solid.shirtTitle, contains('solid flannel'));
      final extractedPalette = _looks(
        details: const GarmentDetails(
          type: GarmentType.flannel,
          accentColors: [_navy, _cream],
        ),
      ).first;
      expect(extractedPalette.topDetails.pattern, GarmentPattern.solid);
      expect(extractedPalette.shirtTitle, contains('multicolor flannel'));
      expect(extractedPalette.shirtTitle, isNot(contains('solid')));
      final multi = _looks(
        details: const GarmentDetails(
          type: GarmentType.tShirt,
          pattern: GarmentPattern.print,
          accentColors: [_navy, _cream],
        ),
      ).first;
      expect(multi.topDetails.accentColors, hasLength(2));
      expect(multi.pants.title, startsWith('Plain '));
    },
  );

  test(
    'style and weather retain owned details and plain companion garments',
    () {
      for (final piece in StartingPiece.values) {
        final details = piece == StartingPiece.shirt
            ? _checkedFlannel
            : const GarmentDetails(
                type: GarmentType.jeans,
                pattern: GarmentPattern.colorBlock,
                accentColors: [_cream],
              );
        final original = _looks(
          piece: piece,
          details: details,
          occasion: Occasion.party,
        );
        for (final direction in StyleDirection.values) {
          final adapted = const WeatherStylist().adapt(
            const StyleDirectionStylist().adapt(original, direction),
            _coldRain(),
            includeLayer: true,
          );
          for (var i = 0; i < original.length; i++) {
            final before = original[i], after = adapted[i];
            expect(after.topDetails.signature, before.topDetails.signature);
            expect(after.pantsDetails.signature, before.pantsDetails.signature);
            expect(after.shirtTitle, before.shirtTitle);
            expect(after.pants.title, before.pants.title);
            expect(after.shirt, before.shirt);
            expect(after.pants.colorArgb, before.pants.colorArgb);
            expect(after.layer.title.toLowerCase(), startsWith('plain '));
          }
        }
      }
    },
  );

  test('ordinary checked clothes never become certified motorcycle gear', () {
    final pants = _looks(
      piece: StartingPiece.pants,
      details: const GarmentDetails(
        type: GarmentType.jeans,
        pattern: GarmentPattern.checks,
      ),
      occasion: Occasion.bikeRide,
      includeLayer: false,
    ).first;
    expect(pants.pants.title, isNot(contains('certified')));
    expect(pants.reasons.join(' '), contains('only if they are certified'));
    expect(pants.layer.title, contains('Certified'));
    expect(pants.safetyNote, contains('Ordinary fashion layers'));
    final shirt = _looks(
      occasion: Occasion.bikeRide,
      includeLayer: false,
    ).first;
    expect(shirt.pants.title, contains('Certified motorcycle'));
    expect(shirt.topDetails.type, GarmentType.flannel);
    expect(
      _looks(occasion: Occasion.bikeRide).map((look) => look.pantsDetails.type),
      everyElement(isNull),
      reason:
          'Fashion metadata cannot describe certified riding trousers or jeans.',
    );
    expect(
      const WardrobeStylist().matchesFor(pants, [
        _owned(pants, pants.pantsDetails),
      ]),
      isEmpty,
    );
  });

  test('optional layers stay off for patterned non-riding outfits', () {
    expect(
      _looks(includeLayer: false).every((look) => look.layer.colorArgb == 0),
      isTrue,
    );
  });

  test('old favorites and wardrobe records still load without details', () {
    final json = _looks().first.toJson()
      ..remove('topDetails')
      ..remove('pantsDetails');
    final legacy = OutfitRecommendation.fromJson(json);
    expect(legacy.topDetails.isSpecified, isFalse);
    expect(legacy.pantsDetails.isSpecified, isFalse);
    final wardrobe = _owned(legacy, const GarmentDetails()).toJson()
      ..remove('details');
    expect(WardrobeItem.fromJson(wardrobe).details.isSpecified, isFalse);
    expect(
      GarmentDetails.fromJson({
        'type': 'futureType',
        'pattern': 'futurePattern',
        'accentColors': [
          null,
          {'argb': 'bad'},
          {'name': 'Cream', 'argb': _cream.argb},
        ],
      }).accentColors,
      hasLength(1),
    );
    expect(GarmentDetails.fromJson(null).pattern, GarmentPattern.solid);
  });

  test('favorites and wardrobe round-trip details through JSON', () {
    final look = _looks().first;
    final restored = OutfitRecommendation.fromJson(
      jsonDecode(jsonEncode(look.toJson())) as Map<String, dynamic>,
    );
    expect(restored.topDetails.signature, look.topDetails.signature);
    expect(restored.pantsDetails.signature, look.pantsDetails.signature);
    expect(restored.id, look.id);
    final owned = _owned(look, _checkedFlannel);
    expect(
      WardrobeItem.fromJson(
        jsonDecode(jsonEncode(owned.toJson())) as Map<String, dynamic>,
      ).details.signature,
      _checkedFlannel.signature,
    );
  });

  test('stable IDs distinguish type pattern and accent palettes', () {
    final solid = _looks(
      details: const GarmentDetails(type: GarmentType.shirt),
    ).first.id;
    final checked = _looks(
      details: const GarmentDetails(
        type: GarmentType.shirt,
        pattern: GarmentPattern.checks,
      ),
    ).first.id;
    final flannel = _looks().first.id;
    expect({solid, checked, flannel}, hasLength(3));
    final reordered = _looks(
      details: const GarmentDetails(
        type: GarmentType.flannel,
        pattern: GarmentPattern.checks,
        accentColors: [_cream, _navy],
      ),
    ).first.id;
    expect(reordered, flannel);
    expect(_looks().first.id, flannel);
    final legacy = _looks(details: const GarmentDetails()).first;
    expect(legacy.id, isNot(contains('-garment-')));
  });

  test('wardrobe coverage rejects known pattern and garment mismatches', () {
    final look = _looks().first;
    final matching = _owned(look, look.pantsDetails);
    expect(const WardrobeStylist().coverage(look, [matching]), 1);
    final wrongPattern = _owned(
      look,
      look.pantsDetails.copyWith(pattern: GarmentPattern.checks),
    );
    expect(const WardrobeStylist().coverage(look, [wrongPattern]), 0);
    final wrongType = _owned(
      look,
      const GarmentDetails(type: GarmentType.shorts),
    );
    expect(const WardrobeStylist().coverage(look, [wrongType]), 0);
    final oldColorOnly = _owned(look, const GarmentDetails());
    expect(const WardrobeStylist().coverage(look, [oldColorOnly]), 1);
    final pantsFirst = _looks(
      piece: StartingPiece.pants,
      details: const GarmentDetails(type: GarmentType.jeans),
    ).first;
    final top = WardrobeItem(
      id: 'tee',
      name: 'My tee',
      colorName: pantsFirst.shirt.name,
      colorArgb: pantsFirst.shirt.argb,
      category: WardrobeCategory.shirt,
      details: pantsFirst.topDetails,
    );
    expect(
      const WardrobeStylist().matchesFor(pantsFirst, [top]).keys,
      contains(WardrobeCategory.shirt),
    );
  });

  test(
    'local preference model learns patterns independently of labels and IDs',
    () {
      final base = _looks().first;
      OutfitRecommendation withPattern(String id, GarmentPattern pattern) =>
          OutfitRecommendation.fromJson({
            ...base.toJson(),
            'id': id,
            'topDetails': GarmentDetails(
              type: GarmentType.flannel,
              pattern: pattern,
            ).toJson(),
          });
      final checks = withPattern('training-checks', GarmentPattern.checks);
      final stripes = withPattern('training-stripes', GarmentPattern.stripes);
      const model = AdaptiveStylist();
      final history = model.record(
        model.record([], checks, StyleFeedback.like),
        stripes,
        StyleFeedback.dislike,
      );
      final unseenChecks = withPattern('unseen-checks', GarmentPattern.checks);
      final unseenStripes = withPattern(
        'unseen-stripes',
        GarmentPattern.stripes,
      );
      expect(
        model.preferenceScore(unseenChecks, history),
        greaterThan(model.preferenceScore(unseenStripes, history)),
      );
    },
  );
}

WardrobeItem _owned(OutfitRecommendation outfit, GarmentDetails details) =>
    WardrobeItem(
      id: 'owned-pants',
      name: 'My pants',
      colorName: outfit.pants.colorName,
      colorArgb: outfit.pants.colorArgb,
      category: WardrobeCategory.pants,
      details: details,
    );
