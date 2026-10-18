import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/style_models.dart';
import '../models/learning_models.dart';
import '../models/planner_models.dart';
import '../models/weather_models.dart';
import '../models/wardrobe_models.dart';
import '../models/style_discovery_models.dart';

class StoredStyle {
  const StoredStyle({
    this.profile = const StyleProfile(),
    this.configured = false,
    this.saved = const [],
    this.feedback = const [],
    this.plans = const [],
    this.wardrobe = const [],
    this.direction = StyleDirection.everyday,
    this.weather,
    this.recoveryMessage,
  });
  final StyleProfile profile;
  final bool configured;
  final List<OutfitRecommendation> saved;
  final List<StyleFeedbackEntry> feedback;
  final List<PlannedOutfit> plans;
  final List<WardrobeItem> wardrobe;
  final StyleDirection direction;
  final WeatherSnapshot? weather;
  final String? recoveryMessage;
}

class StyleStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static const _profileKey = 'thread.profile.v1';
  static const _savedKey = 'thread.saved.v1';
  static const _feedbackKey = 'thread.feedback.v1';
  static const _plansKey = 'thread.plans.v1';
  static const _weatherKey = 'thread.weather.v1';
  static const _wardrobeKey = 'thread.wardrobe.v1';
  static const _directionKey = 'thread.direction.v1';

  Future<StoredStyle> load() async {
    final profileRaw = await _preferences.getString(_profileKey);
    final savedRaw = await _preferences.getString(_savedKey);
    final feedbackRaw = await _preferences.getString(_feedbackKey);
    final plansRaw = await _preferences.getString(_plansKey);
    final weatherRaw = await _preferences.getString(_weatherKey);
    final wardrobeRaw = await _preferences.getString(_wardrobeKey);
    final directionRaw = await _preferences.getString(_directionKey);
    return decode(
      profileRaw: profileRaw,
      savedRaw: savedRaw,
      feedbackRaw: feedbackRaw,
      plansRaw: plansRaw,
      weatherRaw: weatherRaw,
      wardrobeRaw: wardrobeRaw,
      directionRaw: directionRaw,
    );
  }

  /// Restores valid records independently. Decoding never rewrites storage, so
  /// a damaged record does not silently replace an existing saved collection.
  static StoredStyle decode({
    String? profileRaw,
    String? savedRaw,
    String? feedbackRaw,
    String? plansRaw,
    String? weatherRaw,
    String? wardrobeRaw,
    String? directionRaw,
  }) {
    var profile = const StyleProfile();
    var configured = false;
    var hadRecovery = false;
    final saved = <OutfitRecommendation>[];
    WeatherSnapshot? weather;
    List<T> recoverList<T>(
      String? raw,
      T Function(Map<String, dynamic>) decode, {
      String Function(T)? identity,
    }) {
      final values = <T>[];
      final ids = <String>{};
      if (raw == null) return values;
      try {
        for (final record in jsonDecode(raw) as List<dynamic>) {
          try {
            final value = decode(record as Map<String, dynamic>);
            if (identity != null && !ids.add(identity(value))) {
              hadRecovery = true;
              continue;
            }
            values.add(value);
          } catch (_) {
            hadRecovery = true;
          }
        }
      } catch (_) {
        hadRecovery = true;
      }
      return values;
    }

    final feedback = recoverList(feedbackRaw, StyleFeedbackEntry.fromJson);
    final plans = recoverList(
      plansRaw,
      PlannedOutfit.fromJson,
      identity: (plan) => plan.id,
    );
    final wardrobe = recoverList(
      wardrobeRaw,
      WardrobeItem.fromJson,
      identity: (item) => item.id,
    );
    var direction = StyleDirection.everyday;
    if (directionRaw != null) {
      final matches = StyleDirection.values.where(
        (value) => value.name == directionRaw,
      );
      if (matches.isEmpty) {
        hadRecovery = true;
      } else {
        direction = matches.single;
      }
    }
    if (weatherRaw != null) {
      try {
        weather = WeatherSnapshot.fromJson(
          jsonDecode(weatherRaw) as Map<String, dynamic>,
        );
      } catch (_) {
        hadRecovery = true;
      }
    }

    if (profileRaw != null) {
      try {
        profile = StyleProfile.fromJson(
          jsonDecode(profileRaw) as Map<String, dynamic>,
        );
        configured = true;
      } catch (_) {
        hadRecovery = true;
      }
    }

    if (savedRaw != null) {
      try {
        final records = jsonDecode(savedRaw) as List<dynamic>;
        for (final record in records) {
          try {
            saved.add(
              OutfitRecommendation.fromJson(record as Map<String, dynamic>),
            );
          } catch (_) {
            hadRecovery = true;
          }
        }
      } catch (_) {
        hadRecovery = true;
      }
    }

    final recovered = <String>[
      if (configured) 'Your style profile was restored.',
      if (saved.isNotEmpty)
        '${saved.length} saved ${saved.length == 1 ? 'look was' : 'looks were'} restored.',
      if (!configured && saved.isEmpty) 'You can still create outfits.',
    ];
    return StoredStyle(
      profile: profile,
      configured: configured,
      saved: List<OutfitRecommendation>.unmodifiable(saved),
      feedback: List.unmodifiable(feedback),
      plans: List.unmodifiable(plans),
      wardrobe: List.unmodifiable(wardrobe),
      direction: direction,
      weather: weather,
      recoveryMessage: hadRecovery
          ? 'Some saved data could not be read. ${recovered.join(' ')}'
          : null,
    );
  }

  Future<void> saveProfile(StyleProfile profile) =>
      _preferences.setString(_profileKey, jsonEncode(profile.toJson()));
  Future<void> saveOutfits(List<OutfitRecommendation> outfits) =>
      _preferences.setString(
        _savedKey,
        jsonEncode(outfits.map((outfit) => outfit.toJson()).toList()),
      );
  Future<void> saveFeedback(List<StyleFeedbackEntry> feedback) =>
      _preferences.setString(
        _feedbackKey,
        jsonEncode(feedback.map((entry) => entry.toJson()).toList()),
      );
  Future<void> savePlans(List<PlannedOutfit> plans) => _preferences.setString(
    _plansKey,
    jsonEncode(plans.map((entry) => entry.toJson()).toList()),
  );
  Future<void> saveWeather(WeatherSnapshot? weather) => weather == null
      ? _preferences.remove(_weatherKey)
      : _preferences.setString(_weatherKey, jsonEncode(weather.toJson()));
  Future<void> saveWardrobe(List<WardrobeItem> items) => _preferences.setString(
    _wardrobeKey,
    jsonEncode(items.map((item) => item.toJson()).toList()),
  );
  Future<void> saveDirection(StyleDirection direction) =>
      _preferences.setString(_directionKey, direction.name);
  Future<void> clear() => _preferences.clear(
    allowList: {
      _profileKey,
      _savedKey,
      _feedbackKey,
      _plansKey,
      _weatherKey,
      _wardrobeKey,
      _directionKey,
    },
  );
}
