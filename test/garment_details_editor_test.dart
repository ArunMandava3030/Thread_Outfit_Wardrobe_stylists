import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/theme.dart';
import 'package:thread_style/widgets/garment_details_editor.dart';

const _red = ShirtColor(name: 'Red', argb: 0xFFC94F4F);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  StartingPiece piece = StartingPiece.shirt,
  GarmentDetails initial = const GarmentDetails(),
  required ValueChanged<GarmentDetails?> onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThreadTheme.theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
              await showGarmentDetailsEditor(
                context,
                startingPiece: piece,
                initial: initial,
                mainColor: _red,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open'));
}

void main() {
  testWidgets(
    'sampled and preset colors sharing a name have distinct controls',
    (tester) async {
      GarmentDetails? result;
      await _pump(
        tester,
        initial: const GarmentDetails(
          pattern: GarmentPattern.checks,
          accentColors: [ShirtColor(name: 'Blue', argb: 0xFF5381A3)],
        ),
        onResult: (value) => result = value,
      );
      expect(
        find.byKey(const Key('garment_accent_Blue_ff5381a3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('garment_accent_Blue_ff7898b3')),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const Key('garment_accent_Blue_ff7898b3')));
      await _tap(tester, find.byKey(const Key('garment_details_done')));
      expect(result?.accentColors.map((color) => color.argb), [
        0xFF5381A3,
        0xFF7898B3,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor confirms checked flannel with two distinct accent colors',
    (tester) async {
      GarmentDetails? result;
      await _pump(tester, onResult: (value) => result = value);
      await _tap(tester, find.byType(DropdownButtonFormField<GarmentType>));
      expect(find.text('Jeans'), findsNothing);
      await _tap(tester, find.text('Flannel shirt').last);
      await _tap(tester, find.byKey(const Key('garment_pattern_checks')));
      expect(
        find.byKey(const Key('garment_accent_Red_ffc94f4f')),
        findsNothing,
      );
      await _tap(tester, find.byKey(const Key('garment_accent_Navy_ff25394f')));
      await _tap(
        tester,
        find.byKey(const Key('garment_accent_White_fff4f2eb')),
      );
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const Key('garment_accent_Blue_ff7898b3')),
            )
            .onSelected,
        isNull,
      );
      await _tap(tester, find.byKey(const Key('garment_details_done')));
      expect(result?.type, GarmentType.flannel);
      expect(result?.pattern, GarmentPattern.checks);
      expect(result?.accentColors.map((color) => color.name), [
        'Navy',
        'White',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel discards pattern edits and pants types exclude tops', (
    tester,
  ) async {
    var returned = false;
    GarmentDetails? result;
    await _pump(
      tester,
      piece: StartingPiece.pants,
      onResult: (value) {
        returned = true;
        result = value;
      },
    );
    await _tap(tester, find.byType(DropdownButtonFormField<GarmentType>));
    expect(find.text('Flannel shirt'), findsNothing);
    await _tap(tester, find.text('Jeans').last);
    await _tap(tester, find.byKey(const Key('garment_pattern_stripes')));
    await _tap(tester, find.byKey(const Key('garment_details_cancel')));
    expect(returned, isTrue);
    expect(result, isNull);
  });

  testWidgets(
    'solid clears pattern accents and duplicate main color is removed',
    (tester) async {
      GarmentDetails? result;
      await _pump(
        tester,
        initial: const GarmentDetails(
          pattern: GarmentPattern.checks,
          accentColors: [
            _red,
            ShirtColor(name: 'White', argb: 0xFFF4F2EB),
          ],
        ),
        onResult: (value) => result = value,
      );
      expect(
        find.byKey(const Key('garment_accent_Red_ffc94f4f')),
        findsNothing,
      );
      await _tap(tester, find.byKey(const Key('garment_pattern_solid')));
      await _tap(tester, find.byKey(const Key('garment_details_done')));
      expect(result?.accentColors, isEmpty);
    },
  );

  testWidgets('editor remains usable at 320px with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    GarmentDetails? result;
    await _pump(tester, onResult: (value) => result = value);
    await _tap(tester, find.byKey(const Key('garment_pattern_colorBlock')));
    await _tap(tester, find.byKey(const Key('garment_accent_White_fff4f2eb')));
    await _tap(tester, find.byKey(const Key('garment_details_done')));
    expect(result?.pattern, GarmentPattern.colorBlock);
    expect(tester.takeException(), isNull);
  });
}
