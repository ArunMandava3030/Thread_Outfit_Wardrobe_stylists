import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/models/weather_models.dart';
import 'package:thread_style/services/style_engine.dart';
import 'package:thread_style/services/weather_stylist.dart';

WeatherSnapshot _weather({
  double feelsLike = 22,
  double rain = 0,
  double wind = 5,
  int code = 0,
  bool stale = false,
}) => WeatherSnapshot(
  location: const CityLocation(name: 'Test city', latitude: 10, longitude: 20),
  temperatureC: feelsLike,
  apparentTemperatureC: feelsLike,
  windKmh: wind,
  precipitationMm: rain,
  weatherCode: code,
  fetchedAt: DateTime.now().toUtc().subtract(Duration(hours: stale ? 2 : 0)),
);

List<OutfitRecommendation> _outfits(
  Occasion occasion, {
  bool includeLayer = true,
}) => const StyleEngine().generate(
  shirt: ShirtColor.presets.first,
  occasion: occasion,
  profile: const StyleProfile(),
  includeLayer: includeLayer,
);

void main() {
  const stylist = WeatherStylist();

  test(
    'warm weather changes fabrics while retaining office dress and colors',
    () {
      final original = _outfits(Occasion.office);
      final adapted = stylist.adapt(
        original,
        _weather(feelsLike: 33),
        includeLayer: true,
      );
      for (var i = 0; i < adapted.length; i++) {
        expect(adapted[i].pants.title, contains('cotton-linen trousers'));
        expect(adapted[i].layer.title, 'Airy unlined blazer');
        expect(adapted[i].shoes.title, original[i].shoes.title);
        expect(adapted[i].pants.colorArgb, original[i].pants.colorArgb);
        expect(adapted[i].shirt, original[i].shirt);
        expect(adapted[i].occasion, Occasion.office);
        expect(adapted[i].reasons.join(' '), contains('workplace dress code'));
        expect(adapted[i].description, contains('warm'));
        expect(adapted[i].id, isNot(original[i].id));
      }
    },
  );

  test(
    'rain replaces suede, sandals and canvas with water-resistant closed shoes',
    () {
      for (final occasion in [Occasion.date, Occasion.beach, Occasion.casual]) {
        final adapted = stylist.adapt(
          _outfits(occasion),
          _weather(rain: 2),
          includeLayer: true,
        );
        for (final outfit in adapted) {
          expect(outfit.pants.title, contains('Quick-drying'));
          expect(outfit.shoes.title, contains('Water-resistant'));
          expect(outfit.layer.title, 'Lightweight rain shell');
          expect(outfit.reasons.join(' '), contains('Wet conditions'));
          expect(outfit.occasion, occasion);
        }
      }
    },
  );

  test(
    'weather codes adapt for showers even when instantaneous rain is zero',
    () {
      final adapted = stylist.adapt(
        _outfits(Occasion.casual),
        _weather(code: 80),
        includeLayer: true,
      );
      expect(adapted.first.layer.title, 'Lightweight rain shell');
    },
  );

  test(
    'cold beach outfits replace shorts and sandals and remove warm-weather advice',
    () {
      final adapted = stylist.adapt(
        _outfits(Occasion.beach),
        _weather(feelsLike: 5),
        includeLayer: true,
      );
      for (final outfit in adapted) {
        expect(outfit.pants.title, 'Heavier straight-leg trousers');
        expect(outfit.shoes.title, 'Closed leather boots');
        expect(outfit.layer.title, 'Insulated jacket');
        expect(
          outfit.reasons.join(' '),
          isNot(contains('warm, easy beach day')),
        );
        expect(outfit.fitAdvice, isNot(contains('for warm weather')));
      }
    },
  );

  test(
    'optional layers stay off in all conditions with appropriate advice',
    () {
      for (final weather in [
        _weather(feelsLike: 32),
        _weather(feelsLike: 4),
        _weather(rain: 3),
        _weather(wind: 35),
      ]) {
        final adapted = stylist.adapt(
          _outfits(Occasion.casual, includeLayer: false),
          weather,
          includeLayer: false,
        );
        for (final outfit in adapted) {
          expect(outfit.layer.colorArgb, 0);
          expect(outfit.layer.title, 'Skip the layer');
          expect(outfit.layer.colorName, 'None');
        }
      }
      final cold = stylist.adapt(
        _outfits(Occasion.casual, includeLayer: false),
        _weather(feelsLike: 4),
        includeLayer: false,
      );
      expect(
        cold.first.reasons.join(' '),
        contains('Consider bringing a warm layer'),
      );
    },
  );

  test(
    'motorcycle protection survives rain, cold, wind, heat and layers disabled',
    () {
      final original = _outfits(Occasion.bikeRide, includeLayer: false);
      for (final weather in [
        _weather(feelsLike: 35),
        _weather(feelsLike: 1, rain: 3, wind: 40),
      ]) {
        final adapted = stylist.adapt(original, weather, includeLayer: false);
        for (var i = 0; i < adapted.length; i++) {
          expect(adapted[i].pants, original[i].pants);
          expect(adapted[i].shoes, original[i].shoes);
          expect(adapted[i].layer, original[i].layer);
          expect(adapted[i].safetyNote, original[i].safetyNote);
          expect(adapted[i].fitAdvice, original[i].fitAdvice);
          expect(adapted[i].id, original[i].id);
        }
      }
    },
  );

  test(
    'stale weather and mild weather leave original recommendations untouched',
    () {
      final original = _outfits(Occasion.casual);
      expect(
        identical(
          stylist.adapt(
            original,
            _weather(feelsLike: 2, rain: 10, stale: true),
            includeLayer: true,
          ),
          original,
        ),
        isTrue,
      );
      expect(
        identical(
          stylist.adapt(original, _weather(), includeLayer: true),
          original,
        ),
        isTrue,
      );
    },
  );

  test(
    'saved identities differ by actual weather clothes and stay stable on refresh',
    () {
      final original = _outfits(Occasion.date);
      final warm = stylist
          .adapt(original, _weather(feelsLike: 31), includeLayer: true)
          .first;
      final warmRefresh = stylist
          .adapt(original, _weather(feelsLike: 32), includeLayer: true)
          .first;
      final rainy = stylist
          .adapt(original, _weather(rain: 5), includeLayer: true)
          .first;
      final coldRain = stylist
          .adapt(original, _weather(feelsLike: 2, rain: 5), includeLayer: true)
          .first;
      expect(warm.id, warmRefresh.id);
      expect({original.first.id, warm.id, rainy.id, coldRain.id}, hasLength(4));
    },
  );
}
