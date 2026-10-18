import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/models/wardrobe_models.dart';
import 'package:thread_style/screens/wardrobe_screen.dart';
import 'package:thread_style/services/wardrobe_stylist.dart';
import 'package:thread_style/theme.dart';

const _navyPants = WardrobeItem(
  id: 'navy-pants',
  name: 'My navy chinos',
  colorName: 'Navy',
  colorArgb: 0xFF25394F,
  category: WardrobeCategory.pants,
);

OutfitRecommendation _look(
  String id, {
  int pants = 0xFF25394F,
  Occasion occasion = Occasion.office,
  bool layer = true,
}) => OutfitRecommendation(
  id: id,
  title: 'The office regular',
  description: 'An easy combination.',
  occasion: occasion,
  shirt: const ShirtColor(name: 'Sage', argb: 0xFF9BAE98),
  pants: OutfitPiece(
    category: 'Pants',
    title: 'chinos',
    colorName: 'Chosen color',
    colorArgb: pants,
  ),
  shoes: const OutfitPiece(
    category: 'Shoes',
    title: 'loafers',
    colorName: 'Brown',
    colorArgb: 0xFF76563D,
  ),
  layer: OutfitPiece(
    category: 'Layer',
    title: layer ? 'blazer' : 'Skip the layer',
    colorName: 'Navy',
    colorArgb: layer ? 0xFF25394F : 0,
  ),
  reasons: const ['Balanced colors.'],
  fitAdvice: 'Choose a comfortable fit.',
  safetyNote: occasion == Occasion.bikeRide
      ? 'Wear certified motorcycle protective equipment.'
      : null,
);

void main() {
  const stylist = WardrobeStylist();

  test(
    'wardrobe JSON preserves category and color and rejects damaged records',
    () {
      final restored = WardrobeItem.fromJson(_navyPants.toJson());
      expect(restored.toJson(), _navyPants.toJson());
      expect(restored.hex, '#25394F');
      for (final invalid in <Map<String, dynamic>>[
        {'name': '   '},
        {'name': List.filled(61, 'a').join()},
        {'id': ''},
        {'category': 'accessory'},
        {'colorArgb': -1},
        {'colorArgb': 0x0025394F},
        {'colorName': ''},
      ]) {
        expect(
          () => WardrobeItem.fromJson({..._navyPants.toJson(), ...invalid}),
          throwsFormatException,
        );
      }
    },
  );

  test('coverage counts nearby colors only within the matching category', () {
    final near = _look('near', pants: 0xFF273B51);
    expect(stylist.coverage(near, [_navyPants]), 1);
    expect(stylist.matchesFor(near, [_navyPants]).keys, [
      WardrobeCategory.pants,
    ]);
    expect(stylist.coverage(_look('red', pants: 0xFFC94F4F), [_navyPants]), 0);
    expect(stylist.coverage(near, [_navyPants, _navyPants]), 1);
    const shirt = WardrobeItem(
      id: 'shirt',
      name: 'Navy shirt',
      colorName: 'Navy',
      colorArgb: 0xFF25394F,
      category: WardrobeCategory.shirt,
    );
    expect(stylist.coverage(near, [shirt]), 0);
    const layer = WardrobeItem(
      id: 'layer',
      name: 'Navy overshirt',
      colorName: 'Navy',
      colorArgb: 0xFF25394F,
      category: WardrobeCategory.layer,
    );
    expect(stylist.coverage(_look('no-layer', layer: false), [layer]), 0);
  });

  test(
    'ownership ranking is stable and preserves garment and weather requirements',
    () {
      final red = _look('red', pants: 0xFFC94F4F);
      final navy = _look('navy');
      final navyAgain = _look('navy-again');
      final candidates = [red, navy, navyAgain];
      final ranked = stylist.rankByOwnership(candidates, [_navyPants]);
      expect(ranked.map((look) => look.id), ['navy', 'navy-again', 'red']);
      expect(identical(ranked.first, navy), isTrue);
      expect(candidates.first, red);
      expect(stylist.rankByOwnership(candidates, []), candidates);
    },
  );

  test('fashion wardrobe never counts as certified riding equipment', () {
    final riding = _look('ride', occasion: Occasion.bikeRide);
    expect(stylist.coverage(riding, [_navyPants]), 0);
    final ranked = stylist.rankByOwnership([riding], [_navyPants]);
    expect(identical(ranked.single, riding), isTrue);
    expect(ranked.single.safetyNote, contains('certified motorcycle'));
  });

  testWidgets(
    'wardrobe supports add, edit, wear, category filters and removal',
    (tester) async {
      var items = <WardrobeItem>[];
      WardrobeItem? worn;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThreadTheme.theme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: WardrobeScreen(
                  items: items,
                  onSave: (item) => update(() {
                    items = [...items.where((old) => old.id != item.id), item];
                  }),
                  onRemove: (id) => update(() {
                    items = items.where((item) => item.id != id).toList();
                  }),
                  onWear: (item) => worn = item,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start with your favorite shirt.'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('add_wardrobe_item')));
      await _tap(tester, find.byKey(const Key('save_wardrobe_item')));
      expect(find.text('Give this item a name.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('wardrobe_name')),
        '  My favorite shirt  ',
      );
      await _tap(tester, find.byTooltip('Navy'));
      await _tap(tester, find.byKey(const Key('save_wardrobe_item')));
      expect(items.single.name, 'My favorite shirt');
      expect(items.single.colorArgb, 0xFF25394F);
      final originalId = items.single.id;
      await _tap(tester, find.text('Wear this shirt'));
      expect(worn?.id, originalId);
      await _tap(tester, find.byTooltip('Edit item'));
      await tester.enterText(
        find.byKey(const Key('wardrobe_name')),
        'Navy linen shirt',
      );
      await _tap(tester, find.byKey(const Key('save_wardrobe_item')));
      expect(items.single.id, originalId);
      expect(items.single.name, 'Navy linen shirt');
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Pants'));
      expect(find.text('Room for another favorite.'), findsOneWidget);
      expect(find.text('Navy linen shirt'), findsNothing);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'All (1)'));
      await _tap(tester, find.byTooltip('Remove item'));
      expect(items, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wardrobe custom color is validated and cancel creates no item', (
    tester,
  ) async {
    WardrobeItem? result;
    await _pumpDialog(tester, (value) => result = value);
    await tester.enterText(find.byKey(const Key('wardrobe_name')), 'My boots');
    await tester.enterText(find.byKey(const Key('wardrobe_hex')), 'badhex');
    await _tap(tester, find.byKey(const Key('save_wardrobe_item')));
    expect(find.text('Use 6 hex digits, like #9BAE98.'), findsOneWidget);
    expect(result, isNull);
    await tester.enterText(find.byKey(const Key('wardrobe_hex')), '#A1B2C3');
    await _tap(tester, find.byKey(const Key('wardrobe_category')));
    await _tap(tester, find.text('Shoes').last);
    await _tap(tester, find.byKey(const Key('save_wardrobe_item')));
    expect(result?.colorArgb, 0xFFA1B2C3);
    expect(result?.colorName, 'Custom');
    expect(result?.category, WardrobeCategory.shoes);
    await _tap(tester, find.text('Open wardrobe'));
    await _tap(tester, find.text('Cancel'));
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wardrobe and add dialog fit a narrow phone with enlarged text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThreadTheme.theme,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: WardrobeScreen(
              items: const [_navyPants],
              onSave: (_) {},
              onRemove: (_) {},
              onWear: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byTooltip('Edit item'));
    await tester.enterText(
      find.byKey(const Key('wardrobe_name')),
      'My navy trousers',
    );
    await _tap(tester, find.byTooltip('Blue'));
    await _tap(tester, find.byKey(const Key('save_wardrobe_item')));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester,
  ValueChanged<WardrobeItem?> onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThreadTheme.theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                onResult(await showWardrobeItemDialog(context)),
            child: const Text('Open wardrobe'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.text('Open wardrobe'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
