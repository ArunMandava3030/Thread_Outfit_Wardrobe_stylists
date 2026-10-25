import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/guest_app.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/widgets/garment_art.dart';

void main() {
  testWidgets(
    '320px enlarged text supports scanned pants, measured hints and completed outfit',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final bytes = await tester.runAsync(_fixture);
      await tester.pumpWidget(ThreadGuestApp(photoPicker: () async => bytes));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('guest_start_pants')));
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Scan design'))
            .didExceedMaxLines,
        isFalse,
      );
      await _tap(
        tester,
        find.byKey(const Key('guest_scan_design')),
        settle: false,
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Auto analyze'), findsNothing);
      final photo = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Photo. Tap an area to sample its colour.',
      );
      for (final fraction in [const Offset(.08, .1), const Offset(.92, .9)]) {
        await tester.ensureVisible(photo);
        await tester.pumpAndSettle();
        final box = tester.getRect(photo);
        final width = box.height * 2 / 3;
        final left = box.center.dx - width / 2;
        await tester.tapAt(
          Offset(
            left + width * fraction.dx,
            box.top + box.height * fraction.dy,
          ),
        );
        await tester.pumpAndSettle();
      }
      await _tap(tester, find.text('Use this design'));
      final anchor = tester.widget<GarmentArt>(find.byType(GarmentArt));
      expect(anchor.details.visualProfile?.isReliable, isTrue);
      expect(
        anchor.details.visualProfile!.palette.length,
        greaterThanOrEqualTo(2),
      );
      expect(tester.takeException(), isNull);
      await _tap(tester, find.byKey(const Key('guest_continue')));
      final matches = tester
          .widgetList<ChoiceChip>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is ChoiceChip &&
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith(
                    'guest_match_',
                  ),
            ),
          )
          .toList();
      expect(matches, hasLength(3));
      expect(matches.any((chip) => chip.label is Column), isTrue);
      expect(
        matches.map((chip) => chip.key).toSet(),
        hasLength(matches.length),
      );
      expect(tester.takeException(), isNull);
      await _tap(tester, find.byKey(const Key('guest_continue')));
      await _tap(tester, find.byKey(const Key('guest_occasion_date')));
      await _tap(tester, find.byKey(const Key('guest_generate')));
      final outfit = tester
          .widget<GuestOutfitCard>(find.byType(GuestOutfitCard))
          .outfit;
      expect(outfit.startingPiece, StartingPiece.pants);
      expect(outfit.pantsDetails.visualProfile?.isReliable, isTrue);
      expect(outfit.topDetails.visualProfile, isNull);
      expect(outfit.topDetails.pattern, GarmentPattern.solid);
      await _tap(tester, find.text('Why it works'));
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<Uint8List> _fixture() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 80, 120),
    Paint()..color = const Color(0xFFF4F2EB),
  );
  for (var y = 3; y < 120; y += 7) {
    for (var x = 2; x < 80; x += 9) {
      canvas.drawCircle(
        Offset((x + y % 5).toDouble(), y.toDouble()),
        ((x + y) % 3 + 1).toDouble(),
        Paint()..color = const Color(0xFF25394F),
      );
      canvas.drawLine(
        Offset(x.toDouble(), y.toDouble()),
        Offset((x + 4).toDouble(), (y + 3).toDouble()),
        Paint()
          ..color = const Color(0xFFC94F4F)
          ..strokeWidth = 1.5,
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
