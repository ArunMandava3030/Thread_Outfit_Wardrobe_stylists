import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/style_discovery_models.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/models/weather_models.dart';
import 'package:thread_style/services/style_direction_stylist.dart';
import 'package:thread_style/services/style_engine.dart';
import 'package:thread_style/services/weather_stylist.dart';

const _engine = StyleEngine();
const _anchor = ShirtColor(name: 'My indigo', argb: 0xFF273C91);
const _match = ShirtColor(name: 'Custom cream', argb: 0xFFE6DCC2);
const _profile = StyleProfile(
  heightCm: 164,
  bodyShape: BodyShape.broadShoulders,
  skinToneArgb: 0xFF86563D,
  undertone: Undertone.warm,
  useSkinTone: true,
);

WeatherSnapshot _weather({double temperature = 22, double rain = 0}) =>
    WeatherSnapshot(
      location: const CityLocation(name: 'Test', latitude: 10, longitude: 20),
      temperatureC: temperature,
      apparentTemperatureC: temperature,
      windKmh: 8,
      precipitationMm: rain,
      weatherCode: rain > 0 ? 61 : 0,
      fetchedAt: DateTime.now().toUtc(),
    );

void main() {
  test('both chosen colors survive every occasion, direction and weather', () {
    for (final startingPiece in StartingPiece.values) {
      for (final occasion in Occasion.values) {
        final originals = _engine.generateForItem(
          startingPiece: startingPiece,
          color: _anchor,
          matchingColor: _match,
          occasion: occasion,
          profile: _profile,
        );
        expect(originals, hasLength(3));
        expect(originals.map((item) => item.id).toSet(), hasLength(3));
        for (final direction in StyleDirection.values) {
          final styled = const StyleDirectionStylist().adapt(
            originals,
            direction,
          );
          for (final weather in [
            _weather(),
            _weather(temperature: 34),
            _weather(temperature: 5),
            _weather(rain: 4),
          ]) {
            final adapted = const WeatherStylist().adapt(
              styled,
              weather,
              includeLayer: true,
            );
            for (final look in adapted) {
              final top = startingPiece == StartingPiece.shirt
                  ? _anchor
                  : _match;
              final bottom = startingPiece == StartingPiece.pants
                  ? _anchor
                  : _match;
              expect(look.shirt.toJson(), top.toJson());
              expect(look.pants.colorArgb, bottom.argb);
              expect(look.pants.colorName, bottom.name);
              expect(look.startingPiece, startingPiece);
              expect(look.occasion, occasion);
              if (startingPiece == StartingPiece.pants) {
                expect(look.pants.title, 'Your pants');
                expect(look.shirtTitle, isNot('Your shirt'));
              } else {
                expect(look.shirtTitle, 'Your shirt');
              }
            }
          }
        }
      }
    }
  });

  test('pants-first without a selected match offers three different tops', () {
    final looks = _engine.generateForItem(
      startingPiece: StartingPiece.pants,
      color: _anchor,
      occasion: Occasion.date,
      profile: _profile,
    );
    expect(looks.map((item) => item.shirt.argb).toSet(), hasLength(3));
    expect(looks.map((item) => item.pants.colorArgb).toSet(), {_anchor.argb});
    expect(looks.first.reasons.first, contains('pants you are keeping'));
    expect(looks.first.fitAdvice, contains('high-rise'));
    expect(looks.first.fitAdvice, contains('unpadded shoulders'));
    expect(looks.first.reasons.join(' '), contains('sampled tone'));
  });

  test(
    'matching suggestions use RGB and profile contrast is opt-in for tops',
    () {
      List<int> matches(ShirtColor color, {StyleProfile? profile}) => _engine
          .matchingColors(
            startingPiece: StartingPiece.pants,
            color: color,
            profile: profile,
          )
          .map((item) => item.argb)
          .toList();
      expect(
        matches(_anchor),
        matches(const ShirtColor(name: 'Sample', argb: 0xFF273C91)),
      );
      expect(matches(_anchor), isNot(matches(ShirtColor.presets.first)));
      final deep = matches(
        _anchor,
        profile: const StyleProfile(
          useSkinTone: true,
          skinToneArgb: 0xFF69432E,
        ),
      );
      final light = matches(
        _anchor,
        profile: const StyleProfile(
          useSkinTone: true,
          skinToneArgb: 0xFFF1D5BE,
        ),
      );
      expect(deep.first, isNot(light.first));
      expect(deep.toSet(), light.toSet());
      expect(
        matches(_anchor, profile: const StyleProfile(skinToneArgb: 0xFF69432E)),
        matches(_anchor),
      );
    },
  );

  test(
    'celebration outfits have occasion-specific layers and respect the toggle',
    () {
      final party = _engine.generateForItem(
        startingPiece: StartingPiece.pants,
        color: _anchor,
        matchingColor: _match,
        occasion: Occasion.party,
        profile: _profile,
      );
      final special = _engine.generateForItem(
        startingPiece: StartingPiece.pants,
        color: _anchor,
        matchingColor: _match,
        occasion: Occasion.special,
        profile: _profile,
      );
      expect(party.first.shirtTitle, 'Textured evening shirt');
      expect(party.first.layer.title, contains('evening blazer'));
      expect(special.first.shirtTitle, 'Crisp dress shirt');
      expect(special.first.layer.title, contains('single-breasted blazer'));
      expect(
        special.first.reasons.join(' '),
        contains('invitation dress code'),
      );
      for (final direction in StyleDirection.values) {
        final styled = const StyleDirectionStylist().adapt(special, direction);
        expect(styled.first.shirtTitle, contains('dress shirt'));
        expect(styled.first.layer.title.toLowerCase(), contains('blazer'));
      }
      final noLayer = _engine.generateForItem(
        startingPiece: StartingPiece.shirt,
        color: _anchor,
        matchingColor: _match,
        occasion: Occasion.party,
        profile: _profile,
        includeLayer: false,
      );
      expect(noLayer.every((look) => look.layer.colorArgb == 0), isTrue);
    },
  );

  test(
    'pants-first riding does not claim an unknown existing item is protective',
    () {
      final looks = _engine.generateForItem(
        startingPiece: StartingPiece.pants,
        color: _anchor,
        occasion: Occasion.bikeRide,
        profile: _profile,
        includeLayer: false,
      );
      for (final look in looks) {
        expect(look.pants.title, 'Your pants');
        expect(look.reasons.join(' '), contains('only if they are certified'));
        expect(look.layer.title, contains('Certified armored'));
        expect(look.shoes.title, contains('motorcycle boots'));
        expect(
          look.safetyNote,
          contains('Ordinary fashion layers are not protective'),
        );
      }
    },
  );

  test('favorites persist the anchor, top title and selected colors', () {
    final original = _engine
        .generateForItem(
          startingPiece: StartingPiece.pants,
          color: _anchor,
          matchingColor: _match,
          occasion: Occasion.special,
          profile: _profile,
        )
        .first;
    final decoded = OutfitRecommendation.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.toJson(), original.toJson());
    final legacy = original.toJson()
      ..remove('startingPiece')
      ..remove('shirtTitle');
    final oldFavorite = OutfitRecommendation.fromJson(legacy);
    expect(oldFavorite.startingPiece, StartingPiece.shirt);
    expect(oldFavorite.shirtTitle, 'Your shirt');
    expect(oldFavorite.pants.colorArgb, _anchor.argb);
  });

  test(
    'changed matching colors produce different stable favorite identities',
    () {
      String identity(ShirtColor match) => _engine
          .generateForItem(
            startingPiece: StartingPiece.shirt,
            color: _anchor,
            matchingColor: match,
            occasion: Occasion.date,
            profile: _profile,
          )
          .first
          .id;
      expect(identity(_match), identity(_match));
      expect(identity(_match), isNot(identity(ShirtColor.presets.first)));
    },
  );
}
