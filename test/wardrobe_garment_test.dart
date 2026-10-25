import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/models/wardrobe_models.dart';
import 'package:thread_style/screens/wardrobe_screen.dart';
import 'package:thread_style/theme.dart';

const _saved = WardrobeItem(
  id: 'red-flannel',
  name: 'My red flannel',
  colorName: 'Red',
  colorArgb: 0xFFC94F4F,
  category: WardrobeCategory.shirt,
  details: GarmentDetails(
    type: GarmentType.flannel,
    pattern: GarmentPattern.checks,
    accentColors: [ShirtColor(name: 'Navy', argb: 0xFF25394F)],
  ),
);

void main() {
  testWidgets(
    'wardrobe editor preserves checked flannel and cancels draft changes',
    (tester) async {
      WardrobeItem? result;
      await _open(tester, (value) => result = value, existing: _saved);
      await _tap(tester, find.byKey(const Key('wardrobe_details')));
      expect(find.text('Checks / plaid'), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const Key('garment_accent_Navy_ff25394f')),
            )
            .selected,
        isTrue,
      );
      await _tap(tester, find.byKey(const Key('garment_pattern_stripes')));
      await _tap(tester, find.byKey(const Key('garment_details_cancel')));
      await _tap(tester, find.byKey(const Key('save_wardrobe_item')));
      expect(result?.id, _saved.id);
      expect(result?.details.signature, _saved.details.signature);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wardrobe item can add garment type pattern and accent on a phone',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      WardrobeItem? result;
      await _open(tester, (value) => result = value);
      await tester.enterText(
        find.byKey(const Key('wardrobe_name')),
        'My striped tee',
      );
      await _tap(tester, find.byKey(const Key('wardrobe_details')));
      await _tap(tester, find.byKey(const Key('garment_type_any')));
      await _tap(tester, find.text('T-shirt').last);
      await _tap(tester, find.byKey(const Key('garment_pattern_stripes')));
      await _tap(tester, find.byKey(const Key('garment_accent_Navy_ff25394f')));
      await _tap(tester, find.byKey(const Key('garment_details_done')));
      await _tap(tester, find.byKey(const Key('save_wardrobe_item')));
      expect(result?.details.type, GarmentType.tShirt);
      expect(result?.details.pattern, GarmentPattern.stripes);
      expect(result?.details.accentColors.single.name, 'Navy');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing main color clears old accents and category clears garment details',
    (tester) async {
      WardrobeItem? result;
      await _open(tester, (value) => result = value, existing: _saved);
      await _tap(tester, find.byTooltip('Blue'));
      await _tap(tester, find.byKey(const Key('save_wardrobe_item')));
      expect(result?.details.pattern, GarmentPattern.checks);
      expect(result?.details.type, GarmentType.flannel);
      expect(result?.details.accentColors, isEmpty);
      await _open(tester, (value) => result = value, existing: _saved);
      await _tap(tester, find.byKey(const Key('wardrobe_category')));
      await _tap(tester, find.text('Pants').last);
      await _tap(tester, find.byKey(const Key('save_wardrobe_item')));
      expect(result?.category, WardrobeCategory.pants);
      expect(result?.details.isSpecified, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _open(
  WidgetTester tester,
  ValueChanged<WardrobeItem?> onResult, {
  WardrobeItem? existing,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThreadTheme.theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
              await showWardrobeItemDialog(context, existing: existing),
            ),
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
