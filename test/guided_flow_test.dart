import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/main.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/models/wardrobe_models.dart';
import 'package:thread_style/screens/outfit_rating_screen.dart';
import 'package:thread_style/services/style_engine.dart';
import 'package:thread_style/services/style_store.dart';
import 'package:thread_style/widgets/outfit_card.dart';

void main() {
  testWidgets(
    'checked flannel details reach matches, favorites and rating',
    (tester) async {
      final store = _GuidedStore();
      await _mount(tester, store);
      await _tap(tester, find.byKey(const Key('starting_color_Red')));
      await _tap(tester, find.byKey(const Key('edit_garment_details')));
      await _tap(tester, find.byType(DropdownButtonFormField<GarmentType>));
      await _tap(tester, find.text('Flannel shirt').last);
      await _tap(tester, find.byKey(const Key('garment_pattern_checks')));
      await _tap(tester, find.text('Black').last);
      await _tap(tester, find.byKey(const Key('garment_details_done')));
      await _tap(tester, find.byKey(const Key('studio_next')));
      final selected = tester.widget<ChoiceChip>(
        find.byKey(const Key('matching_suggestion_0')),
      );
      expect((selected.label as Text).data, 'Black');
      await _tap(tester, find.byKey(const Key('studio_next')));
      await _tap(tester, find.byKey(const Key('occasion_date')));
      await _tap(tester, find.byKey(const Key('generate_outfits')));
      final outfit = tester.widget<OutfitCard>(find.byType(OutfitCard)).outfit;
      expect(outfit.topDetails.type, GarmentType.flannel);
      expect(outfit.topDetails.pattern, GarmentPattern.checks);
      expect(outfit.topDetails.accentColors.single.name, 'Black');
      expect(outfit.pantsDetails.pattern, GarmentPattern.solid);
      await _tap(tester, find.text('Favorite outfit'));
      expect(
        store.saved.single.topDetails.toJson(),
        outfit.topDetails.toJson(),
      );
      await _tap(tester, find.text('Outfit details'));
      await _tap(tester, find.text('Rate this outfit'));
      expect(
        tester
            .widget<OutfitRatingScreen>(find.byType(OutfitRatingScreen))
            .initialOutfit!
            .topDetails
            .toJson(),
        outfit.topDetails.toJson(),
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'changing main color clears accents and changing anchor clears type',
    (tester) async {
      await _mount(tester, _GuidedStore());
      await _tap(tester, find.byKey(const Key('edit_garment_details')));
      await _tap(tester, find.byKey(const Key('garment_pattern_checks')));
      await _tap(tester, find.text('Black').last);
      await _tap(tester, find.byKey(const Key('garment_details_done')));
      await _tap(tester, find.byKey(const Key('starting_color_Blue')));
      await _tap(tester, find.byKey(const Key('edit_garment_details')));
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('garment_pattern_checks')))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Black'))
            .selected,
        isFalse,
      );
      await _tap(tester, find.byKey(const Key('garment_details_cancel')));
      await _tap(tester, find.byKey(const Key('starting_piece_pants')));
      await _tap(tester, find.byKey(const Key('edit_garment_details')));
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('garment_pattern_solid')))
            .selected,
        isTrue,
      );
      expect(find.byKey(const ValueKey('garment_type_any')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'phone quick path uses a ready matching color and reachable Continue buttons',
    (tester) async {
      await _mount(tester, _GuidedStore());
      final next = find.byKey(const Key('studio_next'));
      expect(
        next.hitTestable(),
        findsOneWidget,
        reason:
            'Next bounds: ${tester.getRect(next)}; details: ${tester.getRect(find.byKey(const Key('edit_garment_details')))}; photo: ${tester.getRect(find.byKey(const Key('add_photo')))}',
      );
      await tester.tap(next);
      await tester.pumpAndSettle();

      expect(next.hitTestable(), findsOneWidget);
      expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('matching_suggestion_0')))
            .selected,
        isTrue,
      );
      await tester.tap(next);
      await tester.pumpAndSettle();

      final generate = find.byKey(const Key('generate_outfits'));
      expect(generate.hitTestable(), findsOneWidget);
      await tester.tap(generate);
      await tester.pumpAndSettle();
      expect(find.byType(OutfitCard), findsOneWidget);
      expect(find.text('Favorite outfit'), findsOneWidget);
      expect(find.text('Outfit details'), findsOneWidget);
      expect(find.text('Plan look'), findsNothing);
      expect(find.byTooltip('Like this look'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'system Back returns through outfit steps and the More menu',
    (tester) async {
      await _mount(tester, _GuidedStore());
      await _tap(tester, find.byKey(const Key('studio_next')));
      expect(find.text('Choose your pants color'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('starting_piece_shirt')), findsOneWidget);

      await _tap(tester, find.text('More'));
      await _tap(tester, find.text('My profile'));
      expect(find.byKey(const Key('height_input')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Wardrobe'), findsOneWidget);
      expect(find.text('Planner'), findsOneWidget);
      expect(find.byKey(const Key('height_input')), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('starting_piece_shirt')), findsOneWidget);
      await _tap(tester, find.text('Saved'));
      expect(find.text('Your next favorite look is waiting.'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('starting_piece_shirt')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  testWidgets(
    'studio rating route saves a real favorite that survives navigation and restart',
    (tester) async {
      final store = _GuidedStore();
      await _mount(tester, store);
      await _tap(tester, find.byKey(const Key('open_outfit_rating')));
      expect(find.byKey(const Key('rate_current_outfit')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('rating-edit-Top')));
      await _tap(tester, find.byKey(const ValueKey('rating-Top-color-Blue')));
      await _tap(tester, find.byKey(const Key('rating-editor-done')));
      await _tap(tester, find.byKey(const Key('rate_current_outfit')));
      final scoreText = tester
          .widget<Text>(find.byKey(const Key('outfit_rating_score')))
          .data!;
      final score = double.parse(scoreText.split(' / ').first);
      expect(score, inInclusiveRange(0, 5));
      expect(find.text('Things to try'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('favorite_rated_outfit')));
      expect(find.text('Saved to favorites'), findsOneWidget);
      expect(store.saved, hasLength(1));
      final favorite = store.saved.single;
      expect(favorite.shirt.argb, 0xFF7898B3);
      expect(favorite.pants.colorArgb, 0xFF25394F);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('favorite_rated_outfit')),
            )
            .onPressed,
        isNull,
      );

      await _tap(tester, find.byType(BackButton));
      await _tap(tester, find.text('Saved'));
      final savedCard = tester.widget<OutfitCard>(find.byType(OutfitCard));
      expect(savedCard.saved, isTrue);
      expect(savedCard.outfit.toJson(), favorite.toJson());

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(ThreadApp(store: store));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Saved'));
      final restored = tester.widget<OutfitCard>(find.byType(OutfitCard));
      expect(restored.saved, isTrue);
      expect(restored.outfit.toJson(), favorite.toJson());
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'pants first leads from matching top to party layers and a persistent favorite',
    (tester) async {
      final store = _GuidedStore();
      await _mount(tester, store);
      expect(find.byKey(const Key('generate_outfits')), findsNothing);
      expect(find.byKey(const Key('occasion_party')), findsNothing);
      await _tap(tester, find.byKey(const Key('starting_piece_pants')));
      await _tap(tester, find.byKey(const Key('starting_color_Navy')));
      await _tap(tester, find.byKey(const Key('studio_next')));
      expect(find.text('Choose your top color'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('studio_next')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('matching_suggestion_0')))
            .selected,
        isTrue,
      );
      await _tap(tester, find.byKey(const Key('matching_suggestion_1')));
      final expectedTop = const StyleEngine().matchingColors(
        startingPiece: StartingPiece.pants,
        color: ShirtColor.presets.firstWhere((color) => color.name == 'Navy'),
        profile: const StyleProfile(),
      )[1];
      await _tap(tester, find.byKey(const Key('studio_next')));
      await _tap(tester, find.byKey(const Key('occasion_party')));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await _tap(tester, find.byKey(const Key('generate_outfits')));
      expect(find.byType(OutfitCard), findsOneWidget);
      await _tap(tester, find.byKey(const Key('show_more_outfits')));
      expect(find.byType(OutfitCard), findsNWidgets(3));
      for (final card in tester.widgetList<OutfitCard>(
        find.byType(OutfitCard),
      )) {
        expect(card.outfit.startingPiece, StartingPiece.pants);
        expect(card.outfit.occasion, Occasion.party);
        expect(card.outfit.shirt.argb, expectedTop.argb);
        expect(card.outfit.pants.colorArgb, 0xFF25394F);
        expect(card.outfit.pants.title, 'Your pants');
        expect(card.outfit.layer.colorArgb, isNot(0));
      }
      final first = tester
          .widget<OutfitCard>(find.byType(OutfitCard).first)
          .outfit;
      await _tap(tester, find.text('Favorite outfit').first);
      expect(store.saved.single.id, first.id);
      await _tap(tester, find.text('Outfit details').first);
      await _tap(tester, find.text('Rate this outfit'));
      final ratingScreen = tester.widget<OutfitRatingScreen>(
        find.byType(OutfitRatingScreen),
      );
      expect(ratingScreen.initialOutfit?.toJson(), first.toJson());
      expect(find.byKey(const Key('rate_current_outfit')), findsOneWidget);
      await _tap(tester, find.byType(BackButton));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(ThreadApp(store: store));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Saved'));
      final restored = tester.widget<OutfitCard>(find.byType(OutfitCard));
      expect(restored.saved, isTrue);
      expect(restored.outfit.toJson(), first.toJson());
      expect(find.text('Favorited'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'shirt first keeps an explicitly chosen pants color and allows a layer-free date',
    (tester) async {
      await _mount(tester, _GuidedStore());
      await _tap(tester, find.byKey(const Key('starting_piece_shirt')));
      await _tap(tester, find.byKey(const Key('starting_color_Burgundy')));
      await _tap(tester, find.byKey(const Key('studio_next')));
      expect(find.text('Choose your pants color'), findsOneWidget);
      await _tap(tester, find.text('More colors'));
      await _tap(tester, find.byKey(const Key('matching_color_Grey')));
      await _tap(tester, find.byKey(const Key('studio_next')));
      await _tap(tester, find.byKey(const Key('occasion_date')));
      await _tap(tester, find.byType(SwitchListTile));
      await _tap(tester, find.byKey(const Key('generate_outfits')));
      expect(find.byType(OutfitCard), findsOneWidget);
      await _tap(tester, find.byKey(const Key('show_more_outfits')));
      for (final card in tester.widgetList<OutfitCard>(
        find.byType(OutfitCard),
      )) {
        expect(card.outfit.startingPiece, StartingPiece.shirt);
        expect(card.outfit.shirt.argb, 0xFF783B4B);
        expect(card.outfit.shirtTitle, 'Your shirt');
        expect(card.outfit.pants.colorArgb, 0xFF979B9B);
        expect(card.outfit.occasion, Occasion.date);
        expect(card.outfit.layer.colorArgb, 0);
      }
      expect(find.byType(OutfitCard), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'editing the starting item clears old results and selects a fresh matching default',
    (tester) async {
      await _mount(
        tester,
        _GuidedStore(),
        size: const Size(320, 740),
        textScale: 1.5,
      );
      await _tap(tester, find.byKey(const Key('studio_next')));
      await _tap(tester, find.text('More colors'));
      await _tap(tester, find.byKey(const Key('matching_color_Burgundy')));
      await _tap(tester, find.byKey(const Key('studio_next')));
      await _tap(tester, find.byKey(const Key('generate_outfits')));
      expect(find.byType(OutfitCard), findsOneWidget);
      expect(
        tester
            .widget<OutfitCard>(find.byType(OutfitCard))
            .outfit
            .pants
            .colorArgb,
        0xFF783B4B,
      );
      await _tap(tester, find.byKey(const Key('studio_back')));
      expect(find.byKey(const Key('occasion_special')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('studio_back')));
      await _tap(tester, find.byKey(const Key('studio_back')));
      await _tap(tester, find.byKey(const Key('starting_piece_pants')));
      await _tap(tester, find.byKey(const Key('starting_color_Black')));
      expect(find.byType(OutfitCard), findsNothing);
      await _tap(tester, find.byKey(const Key('studio_next')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('studio_next')))
            .onPressed,
        isNotNull,
      );
      for (var i = 0; i < 3; i++) {
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(Key('matching_suggestion_$i')))
              .selected,
          i == 0,
        );
      }
      final expectedTop = const StyleEngine()
          .matchingColors(
            startingPiece: StartingPiece.pants,
            color: ShirtColor.presets.firstWhere(
              (color) => color.name == 'Black',
            ),
            profile: const StyleProfile(),
          )
          .first;
      await _tap(tester, find.byKey(const Key('studio_next')));
      await _tap(tester, find.byKey(const Key('occasion_special')));
      await _tap(tester, find.byKey(const Key('generate_outfits')));
      for (final card in tester.widgetList<OutfitCard>(
        find.byType(OutfitCard),
      )) {
        expect(card.outfit.startingPiece, StartingPiece.pants);
        expect(card.outfit.pants.colorArgb, 0xFF262626);
        expect(card.outfit.shirt.argb, expectedTop.argb);
        expect(card.outfit.occasion, Occasion.special);
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'wearing wardrobe pants opens matching tops with the exact stored color',
    (tester) async {
      final store = _GuidedStore(
        wardrobe: const [
          WardrobeItem(
            id: 'custom-pants',
            name: 'My teal trousers',
            category: WardrobeCategory.pants,
            colorName: 'Deep custom teal',
            colorArgb: 0xFF285756,
          ),
        ],
      );
      await _mount(tester, store);
      await _tap(tester, find.text('More'));
      await _tap(tester, find.text('Wardrobe'));
      await _tap(tester, find.text('Wear these pants'));
      expect(find.text('Choose your top color'), findsOneWidget);
      expect(
        find.textContaining('Keeping your deep custom teal pants'),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const Key('studio_next')));
      await _tap(tester, find.byKey(const Key('occasion_office')));
      await _tap(tester, find.byKey(const Key('generate_outfits')));
      expect(find.byType(OutfitCard), findsOneWidget);
      await _tap(tester, find.byKey(const Key('show_more_outfits')));
      expect(find.byType(OutfitCard), findsNWidgets(3));
      for (final card in tester.widgetList<OutfitCard>(
        find.byType(OutfitCard),
      )) {
        expect(card.outfit.startingPiece, StartingPiece.pants);
        expect(card.outfit.pants.colorArgb, 0xFF285756);
        expect(card.outfit.pants.colorName, 'Deep custom teal');
        expect(card.outfit.occasion, Occasion.office);
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );
}

Future<void> _mount(
  WidgetTester tester,
  _GuidedStore store, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(ThreadApp(store: store));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _GuidedStore implements StyleStore {
  _GuidedStore({this.wardrobe = const []});
  final List<WardrobeItem> wardrobe;
  List<OutfitRecommendation> saved = [];

  @override
  Future<StoredStyle> load() async => StoredStyle(
    configured: true,
    saved: saved
        .map((look) => OutfitRecommendation.fromJson(look.toJson()))
        .toList(),
    wardrobe: wardrobe
        .map((item) => WardrobeItem.fromJson(item.toJson()))
        .toList(),
  );

  @override
  Future<void> saveOutfits(List<OutfitRecommendation> outfits) async {
    saved = outfits
        .map((look) => OutfitRecommendation.fromJson(look.toJson()))
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Unexpected persistence operation: ${invocation.memberName}',
  );
}
