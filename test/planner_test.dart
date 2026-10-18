import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/planner_models.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/screens/planner_screen.dart';
import 'package:thread_style/theme.dart';

const _outfit = OutfitRecommendation(
  id: 'office-sage',
  title: 'The office regular',
  description: 'An easy office combination.',
  occasion: Occasion.office,
  shirt: ShirtColor(name: 'Sage', argb: 0xFF9BAE98),
  pants: OutfitPiece(
    category: 'Pants',
    title: 'chinos',
    colorName: 'Navy',
    colorArgb: 0xFF25394F,
  ),
  shoes: OutfitPiece(
    category: 'Shoes',
    title: 'loafers',
    colorName: 'Brown',
    colorArgb: 0xFF76563D,
  ),
  layer: OutfitPiece(
    category: 'Layer',
    title: 'blazer',
    colorName: 'Navy',
    colorArgb: 0xFF25394F,
  ),
  reasons: ['Balanced colors.'],
  fitAdvice: 'Choose a comfortable fit.',
);

void main() {
  test('plans preserve the calendar date and complete outfit through JSON', () {
    final plan = PlannedOutfit(
      id: 'plan-1',
      outfit: _outfit,
      date: DateTime.utc(2026, 10, 18, 23, 45),
      note: 'Team dinner',
    );
    expect(plan.date, DateTime(2026, 10, 18));
    expect(plan.toJson()['date'], '2026-10-18');
    final restored = PlannedOutfit.fromJson(plan.toJson());
    expect(restored.date, DateTime(2026, 10, 18));
    expect(restored.date.isUtc, isFalse);
    expect(restored.outfit.toJson(), _outfit.toJson());
    expect(restored.note, 'Team dinner');
    expect(restored.copyWith(date: DateTime(2026, 10, 20, 19)).id, plan.id);
    expect(restored.copyWith(note: '').note, '');
  });

  test('invalid stored calendar dates are rejected instead of shifted', () {
    final json = PlannedOutfit(
      id: 'p',
      outfit: _outfit,
      date: DateTime(2026, 10, 18),
    ).toJson();
    for (final date in [
      '2026-02-30',
      '2026-13-01',
      '2026-00-03',
      '0000-01-01',
      '2026-10-18T00:00:00Z',
      '2026-1-2',
      'bad',
      null,
    ]) {
      expect(
        () => PlannedOutfit.fromJson({...json, 'date': date}),
        throwsFormatException,
      );
    }
    expect(
      PlannedOutfit.fromJson({...json, 'date': '2028-02-29'}).date,
      DateTime(2028, 2, 29),
    );
    json.remove('note');
    expect(PlannedOutfit.fromJson(json).note, isEmpty);
  });

  testWidgets('planner empty state offers the studio without sample plans', (
    tester,
  ) async {
    var browsed = 0;
    await _pumpPlanner(tester, plans: [], onBrowse: () => browsed++);
    expect(find.text('Your calendar is a blank canvas.'), findsOneWidget);
    expect(find.text('Edit plan'), findsNothing);
    await tester.tap(find.text('Find an outfit to plan'));
    expect(browsed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'planner sorts upcoming and past days and dispatches edit and remove',
    (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final soon = PlannedOutfit(id: 'soon', outfit: _outfit, date: today);
      final later = PlannedOutfit(
        id: 'later',
        outfit: _outfit,
        date: DateTime(today.year, today.month, today.day + 3),
      );
      final past = PlannedOutfit(
        id: 'past',
        outfit: _outfit,
        date: DateTime(today.year, today.month, today.day - 1),
      );
      PlannedOutfit? edited;
      String? removed;
      await _pumpPlanner(
        tester,
        plans: [later, past, soon],
        onEdit: (plan) => edited = plan,
        onRemove: (id) => removed = id,
      );
      expect(find.text('Coming up'), findsOneWidget);
      expect(find.text('Past plans'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('plan_soon'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('plan_later'))).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('plan_later'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('plan_past'))).dy),
      );
      await _tap(tester, find.text('Edit plan').first);
      expect(edited?.id, 'soon');
      await _tap(tester, find.byTooltip('Remove plan').first);
      expect(removed, 'soon');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('plan dialog saves a chosen day and trimmed note', (
    tester,
  ) async {
    PlannedOutfit? result;
    await _pumpDialog(tester, onResult: (value) => result = value);
    await _tap(tester, find.byKey(const Key('plan_date')));
    await tester.enterText(find.byType(TextField).last, '10/20/2026');
    await _tap(tester, find.text('OK'));
    await tester.enterText(
      find.byKey(const Key('plan_note')),
      '  Bring a jacket  ',
    );
    await _tap(tester, find.byKey(const Key('save_plan')));
    expect(result?.date, DateTime(2026, 10, 20));
    expect(result?.note, 'Bring a jacket');
    expect(result?.outfit.id, _outfit.id);
    expect(result?.id, startsWith('plan-'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancel returns null and editing a past plan retains its identity',
    (tester) async {
      final existing = PlannedOutfit(
        id: 'old-plan',
        outfit: _outfit,
        date: DateTime(2026, 10, 1),
        note: 'Existing note',
      );
      PlannedOutfit? result = existing;
      await _pumpDialog(
        tester,
        existing: existing,
        onResult: (value) => result = value,
      );
      await _tap(tester, find.text('Cancel'));
      expect(result, isNull);
      await _tap(tester, find.text('Open planner'));
      expect(
        find.text(
          'This past plan is set to today. Choose another day if you like.',
        ),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const Key('save_plan')));
      expect(result?.id, 'old-plan');
      expect(result?.note, 'Existing note');
      expect(result?.date, DateTime(2026, 10, 18));
    },
  );

  testWidgets(
    'planner and dialog remain usable on a narrow phone with larger text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await _pumpPlanner(
        tester,
        plans: [
          PlannedOutfit(
            id: 'narrow',
            outfit: _outfit,
            date: DateTime.now(),
            note: 'Dinner with colleagues after the office.',
          ),
        ],
      );
      await _tap(tester, find.text('Edit plan'));
      expect(tester.takeException(), isNull);
      PlannedOutfit? result;
      await _pumpDialog(tester, onResult: (value) => result = value);
      await _tap(tester, find.byKey(const Key('plan_date')));
      await tester.enterText(find.byType(TextField).last, '10/22/2026');
      await _tap(tester, find.text('OK'));
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const Key('plan_note')),
        'Remember the jacket',
      );
      await _tap(tester, find.byKey(const Key('save_plan')));
      expect(result?.note, 'Remember the jacket');
      expect(result?.date, DateTime(2026, 10, 22));
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpPlanner(
  WidgetTester tester, {
  required List<PlannedOutfit> plans,
  VoidCallback? onBrowse,
  ValueChanged<PlannedOutfit>? onEdit,
  ValueChanged<String>? onRemove,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThreadTheme.theme,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: PlannerScreen(
            plans: plans,
            onBrowse: onBrowse ?? () {},
            onEdit: onEdit ?? (_) {},
            onRemove: onRemove ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required ValueChanged<PlannedOutfit?> onResult,
  PlannedOutfit? existing,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThreadTheme.theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
              await showPlanOutfitDialog(
                context,
                outfit: _outfit,
                existing: existing,
                now: DateTime(2026, 10, 18),
              ),
            ),
            child: const Text('Open planner'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, find.text('Open planner'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
