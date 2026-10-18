import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/guest_app.dart';
import 'package:thread_style/models/style_discovery_models.dart';
import 'package:thread_style/models/style_models.dart';

void main() {
  testWidgets('guest choices generate outfits and reset with a new session', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(GuestOutfitCard), findsNothing);
    expect(find.textContaining('No account or saved profile'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('guest_color_Navy')));
    await _tap(tester, find.byKey(const Key('guest_occasion_date')));
    await tester.enterText(find.byKey(const Key('guest_height')), '190');
    await _tap(tester, find.byKey(const Key('guest_generate')));

    final cards = tester.widgetList<GuestOutfitCard>(
      find.byType(GuestOutfitCard),
    );
    expect(cards, hasLength(3));
    for (final card in cards) {
      expect(card.outfit.shirt.name, 'Navy');
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

  testWidgets(
    'all occasions work without optional layers and riding stays protected',
    (tester) async {
      await _pump(tester);
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
          if (occasion == Occasion.bikeRide) {
            expect(card.outfit.layer.colorArgb, isNot(0));
            expect(
              card.outfit.layer.title.toLowerCase(),
              contains('certified'),
            );
            expect(card.outfit.safetyNote, contains('properly fitted helmet'));
          } else {
            expect(card.outfit.layer.colorArgb, 0);
          }
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('height validation prevents misleading fit tips', (tester) async {
    await _pump(tester);
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

  testWidgets('style mood changes the suggested garments', (tester) async {
    await _pump(tester);
    final dropdown = find.byType(DropdownButtonFormField<StyleDirection>);
    await _tap(tester, dropdown);
    await tester.tap(find.text('Streetwear').last);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('guest_generate')));
    for (final card in tester.widgetList<GuestOutfitCard>(
      find.byType(GuestOutfitCard),
    )) {
      expect(card.outfit.pants.title, 'Relaxed cargo trousers');
      expect(card.outfit.layer.title, 'Relaxed overshirt');
    }
    await _tap(tester, find.byKey(const Key('guest_color_Beige')));
    expect(find.byType(GuestOutfitCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px phone with enlarged text has usable results and details', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester, size: const Size(320, 844));
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
