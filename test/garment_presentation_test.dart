import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/planner_models.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/screens/planner_screen.dart';
import 'package:thread_style/services/style_engine.dart';
import 'package:thread_style/services/style_store.dart';
import 'package:thread_style/theme.dart';
import 'package:thread_style/widgets/garment_art.dart';
import 'package:thread_style/widgets/outfit_card.dart';

const _red = ShirtColor(name: 'Red', argb: 0xFFC94F4F);
const _navy = ShirtColor(name: 'Navy', argb: 0xFF25394F);
const _cream = ShirtColor(name: 'Cream', argb: 0xFFECE5D4);
const _checked = GarmentDetails(
  type: GarmentType.flannel,
  pattern: GarmentPattern.checks,
  accentColors: [_navy, _cream],
);

void main() {
  testWidgets(
    'changing type redraws the visible shirt sleeves neckline and trouser length',
    (tester) async {
      final boundary = GlobalKey();
      final shirt = await _pixels(
        tester,
        boundary,
        const GarmentDetails(type: GarmentType.shirt),
      );
      final tee = await _pixels(
        tester,
        boundary,
        const GarmentDetails(type: GarmentType.tShirt),
      );
      final flannel = await _pixels(
        tester,
        boundary,
        const GarmentDetails(type: GarmentType.flannel),
      );
      expect(tee, isNot(orderedEquals(shirt)));
      expect(flannel, isNot(orderedEquals(tee)));
      final trousers = await _pixels(
        tester,
        boundary,
        const GarmentDetails(type: GarmentType.trousers),
        kind: GarmentKind.pants,
      );
      final shorts = await _pixels(
        tester,
        boundary,
        const GarmentDetails(type: GarmentType.shorts),
        kind: GarmentKind.pants,
      );
      expect(shorts, isNot(orderedEquals(trousers)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pattern and reordered accent changes repaint an existing garment',
    (tester) async {
      final boundary = GlobalKey();
      final plain = await _pixels(
        tester,
        boundary,
        const GarmentDetails(type: GarmentType.flannel),
      );
      final checks = await _pixels(tester, boundary, _checked);
      final stripes = await _pixels(
        tester,
        boundary,
        _checked.copyWith(pattern: GarmentPattern.stripes),
      );
      expect(checks, isNot(orderedEquals(plain)));
      expect(stripes, isNot(orderedEquals(checks)));
      final blocksDetails = _checked.copyWith(
        pattern: GarmentPattern.colorBlock,
      );
      final reversedDetails = blocksDetails.copyWith(
        accentColors: [_cream, _navy],
      );
      // A saved garment's palette identity intentionally ignores order, but the
      // drawing uses the first accent for the upper block and must repaint.
      expect(blocksDetails.signature, reversedDetails.signature);
      final blocks = await _pixels(tester, boundary, blocksDetails);
      final reversed = await _pixels(tester, boundary, reversedDetails);
      expect(reversed, isNot(orderedEquals(blocks)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved and planned patterned looks keep accessible labels artwork and copied palette',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final look = const StyleEngine()
            .generateForItem(
              startingPiece: StartingPiece.shirt,
              color: _red,
              matchingColor: _navy,
              details: _checked,
              occasion: Occasion.casual,
              profile: const StyleProfile(),
            )
            .first;
        final plan = PlannedOutfit(
          id: 'pattern-plan',
          outfit: look,
          date: DateTime.now(),
          note: 'Wear the checked flannel',
        );
        final stored = StyleStore.decode(
          savedRaw: jsonEncode([look.toJson()]),
          plansRaw: jsonEncode([plan.toJson()]),
        );
        expect(stored.recoveryMessage, isNull);
        expect(stored.saved.single.topDetails.signature, _checked.signature);
        expect(
          stored.plans.single.outfit.topDetails.signature,
          _checked.signature,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThreadTheme.theme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: PlannerScreen(
                  plans: stored.plans,
                  onRemove: (_) {},
                  onEdit: (_) {},
                  onBrowse: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('checked flannel shirt'), findsOneWidget);
        expect(find.textContaining('Navy + Cream accents'), findsOneWidget);
        final plannedTop = tester.widget<GarmentArt>(
          find.byWidgetPredicate(
            (widget) =>
                widget is GarmentArt && widget.kind == GarmentKind.shirt,
          ),
        );
        expect(plannedTop.details.pattern, GarmentPattern.checks);
        expect(plannedTop.details.type, GarmentType.flannel);
        expect(plannedTop.details.accentColors.map((color) => color.argb), [
          _navy.argb,
          _cream.argb,
        ]);

        String? clipboard;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThreadTheme.theme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: OutfitCard(
                  outfit: stored.saved.single,
                  saved: true,
                  onSave: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel(
            RegExp('Red.*checked flannel shirt.*Navy.*Cream'),
          ),
          findsOneWidget,
        );
        await _tap(tester, find.text('Outfit details'));
        await _tap(tester, find.text('Copy outfit details'));
        expect(clipboard, contains('Checked flannel shirt'));
        expect(clipboard, contains('accents: Navy, Cream'));
        expect(clipboard, contains('Pants: Navy'));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}

Future<Uint8List> _pixels(
  WidgetTester tester,
  GlobalKey boundary,
  GarmentDetails details, {
  GarmentKind kind = GarmentKind.shirt,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: boundary,
          child: GarmentArt(
            kind: kind,
            color: const Color(0xFFC94F4F),
            details: details,
            size: 160,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
  return bytes!;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
