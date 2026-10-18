import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/guest_app.dart';
import 'package:thread_style/models/style_discovery_models.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/services/style_engine.dart';

void main() {
  testWidgets('shirt-first flow preserves chosen colors and resets on reload', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(GuestOutfitCard), findsNothing);
    expect(find.textContaining('No account or saved profile'), findsOneWidget);
    expect(find.byKey(const Key('guest_occasion_date')), findsNothing);
    final match = await _toOccasion(tester, colorName: 'Navy');
    await _tap(tester, find.byKey(const Key('guest_occasion_date')));
    await tester.enterText(find.byKey(const Key('guest_height')), '190');
    await _tap(tester, find.byKey(const Key('guest_generate')));

    final cards = tester.widgetList<GuestOutfitCard>(
      find.byType(GuestOutfitCard),
    );
    expect(cards, hasLength(3));
    for (final card in cards) {
      expect(card.outfit.shirt.name, 'Navy');
      expect(card.outfit.pants.colorArgb, match.argb);
      expect(card.outfit.occasion, Occasion.date);
      expect(card.outfit.layer.colorArgb, isNot(0));
      expect(
        card.outfit.fitAdvice,
        contains('Check sleeve and trouser length'),
      );
      expect(card.showHeightAdvice, isTrue);
    }
    expect(find.byTooltip('Save look'), findsNothing);
    expect(find.text('My profile'), findsNothing);
    expect(find.text('Plan look'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const ThreadGuestApp());
    await tester.pumpAndSettle();
    expect(find.byType(GuestOutfitCard), findsNothing);
    expect(find.byKey(const Key('guest_start_shirt')), findsOneWidget);
    await _toOccasion(tester);
    final input = tester.widget<TextFormField>(
      find.byKey(const Key('guest_height')),
    );
    expect(input.controller!.text, isEmpty);
    await _tap(tester, find.byKey(const Key('guest_generate')));
    final first = tester.widget<GuestOutfitCard>(
      find.byType(GuestOutfitCard).first,
    );
    expect(first.outfit.shirt.name, 'Sage');
    expect(first.outfit.occasion, Occasion.casual);
    expect(first.showHeightAdvice, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pants-first flow suggests tops then a party outfit', (
    tester,
  ) async {
    await _pump(tester);
    final match = await _toOccasion(
      tester,
      startingPiece: StartingPiece.pants,
      colorName: 'Black',
    );
    await _tap(tester, find.byKey(const Key('guest_occasion_party')));
    await tester.enterText(find.byKey(const Key('guest_height')), '168');
    await _tap(tester, find.byKey(const Key('guest_back')));
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(Key('guest_match_${match.name}')))
          .selected,
      isTrue,
    );
    await _tap(tester, find.byKey(const Key('guest_continue')));
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('guest_occasion_party')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('guest_height')))
          .controller!
          .text,
      '168',
    );
    await _tap(tester, find.byKey(const Key('guest_generate')));
    for (final card in tester.widgetList<GuestOutfitCard>(
      find.byType(GuestOutfitCard),
    )) {
      expect(card.outfit.startingPiece, StartingPiece.pants);
      expect(card.outfit.pants.colorName, 'Black');
      expect(card.outfit.pants.title, 'Your pants');
      expect(card.outfit.shirt.argb, match.argb);
      expect(card.outfit.shirtTitle, isNot('Your shirt'));
      expect(card.outfit.occasion, Occasion.party);
      expect(card.outfit.layer.colorArgb, isNot(0));
    }
    expect(find.text('Top · ${match.name}'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('all occasions work and riding stays protected with layers off', (
    tester,
  ) async {
    await _pump(tester);
    final match = await _toOccasion(tester);
    await _tap(tester, find.byKey(const Key('guest_layers')));
    for (final occasion in Occasion.values) {
      await _tap(tester, find.byKey(Key('guest_occasion_${occasion.name}')));
      await _tap(tester, find.byKey(const Key('guest_generate')));
      final cards = tester.widgetList<GuestOutfitCard>(
        find.byType(GuestOutfitCard),
      );
      expect(cards, hasLength(3));
      for (final card in cards) {
        expect(card.outfit.occasion, occasion);
        expect(card.outfit.pants.colorArgb, match.argb);
        if (occasion == Occasion.bikeRide) {
          expect(card.outfit.layer.colorArgb, isNot(0));
          expect(card.outfit.layer.title.toLowerCase(), contains('certified'));
          expect(card.outfit.safetyNote, contains('properly fitted helmet'));
        } else {
          expect(card.outfit.layer.colorArgb, 0);
        }
      }
      await _tap(tester, find.byKey(const Key('guest_edit_occasion')));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the starting color or piece requires a fresh match', (
    tester,
  ) async {
    await _pump(tester);
    final match = await _toOccasion(tester);
    await _tap(tester, find.byKey(const Key('guest_back')));
    await _tap(tester, find.byKey(const Key('guest_back')));
    await _tap(tester, find.byKey(const Key('guest_continue')));
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(Key('guest_match_${match.name}')))
          .selected,
      isTrue,
    );
    await _tap(tester, find.byKey(const Key('guest_back')));
    await _tap(tester, find.byKey(const Key('guest_color_Burgundy')));
    await _tap(tester, find.byKey(const Key('guest_continue')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('guest_continue')))
          .onPressed,
      isNull,
    );
    expect(find.text('Choose one color to continue.'), findsOneWidget);
    final color = ShirtColor.presets.firstWhere(
      (item) => item.name == 'Burgundy',
    );
    final nextMatch = const StyleEngine()
        .matchingColors(startingPiece: StartingPiece.shirt, color: color)
        .first;
    await _tap(tester, find.byKey(Key('guest_match_${nextMatch.name}')));
    await _tap(tester, find.byKey(const Key('guest_back')));
    await _tap(tester, find.byKey(const Key('guest_start_pants')));
    await _tap(tester, find.byKey(const Key('guest_continue')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('guest_continue')))
          .onPressed,
      isNull,
    );
    expect(find.byType(GuestOutfitCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('height validation prevents misleading fit tips', (tester) async {
    await _pump(tester);
    await _toOccasion(tester);
    await tester.enterText(find.byKey(const Key('guest_height')), 'NaN');
    await _tap(tester, find.byKey(const Key('guest_generate')));
    expect(find.byType(GuestOutfitCard), findsNothing);
    expect(find.textContaining('between 100 and 250'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('guest_height')), '0');
    await _tap(tester, find.byKey(const Key('guest_generate')));
    expect(find.byType(GuestOutfitCard), findsNothing);
    await tester.enterText(find.byKey(const Key('guest_height')), '');
    await _tap(tester, find.byKey(const Key('guest_generate')));
    expect(find.byType(GuestOutfitCard), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'style mood changes garments while preserving both chosen colors',
    (tester) async {
      await _pump(tester);
      final match = await _toOccasion(tester);
      await _tap(tester, find.byType(DropdownButtonFormField<StyleDirection>));
      await tester.tap(find.text('Streetwear').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('guest_generate')));
      for (final card in tester.widgetList<GuestOutfitCard>(
        find.byType(GuestOutfitCard),
      )) {
        expect(card.outfit.pants.title, 'Relaxed cargo trousers');
        expect(card.outfit.pants.colorArgb, match.argb);
        expect(card.outfit.shirt.name, 'Sage');
        expect(card.outfit.layer.title, 'Relaxed overshirt');
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('320px phone with enlarged text has usable steps and results', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester, size: const Size(320, 844));
    await _toOccasion(tester, startingPiece: StartingPiece.pants);
    await _tap(tester, find.byKey(const Key('guest_generate')));
    await _tap(tester, find.text('Why it works').first);
    expect(find.byType(GuestOutfitCard), findsNWidgets(3));
    expect(
      find.textContaining('comfortable fit at the shoulders'),
      findsOneWidget,
    );
    await _tap(tester, find.text('App releases'), tap: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop shows three outfits in one row', (tester) async {
    await _pump(tester, size: const Size(1440, 1080));
    await _toOccasion(tester);
    await _tap(tester, find.byKey(const Key('guest_generate')));
    final cards = find.byType(GuestOutfitCard);
    expect(cards, findsNWidgets(3));
    final positions = List.generate(3, (i) => tester.getTopLeft(cards.at(i)));
    expect(positions[0].dy, positions[1].dy);
    expect(positions[1].dy, positions[2].dy);
    expect(positions[0].dx, lessThan(positions[1].dx));
    expect(positions[1].dx, lessThan(positions[2].dx));
    expect(tester.takeException(), isNull);
  });
}

Future<ShirtColor> _toOccasion(
  WidgetTester tester, {
  StartingPiece startingPiece = StartingPiece.shirt,
  String colorName = 'Sage',
}) async {
  await _tap(tester, find.byKey(Key('guest_start_${startingPiece.name}')));
  await _tap(tester, find.byKey(Key('guest_color_$colorName')));
  await _tap(tester, find.byKey(const Key('guest_continue')));
  final color = ShirtColor.presets.firstWhere((item) => item.name == colorName);
  final match = const StyleEngine()
      .matchingColors(startingPiece: startingPiece, color: color)
      .first;
  await _tap(tester, find.byKey(Key('guest_match_${match.name}')));
  await _tap(tester, find.byKey(const Key('guest_continue')));
  return match;
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const ThreadGuestApp());
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder, {bool tap = true}) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  if (tap) {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }
}
