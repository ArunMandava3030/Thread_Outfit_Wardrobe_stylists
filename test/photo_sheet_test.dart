import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/services/photo_analyzer.dart';
import 'package:thread_style/theme.dart';
import 'package:thread_style/widgets/photo_analysis_sheet.dart';

void main() {
  testWidgets(
    'design mode skips pose and reads arbitrary visible detail without a pattern label',
    (tester) async {
      _setPhoneViewport(tester);
      final bytes = await tester.runAsync(_makeDetailedPng);
      PhotoAnalysisResult? result;
      await _openSheet(
        tester,
        bytes: bytes!,
        startInDesignMode: true,
        onResult: (value) => result = value,
      );
      expect(find.text('Auto analyze'), findsNothing);
      expect(find.byKey(const Key('read_garment_palette')), findsNothing);
      expect(find.textContaining('Tap one corner'), findsOneWidget);
      await _tapPhotoPoint(tester, const Offset(.05, .05));
      await _tapPhotoPoint(tester, const Offset(.95, .95));
      expect(find.text('Photo estimate'), findsOneWidget);
      expect(find.textContaining('no pattern label is needed'), findsOneWidget);
      expect(find.textContaining('%'), findsWidgets);
      expect(find.byKey(const Key('garment_pattern_checks')), findsNothing);
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Use this design'),
      );
      expect(result?.visualProfile?.isReliable, isTrue);
      expect(result?.visualProfile?.hasDetail, isTrue);
      expect(result?.visualProfile?.palette.length, greaterThanOrEqualTo(2));
      expect(result?.visualProfile?.previewArgb.length, 256);
      expect(result?.bodyShape, isNull);
      expect(result?.skinToneArgb, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('design estimate can be canceled and narrow screen can confirm', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    tester.view.physicalSize = const Size(320, 760);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final bytes = await tester.runAsync(_makeTwoColourPng);
    PhotoAnalysisResult? result;
    for (final confirm in [false, true]) {
      await _openSheet(
        tester,
        bytes: bytes!,
        garmentLabel: 'shirt',
        startInDesignMode: true,
        onResult: (value) => result = value,
      );
      await _tapPhotoPoint(tester, const Offset(.05, .1));
      await _tapPhotoPoint(tester, const Offset(.95, .9));
      if (confirm) {
        await _tapVisible(
          tester,
          find.widgetWithText(FilledButton, 'Use this design'),
        );
        expect(result?.visualProfile?.isReliable, isTrue);
      } else {
        await _tapVisible(tester, find.byTooltip('Close photo'));
        expect(result, isNull);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'garment region extracts multiple colors and confirms chosen main first',
    (tester) async {
      _setPhoneViewport(tester);
      final bytes = await tester.runAsync(_makeTwoColourPng);
      PhotoAnalysisResult? result;
      await _openSheet(
        tester,
        bytes: bytes!,
        garmentLabel: 'shirt',
        onResult: (value) => result = value,
      );
      await _tapVisible(tester, find.byKey(const Key('read_garment_palette')));
      await _tapPhotoPoint(tester, const Offset(.05, .1));
      expect(find.textContaining('Tap the opposite corner.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use this shirt colour'),
            )
            .onPressed,
        isNull,
      );
      await _tapPhotoPoint(tester, const Offset(.95, .9));
      // The second swatch is the photographed warm color, not a preset RGB.
      final swatch = find.byWidgetPredicate(
        (widget) =>
            widget is ChoiceChip &&
            widget.key == ValueKey('garment_swatch_${0xFFC1926B}'),
      );
      expect(swatch, findsOneWidget);
      await _tapVisible(tester, swatch);
      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Use this design'),
      );
      expect(result!.shirtColor!.argb, 0xFFC1926B);
      expect(result!.garmentPalette.map((color) => color.argb), [
        0xFFC1926B,
        0xFF4279A6,
      ]);
      expect(result!.skinToneArgb, isNull);
      expect(result!.bodyShape, isNull);
      expect(result!.visualProfile?.isReliable, isTrue);
      expect(result!.visualProfile!.palette, hasLength(2));
      expect(result!.visualProfile!.previewArgb, hasLength(256));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('redo and single color clear a previously extracted palette', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final bytes = await tester.runAsync(_makeTwoColourPng);
    PhotoAnalysisResult? result;
    await _openSheet(
      tester,
      bytes: bytes!,
      garmentLabel: 'pants',
      onResult: (value) => result = value,
    );
    await _tapVisible(tester, find.byKey(const Key('read_garment_palette')));
    await _tapPhotoPoint(tester, const Offset(.05, .1));
    await _tapPhotoPoint(tester, const Offset(.95, .9));
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    await _tapVisible(tester, find.byKey(const Key('redo_garment_region')));
    expect(find.byType(ChoiceChip), findsNothing);
    final confirm = find.widgetWithText(FilledButton, 'Use this pants colour');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await _tapPhotoPoint(tester, const Offset(.05, .1));
    await _tapPhotoPoint(tester, const Offset(.45, .9));
    expect(find.byType(ChoiceChip), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('single_garment_color')));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await _tapPhotoPoint(tester, const Offset(.75, .5));
    await _tapVisible(tester, confirm);
    expect(result!.shirtColor!.argb, 0xFFC1926B);
    expect(result!.garmentPalette, isEmpty);
    expect(result!.visualProfile, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('palette is optional and absent for skin and body analysis', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final bytes = await tester.runAsync(_makeTwoColourPng);
    for (final mode in ['disabled', 'skin', 'body']) {
      await _openSheet(
        tester,
        bytes: bytes!,
        onResult: (_) {},
        garmentLabel: mode == 'disabled' ? 'shirt' : null,
        allowPalette: mode != 'disabled',
        sampleSkin: mode == 'skin',
        measureBody: mode == 'body',
      );
      expect(find.byKey(const Key('read_garment_palette')), findsNothing);
      await _tapVisible(tester, find.byTooltip('Close photo'));
    }
  });

  testWidgets(
    'starting another region invalidates the previous palette and rejects a line',
    (tester) async {
      _setPhoneViewport(tester);
      final bytes = await tester.runAsync(_makeTwoColourPng);
      await _openSheet(
        tester,
        bytes: bytes!,
        garmentLabel: 'pants',
        onResult: (_) {},
      );
      await _tapVisible(tester, find.byKey(const Key('read_garment_palette')));
      await _tapPhotoPoint(tester, const Offset(.05, .1));
      await _tapPhotoPoint(tester, const Offset(.95, .9));
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      await _tapPhotoPoint(tester, const Offset(.2, .2));
      expect(find.byType(ChoiceChip), findsNothing);
      final confirm = find.widgetWithText(
        FilledButton,
        'Use this pants colour',
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await _tapPhotoPoint(tester, const Offset(.2, .7));
      expect(
        find.text('Choose opposite corners of a wider area.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await _tapPhotoPoint(tester, const Offset(.1, .2));
      await _tapPhotoPoint(tester, const Offset(.4, .7));
      expect(find.byType(ChoiceChip), findsOneWidget);
      expect(
        find.text('Choose opposite corners of a wider area.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pants photo samples only the tapped garment with no torso auto estimate',
    (tester) async {
      _setPhoneViewport(tester);
      final bytes = await tester.runAsync(_makeTwoColourPng);
      PhotoAnalysisResult? result;
      await _openSheet(
        tester,
        bytes: bytes!,
        garmentLabel: 'pants',
        onResult: (value) => result = value,
      );
      expect(find.text('Read your pants'), findsOneWidget);
      expect(find.text('Auto analyze'), findsNothing);
      final confirm = find.widgetWithText(
        FilledButton,
        'Use this pants colour',
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await _tapPhotoPoint(tester, const Offset(.75, .5));
      await _tapVisible(tester, confirm);
      expect(result!.shirtColor!.argb, 0xFFC1926B);
      expect(result!.skinToneArgb, isNull);
      expect(result!.bodyShape, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('decoded shirt and skin samples preserve their original colours', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    final bytes = await tester.runAsync(_makeTwoColourPng);
    expect(bytes, isNotNull);

    for (final sampleSkin in [false, true]) {
      PhotoAnalysisResult? result;
      await _openSheet(
        tester,
        bytes: bytes!,
        sampleSkin: sampleSkin,
        onResult: (value) => result = value,
      );
      final label = sampleSkin ? 'Use this skin tone' : 'Use this shirt colour';
      final confirm = find.widgetWithText(FilledButton, label);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      // The portrait fixture leaves a border on each side. That border must
      // never be mistaken for a colour in the actual photograph.
      final canvas = _photoCanvas();
      await tester.ensureVisible(canvas);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(canvas);
      await tester.tapAt(Offset(bounds.left + 4, bounds.center.dy));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await _tapPhotoPoint(tester, Offset(sampleSkin ? 0.75 : 0.25, 0.5));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await _tapVisible(tester, confirm);

      expect(result, isNotNull);
      expect(result!.bodyShape, isNull);
      if (sampleSkin) {
        expect(result!.skinToneArgb, 0xFFC1926B);
        expect(result!.shirtColor, isNull);
      } else {
        // This deliberately differs from every preset: naming must not replace
        // the measured colour with a palette entry.
        expect(result!.shirtColor!.argb, 0xFF4279A6);
        expect(result!.shirtColor!.name, isNotEmpty);
        expect(result!.skinToneArgb, isNull);
      }
      expect(find.byType(PhotoAnalysisSheet), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'unreadable photo offers a recoverable error and cannot confirm',
    (tester) async {
      _setPhoneViewport(tester);
      PhotoAnalysisResult? result;
      var closed = false;
      await _openSheet(
        tester,
        bytes: Uint8List.fromList([0, 4, 8, 12]),
        onResult: (value) {
          result = value;
          closed = true;
        },
      );

      expect(
        find.text('This photo could not be opened. Try a different photo.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use this shirt colour'),
            )
            .onPressed,
        isNull,
      );
      expect(closed, isFalse);
      await _tapVisible(tester, find.byTooltip('Close photo'));
      expect(closed, isTrue);
      expect(result, isNull);
      expect(find.byType(PhotoAnalysisSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'proportion guide requires all three valid pairs and supports undo',
    (tester) async {
      _setPhoneViewport(tester);
      final bytes = await tester.runAsync(_makeTwoColourPng);
      PhotoAnalysisResult? result;
      await _openSheet(
        tester,
        bytes: bytes!,
        measureBody: true,
        onResult: (value) => result = value,
      );
      final confirm = find.widgetWithText(
        FilledButton,
        'Use these proportions',
      );
      expect(find.text('Tap one outer shoulder edge'), findsOneWidget);

      await _tapPhotoPoint(tester, const Offset(0.1, 0.2), body: true);
      await _tapPhotoPoint(tester, const Offset(0.9, 0.2), body: true);
      expect(find.text('2/6'), findsOneWidget);
      expect(find.text('Tap one waist edge'), findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await _tapPhotoPoint(tester, const Offset(0.3, 0.5), body: true);
      await _tapPhotoPoint(tester, const Offset(0.7, 0.5), body: true);
      await _tapPhotoPoint(tester, const Offset(0.25, 0.8), body: true);
      expect(find.text('5/6'), findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      // A tilted final pair is not a useful width estimate. Correct it through
      // the same undo affordance available to the user.
      await _tapPhotoPoint(tester, const Offset(0.75, 0.5), body: true);
      expect(find.text('6/6'), findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(
        find.text(
          'Keep each pair level and on opposite edges. Undo to adjust.',
        ),
        findsOneWidget,
      );
      await _tapVisible(tester, find.byTooltip('Undo last point'));
      expect(find.text('5/6'), findsOneWidget);
      await _tapPhotoPoint(tester, const Offset(0.75, 0.8), body: true);

      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      expect(find.text('Approximate guide: Broader shoulders'), findsOneWidget);
      await _tapVisible(tester, confirm);
      expect(result!.bodyShape, BodyShape.broadShoulders);
      expect(result!.shirtColor, isNull);
      expect(result!.skinToneArgb, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<Uint8List> _makeTwoColourPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 40, 120),
    ui.Paint()..color = const Color(0xFF4279A6),
  );
  canvas.drawRect(
    const Rect.fromLTWH(40, 0, 40, 120),
    ui.Paint()..color = const Color(0xFFC1926B),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(80, 120);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return Uint8List.fromList(
      data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<Uint8List> _makeDetailedPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 80, 120),
    ui.Paint()..color = const Color(0xFFF4F2EB),
  );
  // Irregular marks deliberately do not correspond to a named pattern chip.
  for (var y = 3; y < 120; y += 7) {
    for (var x = 2; x < 80; x += 9) {
      canvas.drawCircle(
        Offset((x + y % 5).toDouble(), y.toDouble()),
        ((x + y) % 3 + 1).toDouble(),
        ui.Paint()..color = const Color(0xFF25394F),
      );
      canvas.drawLine(
        Offset(x.toDouble(), y.toDouble()),
        Offset(x + 3.0, y + 4.0),
        ui.Paint()
          ..color = const Color(0xFFC94F4F)
          ..strokeWidth = 2,
      );
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(80, 120);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return Uint8List.fromList(
      data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _openSheet(
  WidgetTester tester, {
  required Uint8List bytes,
  required ValueChanged<PhotoAnalysisResult?> onResult,
  bool sampleSkin = false,
  bool measureBody = false,
  String? garmentLabel,
  bool allowPalette = true,
  bool startInDesignMode = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThreadTheme.theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                final result = await showModalBottomSheet<PhotoAnalysisResult>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => PhotoAnalysisSheet(
                    bytes: bytes,
                    sampleSkin: sampleSkin,
                    measureBody: measureBody,
                    garmentLabel: garmentLabel,
                    allowPalette: allowPalette,
                    startInDesignMode: startInDesignMode,
                  ),
                );
                onResult(result);
              },
              child: const Text('Open photo'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open photo'));
  await tester.pump();

  // The image codec runs on the engine, outside the test's fake clock. Let its
  // real asynchronous work finish before settling the loading animation.
  await tester.runAsync(() async {
    for (var attempt = 0; attempt < 150; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
    }
  });
  expect(find.byType(CircularProgressIndicator), findsNothing);
  await tester.pumpAndSettle();
}

Finder _photoCanvas({bool body = false}) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.label ==
          (body
              ? 'Photo. Tap the indicated body edges.'
              : 'Photo. Tap an area to sample its colour.'),
);

Future<void> _tapPhotoPoint(
  WidgetTester tester,
  Offset normalized, {
  bool body = false,
}) async {
  final canvas = _photoCanvas(body: body);
  await tester.ensureVisible(canvas);
  await tester.pumpAndSettle();
  final bounds = tester.getRect(canvas);
  // The 80×120 fixture fits by height in this portrait phone layout.
  final photo = Rect.fromCenter(
    center: bounds.center,
    width: bounds.height * 2 / 3,
    height: bounds.height,
  );
  await tester.tapAt(
    Offset(
      photo.left + normalized.dx * photo.width,
      photo.top + normalized.dy * photo.height,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
