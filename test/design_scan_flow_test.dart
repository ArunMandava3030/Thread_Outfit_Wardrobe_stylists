import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/guest_app.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/widgets/garment_art.dart';

Future<Uint8List> _design() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const Color(0xFF203F70), BlendMode.src);
  final cream = ui.Paint()..color = const Color(0xFFF0E4C8);
  final orange = ui.Paint()..color = const Color(0xFFD26532);
  for (var y = 15; y < 160; y += 29) {
    for (var x = 12; x < 160; x += 31) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x.toDouble(), y.toDouble()),
          width: 17,
          height: 10,
        ),
        cream,
      );
      canvas.drawCircle(Offset(x + 7.0, y + 9.0), 3, orange);
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(160, 160);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return Uint8List.fromList(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'photo design flows to suggestions and art with no manual category',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = await tester.runAsync(_design);
      await tester.pumpWidget(ThreadGuestApp(photoPicker: () async => bytes));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guest_scan_design')));
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; i < 150; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find
              .byKey(const Key('photo_sample_canvas'))
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
      });
      await tester.pumpAndSettle();
      final photo = find.byKey(const Key('photo_sample_canvas'));
      await tester.ensureVisible(photo);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(photo);
      final side = bounds.width < bounds.height ? bounds.width : bounds.height;
      final area = Rect.fromCenter(
        center: bounds.center,
        width: side,
        height: side,
      );
      await tester.tapAt(Offset(area.left + side * .04, area.top + side * .04));
      await tester.pumpAndSettle();
      await tester.tapAt(Offset(area.left + side * .96, area.top + side * .96));
      await tester.pumpAndSettle();
      expect(find.text('Photo estimate'), findsOneWidget);
      await _tap(tester, find.text('Use this design'));
      final startingArt = tester.widget<GarmentArt>(
        find.byType(GarmentArt).first,
      );
      final profile = startingArt.details.visualProfile!;
      expect(profile.isReliable, isTrue);
      expect(profile.palette.length, greaterThanOrEqualTo(3));
      expect(startingArt.details.pattern, GarmentPattern.solid);
      await _tap(tester, find.byKey(const Key('guest_continue')));
      expect(find.text('Quiet neutral'), findsOneWidget);
      expect(find.text('Photo estimate'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('guest_continue')));
      await _tap(tester, find.byKey(const Key('guest_generate')));
      final outfitArt = tester.widget<OutfitArt>(find.byType(OutfitArt).first);
      expect(outfitArt.topDetails.visualProfile!.signature, profile.signature);
      expect(outfitArt.topDetails.pattern, GarmentPattern.solid);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled or failed photo choice keeps the current outfit editable',
    (tester) async {
      var fail = false;
      await tester.pumpWidget(
        ThreadGuestApp(
          photoPicker: () async {
            if (fail) {
              throw const FormatException('Choose a photo smaller than 25 MB.');
            }
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('guest_scan_design')));
      expect(find.byKey(const Key('guest_continue')), findsOneWidget);
      fail = true;
      await _tap(tester, find.byKey(const Key('guest_scan_design')));
      expect(find.text('Choose a photo smaller than 25 MB.'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('guest_continue')));
      expect(find.text('Choose your pants color'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
