import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thread_style/main.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/models/learning_models.dart';
import 'package:thread_style/models/planner_models.dart';
import 'package:thread_style/models/weather_models.dart';
import 'package:thread_style/models/wardrobe_models.dart';
import 'package:thread_style/models/style_discovery_models.dart';
import 'package:thread_style/services/style_store.dart';
import 'package:thread_style/services/style_engine.dart';
import 'package:thread_style/widgets/outfit_card.dart';

void main() {
  testWidgets(
    'likes persist after restart, can be undone, and learning resets independently',
    (tester) async {
      final store = _MemoryStyleStore(
        initial: const StoredStyle(configured: true),
      );
      await _pumpApp(tester, store: store, size: const Size(390, 844));
      await _generate(tester);
      final liked = tester
          .widget<OutfitCard>(find.byType(OutfitCard).first)
          .outfit;
      await _openDetails(tester);
      await _tapVisible(tester, find.byTooltip('Like this look').first);
      expect(store.snapshot.feedback.single.outfit.id, liked.id);
      expect(store.snapshot.feedback.single.feedback, StyleFeedback.like);
      await _restartApp(tester, store);
      await _openPersonalization(tester);
      expect(find.text('1 style preference learned.'), findsOneWidget);
      await _generate(tester);
      final restored = tester.widget<OutfitCard>(
        find.byWidgetPredicate(
          (widget) => widget is OutfitCard && widget.outfit.id == liked.id,
        ),
      );
      expect(restored.feedback, StyleFeedback.like);
      await _openDetails(tester);
      await _tapVisible(tester, find.byTooltip('Undo like'));
      expect(store.snapshot.feedback, isEmpty);
      await _openDetails(tester);
      await _tapVisible(tester, find.byTooltip('Dislike this look').first);
      expect(store.snapshot.feedback.single.feedback, StyleFeedback.dislike);
      await _tapVisible(tester, find.text('Favorite outfit').first);
      final savedId = store.snapshot.saved.single.id;
      await _openPersonalization(tester);
      await _tapVisible(tester, find.text('Reset learning'));
      expect(find.text('Reset style learning?'), findsOneWidget);
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Reset learning'),
      );
      expect(store.snapshot.feedback, isEmpty);
      expect(store.snapshot.saved.single.id, savedId);
      expect(store.snapshot.configured, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'planned outfit survives restart and can be edited and removed',
    (tester) async {
      final store = _MemoryStyleStore(
        initial: const StoredStyle(configured: true),
      );
      await _pumpApp(tester, store: store, size: const Size(390, 844));
      await _generate(tester);
      final outfit = tester
          .widget<OutfitCard>(find.byType(OutfitCard).first)
          .outfit;
      await _openDetails(tester);
      await _tapVisible(tester, find.text('Plan look').first);
      await tester.enterText(
        find.byKey(const Key('plan_note')),
        'Dinner with friends',
      );
      await _tapVisible(tester, find.byKey(const Key('save_plan')));
      expect(store.snapshot.plans.single.outfit.id, outfit.id);
      final planId = store.snapshot.plans.single.id;
      await _openMorePage(tester, 'Planner');
      expect(find.text('Dinner with friends'), findsOneWidget);
      await _restartApp(tester, store);
      await _openMorePage(tester, 'Planner');
      expect(find.text(outfit.title), findsOneWidget);
      expect(find.text('Dinner with friends'), findsOneWidget);
      await _tapVisible(tester, find.text('Edit plan'));
      await tester.enterText(
        find.byKey(const Key('plan_note')),
        'Dinner moved to 8',
      );
      await _tapVisible(tester, find.byKey(const Key('save_plan')));
      expect(store.snapshot.plans.single.id, planId);
      expect(store.snapshot.plans.single.note, 'Dinner moved to 8');
      await _tapVisible(tester, find.byTooltip('Remove plan'));
      expect(store.snapshot.plans, isEmpty);
      expect(find.text('Your calendar is a blank canvas.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'a wardrobe shirt persists and starts outfit suggestions in its color',
    (tester) async {
      final store = _MemoryStyleStore(
        initial: const StoredStyle(configured: true),
      );
      await _pumpApp(tester, store: store, size: const Size(390, 844));
      await _openMorePage(tester, 'Wardrobe');
      await _tapVisible(tester, find.byKey(const Key('add_wardrobe_item')));
      await tester.enterText(
        find.byKey(const Key('wardrobe_name')),
        'My navy linen shirt',
      );
      await _tapVisible(tester, find.byTooltip('Navy'));
      await _tapVisible(tester, find.byKey(const Key('save_wardrobe_item')));
      expect(store.snapshot.wardrobe.single.colorArgb, 0xFF25394F);
      expect(store.snapshot.configured, isTrue);
      await _restartApp(tester, store);
      await _openMorePage(tester, 'Wardrobe');
      expect(find.text('My navy linen shirt'), findsOneWidget);
      await _tapVisible(tester, find.text('Wear this shirt'));
      expect(find.byKey(const Key('studio_next')), findsOneWidget);
      await _generate(tester);
      expect(
        tester
            .widgetList<OutfitCard>(find.byType(OutfitCard))
            .map((card) => card.outfit.shirt.argb),
        everyElement(0xFF25394F),
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'clear all data removes profile, looks, learning, planner, wardrobe, direction and weather',
    (tester) async {
      final outfit = const StyleEngine()
          .generate(
            shirt: ShirtColor.presets.first,
            occasion: Occasion.office,
            profile: const StyleProfile(),
          )
          .first;
      final store = _MemoryStyleStore(
        initial: StoredStyle(
          configured: true,
          saved: [outfit],
          feedback: [
            StyleFeedbackEntry(
              outfit: outfit,
              feedback: StyleFeedback.like,
              updatedAt: DateTime.now(),
            ),
          ],
          plans: [
            PlannedOutfit(id: 'p1', outfit: outfit, date: DateTime.now()),
          ],
          wardrobe: const [
            WardrobeItem(
              id: 'w1',
              name: 'Sage shirt',
              colorName: 'Sage',
              colorArgb: 0xFF9BAE98,
              category: WardrobeCategory.shirt,
            ),
          ],
          direction: StyleDirection.preppy,
          weather: WeatherSnapshot(
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
            fetchedAt: DateTime.now(),
          ),
        ),
      );
      await _pumpApp(tester, store: store, size: const Size(390, 844));
      await _openMorePage(tester, 'My profile');
      await _tapVisible(tester, find.text('Clear all my Thread data'));
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Clear data'),
      );
      expect(store.snapshot.configured, isFalse);
      expect(store.snapshot.saved, isEmpty);
      expect(store.snapshot.feedback, isEmpty);
      expect(store.snapshot.plans, isEmpty);
      expect(store.snapshot.wardrobe, isEmpty);
      expect(store.snapshot.weather, isNull);
      expect(store.snapshot.direction, StyleDirection.everyday);
      await _restartApp(tester, store);
      await _openMorePage(tester, 'Planner');
      expect(find.text('Your calendar is a blank canvas.'), findsOneWidget);
      await _openMorePage(tester, 'Wardrobe');
      expect(find.text('Start with your favorite shirt.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'mobile user adds a valid height, creates outfits and keeps a saved look '
    'after restarting',
    (tester) async {
      final store = _MemoryStyleStore();
      await _pumpApp(tester, store: store, size: const Size(390, 844));

      expect(find.byKey(const Key('starting_piece_shirt')), findsOneWidget);
      expect(find.byType(OutfitCard), findsNothing);
      expect(tester.takeException(), isNull);

      await _generate(tester);
      expect(find.text('What’s your height?'), findsOneWidget);
      await _tapVisible(tester, find.text('Add my height'));

      final height = find.byKey(const Key('height_input'));
      await tester.ensureVisible(height);
      await tester.enterText(height, 'not a number');
      await _tapVisible(tester, find.byKey(const Key('save_profile')));

      expect(find.text('Enter 100–250 cm.'), findsOneWidget);
      expect(store.profileWrites, 0);
      expect(store.snapshot.configured, isFalse);

      await tester.ensureVisible(height);
      await tester.enterText(height, '182');
      await _tapVisible(tester, find.byKey(const Key('save_profile')));

      expect(store.profileWrites, 1);
      expect(store.snapshot.configured, isTrue);
      expect(store.snapshot.profile.heightCm, 182);
      expect(find.byKey(const Key('generate_outfits')), findsOneWidget);

      await _generate(tester);
      expect(find.byType(OutfitCard), findsOneWidget);
      expect(find.byKey(const Key('show_more_outfits')), findsOneWidget);
      final firstLook = tester.widget<OutfitCard>(
        find.byType(OutfitCard).first,
      );

      await _tapVisible(tester, find.text('Favorite outfit').first);
      expect(store.outfitWrites, 1);
      expect(store.snapshot.saved.single.id, firstLook.outfit.id);
      expect(find.text('Favorited'), findsOneWidget);

      await _tapVisible(tester, find.text('Saved'));
      expect(
        find.text('1 saved look. Ready for your next outing.'),
        findsOneWidget,
      );
      expect(find.byType(OutfitCard), findsOneWidget);
      expect(tester.widget<OutfitCard>(find.byType(OutfitCard)).saved, isTrue);
      expect(tester.takeException(), isNull);

      // Mount a fresh app: the collection must come from storage, not old state.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(ThreadApp(store: store));
      await tester.pumpAndSettle();
      await _openMorePage(tester, 'My profile');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('height_input')))
            .controller!
            .text,
        '182',
      );
      await _tapVisible(tester, find.text('Saved'));

      final restored = tester.widget<OutfitCard>(find.byType(OutfitCard));
      expect(restored.outfit.id, firstLook.outfit.id);
      expect(restored.outfit.pants.colorArgb, firstLook.outfit.pants.colorArgb);
      expect(restored.saved, isTrue);
      expect(store.loads, 2);

      await _tapVisible(tester, find.text('Favorited'));
      expect(store.snapshot.saved, isEmpty);
      expect(find.byType(OutfitCard), findsNothing);
      expect(find.text('Your next favorite look is waiting.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  for (final viewport in [
    (name: 'desktop', size: const Size(1440, 1000), scale: 1.0),
    (
      name: 'narrow phone with enlarged text',
      size: const Size(320, 740),
      scale: 1.5,
    ),
  ]) {
    testWidgets(
      '${viewport.name} keeps studio, results and profile usable without overflow',
      (tester) async {
        final store = _MemoryStyleStore(
          initial: const StoredStyle(
            configured: true,
            profile: StyleProfile(
              heightCm: 182,
              bodyShape: BodyShape.broadShoulders,
              useSkinTone: true,
              skinToneArgb: 0xFFAC7955,
              undertone: Undertone.warm,
            ),
          ),
        );
        await _pumpApp(
          tester,
          store: store,
          size: viewport.size,
          textScale: viewport.scale,
        );
        expect(find.text('What are you starting with?'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'Studio must fit the viewport.',
        );

        await _prepareOccasion(tester);
        await _tapVisible(tester, find.byKey(const Key('occasion_office')));
        await _generate(tester);
        expect(find.byType(OutfitCard), findsOneWidget);
        expect(find.text('Plan look'), findsNothing);
        expect(find.byTooltip('Like this look'), findsNothing);
        await _tapVisible(tester, find.byKey(const Key('show_more_outfits')));
        expect(find.byType(OutfitCard), findsNWidgets(3));
        expect(
          tester
              .widgetList<OutfitCard>(find.byType(OutfitCard))
              .map((card) => card.outfit.occasion),
          everyElement(Occasion.office),
        );
        for (var index = 0; index < 3; index++) {
          await tester.ensureVisible(find.text('Outfit details').at(index));
          await tester.pumpAndSettle();
          expect(
            find.text('Outfit details').at(index).hitTestable(),
            findsOneWidget,
          );
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'All three results must fit.',
        );

        await _openMorePage(tester, 'My profile');
        expect(find.text('Style that feels like you.'), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('height_input')))
              .controller!
              .text,
          '182',
        );
        expect(find.text('Undertone (if you know it)'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('save_profile')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('save_profile')).hitTestable(),
          findsOneWidget,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Expanded profile must fit.',
        );
      },
      variant: TargetPlatformVariant({TargetPlatform.linux}),
    );
  }
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required _MemoryStyleStore store,
  required Size size,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(ThreadApp(store: store));
  await tester.pumpAndSettle();
}

Future<void> _restartApp(WidgetTester tester, _MemoryStyleStore store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.pumpWidget(ThreadApp(store: store));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  // Dismiss editing first, as a user would before scrolling to the next action.
  // EditableText schedules caret visibility after a frame; settling that work
  // before ensureVisible prevents it from scrolling back to the height field.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _prepareOccasion(WidgetTester tester) async {
  if (find.byKey(const Key('generate_outfits')).evaluate().isNotEmpty) return;
  if (find.byType(OutfitCard).evaluate().isNotEmpty) {
    await _tapVisible(tester, find.byKey(const Key('studio_back')));
    return;
  }
  if (find.byKey(const Key('starting_piece_shirt')).evaluate().isNotEmpty) {
    await _tapVisible(tester, find.byKey(const Key('studio_next')));
  }
  await _tapVisible(tester, find.byKey(const Key('studio_next')));
}

Future<void> _generate(WidgetTester tester) async {
  await _prepareOccasion(tester);
  await _tapVisible(tester, find.byKey(const Key('generate_outfits')));
}

Future<void> _openPersonalization(WidgetTester tester) async {
  if (find.byKey(const Key('choose_weather_city')).evaluate().isNotEmpty) {
    return;
  }
  await _tapVisible(tester, find.byKey(const Key('studio_personalization')));
}

Future<void> _openMorePage(WidgetTester tester, String label) async {
  await _tapVisible(tester, find.text('More'));
  await _tapVisible(tester, find.text(label));
}

Future<void> _openDetails(WidgetTester tester) async {
  await _tapVisible(tester, find.text('Outfit details').first);
}

/// Implements the public store contract without creating platform preferences.
/// JSON roundtrips prevent these flows from accidentally relying on object
/// identity or on mutable state retained by a previous widget tree.
class _MemoryStyleStore implements StyleStore {
  _MemoryStyleStore({StoredStyle initial = const StoredStyle()})
    : snapshot = initial;

  StoredStyle snapshot;
  int loads = 0;
  int profileWrites = 0;
  int outfitWrites = 0;

  @override
  Future<StoredStyle> load() async {
    loads++;
    return StoredStyle(
      profile: StyleProfile.fromJson(snapshot.profile.toJson()),
      configured: snapshot.configured,
      saved: snapshot.saved
          .map((outfit) => OutfitRecommendation.fromJson(outfit.toJson()))
          .toList(),
      feedback: snapshot.feedback
          .map((entry) => StyleFeedbackEntry.fromJson(entry.toJson()))
          .toList(),
      plans: snapshot.plans
          .map((plan) => PlannedOutfit.fromJson(plan.toJson()))
          .toList(),
      wardrobe: snapshot.wardrobe
          .map((item) => WardrobeItem.fromJson(item.toJson()))
          .toList(),
      direction: snapshot.direction,
      weather: snapshot.weather == null
          ? null
          : WeatherSnapshot.fromJson(snapshot.weather!.toJson()),
      recoveryMessage: snapshot.recoveryMessage,
    );
  }

  @override
  Future<void> saveProfile(StyleProfile profile) async {
    profileWrites++;
    snapshot = _copy(
      profile: StyleProfile.fromJson(profile.toJson()),
      configured: true,
    );
  }

  @override
  Future<void> saveOutfits(List<OutfitRecommendation> outfits) async {
    outfitWrites++;
    snapshot = _copy(
      saved: outfits
          .map((outfit) => OutfitRecommendation.fromJson(outfit.toJson()))
          .toList(),
    );
  }

  @override
  Future<void> saveFeedback(List<StyleFeedbackEntry> feedback) async {
    snapshot = _copy(
      feedback: feedback
          .map((entry) => StyleFeedbackEntry.fromJson(entry.toJson()))
          .toList(),
    );
  }

  @override
  Future<void> savePlans(List<PlannedOutfit> plans) async {
    snapshot = _copy(
      plans: plans
          .map((plan) => PlannedOutfit.fromJson(plan.toJson()))
          .toList(),
    );
  }

  @override
  Future<void> saveWardrobe(List<WardrobeItem> items) async {
    snapshot = _copy(
      wardrobe: items
          .map((item) => WardrobeItem.fromJson(item.toJson()))
          .toList(),
    );
  }

  @override
  Future<void> saveWeather(WeatherSnapshot? weather) async {
    snapshot = _copy(
      weather: weather == null
          ? null
          : WeatherSnapshot.fromJson(weather.toJson()),
      clearWeather: weather == null,
    );
  }

  @override
  Future<void> saveDirection(StyleDirection direction) async {
    snapshot = _copy(direction: direction);
  }

  StoredStyle _copy({
    StyleProfile? profile,
    bool? configured,
    List<OutfitRecommendation>? saved,
    List<StyleFeedbackEntry>? feedback,
    List<PlannedOutfit>? plans,
    List<WardrobeItem>? wardrobe,
    StyleDirection? direction,
    WeatherSnapshot? weather,
    bool clearWeather = false,
  }) => StoredStyle(
    profile: profile ?? snapshot.profile,
    configured: configured ?? snapshot.configured,
    saved: saved ?? snapshot.saved,
    feedback: feedback ?? snapshot.feedback,
    plans: plans ?? snapshot.plans,
    wardrobe: wardrobe ?? snapshot.wardrobe,
    direction: direction ?? snapshot.direction,
    weather: clearWeather ? null : weather ?? snapshot.weather,
  );

  @override
  Future<void> clear() async {
    snapshot = const StoredStyle();
  }
}
