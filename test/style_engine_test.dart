import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/services/style_engine.dart';

void main() {
  const engine = StyleEngine();
  const defaultProfile = StyleProfile();

  group('StyleEngine', () {
    test('every occasion and shirt has three complete, distinct options', () {
      for (final occasion in Occasion.values) {
        for (final shirt in ShirtColor.presets) {
          final results = engine.generate(
            shirt: shirt,
            occasion: occasion,
            profile: defaultProfile,
          );
          expect(results, hasLength(3));
          expect(results.map((item) => item.id).toSet(), hasLength(3));
          expect(
            results.map((item) => item.pants.colorArgb).toSet(),
            hasLength(3),
          );
          for (final result in results) {
            expect(result.occasion, occasion);
            expect(result.shirt.argb, shirt.argb);
            expect(result.title, isNotEmpty);
            expect(result.pants.title, isNotEmpty);
            expect(result.shoes.title, isNotEmpty);
            expect(result.layer.title, isNotEmpty);
            expect(result.reasons.length, greaterThanOrEqualTo(3));
            expect(result.fitAdvice, isNotEmpty);
          }
        }
      }
    });

    test('shirt RGB changes the complementary palette', () {
      List<int> palette(ShirtColor shirt) => engine
          .generate(
            shirt: shirt,
            occasion: Occasion.casual,
            profile: defaultProfile,
          )
          .map((outfit) => outfit.pants.colorArgb)
          .toList();
      final sage = ShirtColor.presets.first;
      final navy = ShirtColor.presets.firstWhere(
        (color) => color.name == 'Navy',
      );
      final black = ShirtColor.presets.firstWhere(
        (color) => color.name == 'Black',
      );
      expect(palette(sage), isNot(equals(palette(navy))));
      expect(palette(black), isNot(equals(palette(navy))));
      expect(
        palette(ShirtColor(name: 'Camera sample', argb: sage.argb)),
        palette(sage),
      );
    });

    test('height and selected proportions influence fit advice', () {
      String advice(StyleProfile profile) => engine
          .generate(
            shirt: ShirtColor.presets.first,
            occasion: Occasion.office,
            profile: profile,
          )
          .first
          .fitAdvice;

      final shorter = advice(const StyleProfile(heightCm: 158));
      final taller = advice(const StyleProfile(heightCm: 193));
      expect(shorter, isNot(taller));
      expect(shorter, contains('high-rise'));
      expect(taller, contains('sleeve and trouser length'));
      expect(
        advice(const StyleProfile(bodyShape: BodyShape.broadShoulders)),
        contains('unpadded shoulders'),
      );
      expect(
        advice(const StyleProfile(bodyShape: BodyShape.widerHips)),
        contains('hip and thigh'),
      );
      expect(
        advice(const StyleProfile(bodyShape: BodyShape.fullerMidsection)),
        contains('waistband'),
      );
    });

    test('tone personalization is opt-in and permits all shirt colors', () {
      const profile = StyleProfile(
        skinToneArgb: 0xFFB99578,
        undertone: Undertone.warm,
      );
      List<OutfitRecommendation> generate(StyleProfile profile) =>
          engine.generate(
            shirt: ShirtColor.presets.first,
            occasion: Occasion.date,
            profile: profile,
          );
      final optedOut = generate(profile);
      final optedIn = generate(profile.copyWith(useSkinTone: true));
      expect(optedOut.first.reasons.join(' '), isNot(contains('sampled tone')));
      expect(optedIn.first.reasons.join(' '), contains('sampled tone'));
      expect(optedIn.first.reasons.join(' '), contains('tan or cream'));
      expect(optedIn.first.shirt.argb, optedOut.first.shirt.argb);
      expect(
        optedIn.first.layer.colorArgb,
        isNot(optedOut.first.layer.colorArgb),
      );
      expect(optedIn, hasLength(3));
    });

    test(
      'warm and cool preferences vary accents without excluding a shirt',
      () {
        OutfitRecommendation generate(Undertone undertone) => engine
            .generate(
              shirt: ShirtColor.presets.first,
              occasion: Occasion.date,
              profile: StyleProfile(useSkinTone: true, undertone: undertone),
            )
            .first;
        final warm = generate(Undertone.warm);
        final cool = generate(Undertone.cool);
        expect(warm.layer.colorArgb, isNot(cool.layer.colorArgb));
        expect(warm.shoes.colorArgb, isNot(cool.shoes.colorArgb));
        expect(warm.id, isNot(cool.id));
        expect(warm.shirt.argb, cool.shirt.argb);
        expect(warm.pants.colorArgb, cool.pants.colorArgb);
      },
    );

    test(
      'sampled skin tone can add a contrast alternative without an undertone guess',
      () {
        OutfitRecommendation contrastLook(int tone) => engine
            .generate(
              shirt: ShirtColor.presets.first,
              occasion: Occasion.casual,
              profile: StyleProfile(useSkinTone: true, skinToneArgb: tone),
            )
            .last;
        final deepTone = contrastLook(0xFF69432E);
        final lightTone = contrastLook(0xFFF1D5BE);
        expect(deepTone.layer.colorArgb, isNot(lightTone.layer.colorArgb));
        expect(deepTone.shirt.argb, lightTone.shirt.argb);
        expect(
          deepTone.reasons.join(' '),
          contains('Try both a warm and a cool accent'),
        );
      },
    );

    test('optional layers can be omitted', () {
      final results = engine.generate(
        shirt: ShirtColor.presets.first,
        occasion: Occasion.casual,
        profile: defaultProfile,
        includeLayer: false,
      );
      for (final result in results) {
        expect(result.layer.colorArgb, 0);
        expect(result.layer.colorName, 'None');
        expect(result.safetyNote, isNull);
      }
    });

    test('motorbike suggestions keep protective gear when layers are off', () {
      final results = engine.generate(
        shirt: ShirtColor.presets.first,
        occasion: Occasion.bikeRide,
        profile: defaultProfile,
        includeLayer: false,
      );
      for (final result in results) {
        expect(result.layer.title.toLowerCase(), contains('certified armored'));
        expect(
          result.pants.title.toLowerCase(),
          contains('certified motorcycle'),
        );
        expect(result.shoes.title, contains('motorcycle boots'));
        expect(
          result.safetyNote,
          contains('Ordinary fashion layers are not protective'),
        );
        expect(result.fitAdvice, contains('seated riding position'));
      }
    });
  });

  group('Persistence models', () {
    test('profiles survive a JSON round trip including optional settings', () {
      const original = StyleProfile(
        heightCm: 182.5,
        bodyShape: BodyShape.broadShoulders,
        skinToneArgb: 0xFFB99578,
        undertone: Undertone.warm,
        useSkinTone: true,
      );
      final decoded = StyleProfile.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.toJson(), original.toJson());
      expect(
        decoded.copyWith(bodyShape: null, skinToneArgb: null).bodyShape,
        isNull,
      );
      expect(
        decoded.copyWith(bodyShape: null, skinToneArgb: null).skinToneArgb,
        isNull,
      );
      expect(decoded.copyWith(heightCm: 170).bodyShape, original.bodyShape);
    });

    test('a partial or older profile keeps useful defaults', () {
      final decoded = StyleProfile.fromJson({
        'bodyShape': 'removed-option',
        'undertone': 'unknown',
        'heightCm': -5,
      });
      expect(decoded.heightCm, 175);
      expect(decoded.bodyShape, isNull);
      expect(decoded.skinToneArgb, isNull);
      expect(decoded.undertone, Undertone.unsure);
      expect(decoded.useSkinTone, isFalse);
    });

    test('every recommendation survives JSON encoding and decoding', () {
      for (final occasion in Occasion.values) {
        final outfits = engine.generate(
          shirt: ShirtColor.presets.first,
          occasion: occasion,
          profile: defaultProfile,
        );
        for (final original in outfits) {
          final decoded = OutfitRecommendation.fromJson(
            jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
          );
          expect(decoded.toJson(), original.toJson());
        }
      }
    });

    test('hex omits alpha and preserves six characters', () {
      expect(
        const ShirtColor(name: 'Near black', argb: 0xFF00020A).hex,
        '#00020A',
      );
    });
  });
}
