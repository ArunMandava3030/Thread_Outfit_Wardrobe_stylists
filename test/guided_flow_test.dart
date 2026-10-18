import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/main.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/models/wardrobe_models.dart';
import 'package:thread_style/services/style_engine.dart';
import 'package:thread_style/services/style_store.dart';
import 'package:thread_style/widgets/outfit_card.dart';

void main() {
  testWidgets(
    'studio rating route saves a real favorite that survives navigation and restart',
    (tester) async {
      final store = _GuidedStore();
      await _mount(tester, store);
      await _tap(tester, find.byKey(const Key('open_outfit_rating')));
      expect(find.byKey(const Key('rate_current_outfit')), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('rating-Top-color-Blue')));
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
      await _tap(tester, find.text('Saved looks'));
      final savedCard = tester.widget<OutfitCard>(find.byType(OutfitCard));
      expect(savedCard.saved, isTrue);
      expect(savedCard.outfit.toJson(), favorite.toJson());

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(ThreadApp(store: store));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Saved looks'));
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
        isNull,
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
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(ThreadApp(store: store));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Saved looks'));
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
    'editing the starting item clears the old match and requires a new pairing',
    (tester) async {
      await _mount(
        tester,
        _GuidedStore(),
        size: const Size(320, 740),
        textScale: 1.5,
      );
      await _tap(tester, find.byKey(const Key('studio_next')));
      await _tap(tester, find.byKey(const Key('matching_suggestion_0')));
      await _tap(tester, find.byKey(const Key('studio_next')));
      await _tap(tester, find.byKey(const Key('generate_outfits')));
      expect(find.byType(OutfitCard), findsNWidgets(3));
      await _tap(tester, find.byKey(const Key('studio_back')));
      expect(find.byKey(const Key('occasion_special')), findsOneWidget);
      await _tap(tester, find.byKey(const Key('studio_step_0')));
      await _tap(tester, find.byKey(const Key('starting_piece_pants')));
      await _tap(tester, find.byKey(const Key('starting_color_Black')));
      expect(find.byType(OutfitCard), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('studio_step_3')))
            .onSelected,
        isNull,
      );
      await _tap(tester, find.byKey(const Key('studio_next')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('studio_next')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('studio_step_2')))
            .onSelected,
        isNull,
      );
      for (var i = 0; i < 3; i++) {
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(Key('matching_suggestion_$i')))
              .selected,
          isFalse,
        );
      }
      await _tap(tester, find.byKey(const Key('matching_suggestion_2')));
      await _tap(tester, find.byKey(const Key('studio_next')));
      await _tap(tester, find.byKey(const Key('occasion_special')));
      await _tap(tester, find.byKey(const Key('generate_outfits')));
      for (final card in tester.widgetList<OutfitCard>(
        find.byType(OutfitCard),
      )) {
        expect(card.outfit.startingPiece, StartingPiece.pants);
        expect(card.outfit.pants.colorArgb, 0xFF262626);
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
      await _tap(tester, find.text('Wardrobe'));
      await _tap(tester, find.text('Wear these pants'));
      expect(find.text('Choose your top color'), findsOneWidget);
      expect(
        find.textContaining('Keeping your deep custom teal pants'),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const Key('matching_suggestion_0')));
      await _tap(tester, find.byKey(const Key('studio_next')));
      await _tap(tester, find.byKey(const Key('occasion_office')));
      await _tap(tester, find.byKey(const Key('generate_outfits')));
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
