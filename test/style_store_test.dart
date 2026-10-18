import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/models/learning_models.dart';
import 'package:thread_style/models/planner_models.dart';
import 'package:thread_style/models/wardrobe_models.dart';
import 'package:thread_style/models/weather_models.dart';
import 'package:thread_style/models/style_discovery_models.dart';
import 'package:thread_style/services/style_engine.dart';
import 'package:thread_style/services/style_store.dart';

void main() {
  const profile = StyleProfile(
    heightCm: 181,
    bodyShape: BodyShape.broadShoulders,
    undertone: Undertone.warm,
    useSkinTone: true,
  );
  final outfits = const StyleEngine().generate(
    shirt: ShirtColor.presets.first,
    occasion: Occasion.office,
    profile: profile,
  );

  test('new installation has an unconfigured default profile', () {
    final result = StyleStore.decode();
    expect(result.profile.heightCm, 175);
    expect(result.configured, isFalse);
    expect(result.saved, isEmpty);
    expect(result.wardrobe, isEmpty);
    expect(result.direction, StyleDirection.everyday);
    expect(result.recoveryMessage, isNull);
  });

  test('valid profile and saved looks restore without a recovery message', () {
    final result = StyleStore.decode(
      profileRaw: jsonEncode(profile.toJson()),
      savedRaw: jsonEncode(outfits.map((outfit) => outfit.toJson()).toList()),
    );
    expect(result.profile.toJson(), profile.toJson());
    expect(result.configured, isTrue);
    expect(
      result.saved.map((outfit) => outfit.id),
      outfits.map((outfit) => outfit.id),
    );
    expect(result.recoveryMessage, isNull);
  });

  test('malformed profile JSON does not discard valid saved looks', () {
    final result = StyleStore.decode(
      profileRaw: '{invalid',
      savedRaw: jsonEncode([outfits.first.toJson()]),
    );
    expect(result.configured, isFalse);
    expect(result.profile.heightCm, 175);
    expect(result.saved.single.id, outfits.first.id);
    expect(result.recoveryMessage, contains('1 saved look was restored'));
  });

  test('malformed saved collection does not discard the profile', () {
    for (final invalidCollection in ['[invalid', '{}', 'null', '123']) {
      final result = StyleStore.decode(
        profileRaw: jsonEncode(profile.toJson()),
        savedRaw: invalidCollection,
      );
      expect(result.configured, isTrue);
      expect(result.profile.toJson(), profile.toJson());
      expect(result.saved, isEmpty);
      expect(
        result.recoveryMessage,
        contains('Your style profile was restored'),
      );
    }
  });

  test(
    'malformed individual entries are skipped while valid order is retained',
    () {
      final result = StyleStore.decode(
        profileRaw: jsonEncode(profile.toJson()),
        savedRaw: jsonEncode([
          outfits[0].toJson(),
          {'id': 'incomplete'},
          null,
          7,
          outfits[2].toJson(),
        ]),
      );
      expect(result.configured, isTrue);
      expect(result.saved.map((outfit) => outfit.id), [
        outfits[0].id,
        outfits[2].id,
      ]);
      expect(result.recoveryMessage, contains('2 saved looks were restored'));
    },
  );

  test('incorrect profile field types recover without throwing', () {
    final result = StyleStore.decode(
      profileRaw: jsonEncode({'heightCm': 'tall'}),
      savedRaw: '[]',
    );
    expect(result.configured, isFalse);
    expect(result.profile.heightCm, 175);
    expect(result.saved, isEmpty);
    expect(result.recoveryMessage, contains('You can still create outfits'));
  });

  test('feedback, plans, wardrobe, direction and weather restore together', () {
    final feedback = StyleFeedbackEntry(
      outfit: outfits.first,
      feedback: StyleFeedback.like,
      updatedAt: DateTime.utc(2026, 10, 18),
    );
    final plan = PlannedOutfit(
      id: 'p1',
      outfit: outfits.first,
      date: DateTime(2026, 10, 20),
      note: 'Dinner',
    );
    const item = WardrobeItem(
      id: 'w1',
      name: 'Sage shirt',
      colorName: 'Sage',
      colorArgb: 0xFF9BAE98,
      category: WardrobeCategory.shirt,
    );
    final weather = WeatherSnapshot(
      location: const CityLocation(
        name: 'Chennai',
        latitude: 13.08,
        longitude: 80.27,
      ),
      temperatureC: 30,
      apparentTemperatureC: 32,
      windKmh: 12,
      precipitationMm: 0,
      weatherCode: 1,
      fetchedAt: DateTime.utc(2026, 10, 18, 12),
    );
    final result = StyleStore.decode(
      feedbackRaw: jsonEncode([feedback.toJson()]),
      plansRaw: jsonEncode([plan.toJson()]),
      wardrobeRaw: jsonEncode([item.toJson()]),
      directionRaw: StyleDirection.preppy.name,
      weatherRaw: jsonEncode(weather.toJson()),
    );
    expect(result.feedback.single.toJson(), feedback.toJson());
    expect(result.plans.single.toJson(), plan.toJson());
    expect(result.wardrobe.single.toJson(), item.toJson());
    expect(result.direction, StyleDirection.preppy);
    expect(result.weather?.toJson(), weather.toJson());
    expect(result.recoveryMessage, isNull);
  });

  test('wardrobe corruption and duplicate IDs retain other valid records', () {
    const shirt = WardrobeItem(
      id: 'shirt',
      name: 'Sage shirt',
      colorName: 'Sage',
      colorArgb: 0xFF9BAE98,
      category: WardrobeCategory.shirt,
    );
    const shoes = WardrobeItem(
      id: 'shoes',
      name: 'White sneakers',
      colorName: 'White',
      colorArgb: 0xFFF4F2EB,
      category: WardrobeCategory.shoes,
    );
    final result = StyleStore.decode(
      wardrobeRaw: jsonEncode([
        shirt.toJson(),
        {'id': 'broken'},
        shirt.toJson(),
        shoes.toJson(),
      ]),
      savedRaw: jsonEncode([outfits.first.toJson()]),
      directionRaw: StyleDirection.smartCasual.name,
    );
    expect(result.wardrobe.map((item) => item.id), ['shirt', 'shoes']);
    expect(result.saved.single.id, outfits.first.id);
    expect(result.direction, StyleDirection.smartCasual);
    expect(result.recoveryMessage, isNotNull);
  });

  test(
    'invalid plan dates and duplicates do not move or duplicate valid plans',
    () {
      final plan = PlannedOutfit(
        id: 'p1',
        outfit: outfits.first,
        date: DateTime(2026, 10, 20),
      );
      final result = StyleStore.decode(
        plansRaw: jsonEncode([
          {...plan.toJson(), 'id': 'invalid', 'date': '2026-02-30'},
          plan.toJson(),
          plan.toJson(),
        ]),
      );
      expect(result.plans.single.id, 'p1');
      expect(result.plans.single.date, DateTime(2026, 10, 20));
      expect(result.recoveryMessage, isNotNull);
    },
  );

  test(
    'unknown style directions fall back without losing a valid wardrobe',
    () {
      const item = WardrobeItem(
        id: 'w1',
        name: 'Sage shirt',
        colorName: 'Sage',
        colorArgb: 0xFF9BAE98,
        category: WardrobeCategory.shirt,
      );
      final result = StyleStore.decode(
        directionRaw: 'future-style',
        wardrobeRaw: jsonEncode([item.toJson()]),
      );
      expect(result.direction, StyleDirection.everyday);
      expect(result.wardrobe.single.id, item.id);
      expect(result.recoveryMessage, isNotNull);
    },
  );
}
