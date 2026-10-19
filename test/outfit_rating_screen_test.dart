import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/models/trend_models.dart';
import 'package:thread_style/screens/outfit_rating_screen.dart';
import 'package:thread_style/services/trend_service.dart';
import 'package:thread_style/theme.dart';

class _DeferredTrends extends TrendService {
  final response = Completer<TrendSnapshot>();

  @override
  Future<TrendSnapshot> fetchTrends() => response.future;
}

Future<void> _pump(
  WidgetTester tester, {
  required Future<void> Function(OutfitRecommendation) onFavorite,
  double scale = 1,
  Size viewport = const Size(390, 844),
  Future<ShirtColor?> Function(String)? onPickColor,
  TrendService? trendService,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThreadTheme.theme,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: viewport,
            textScaler: TextScaler.linear(scale),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: OutfitRatingScreen(
                profile: const StyleProfile(),
                hasProfile: false,
                history: const [],
                onFavorite: onFavorite,
                onPickColor: onPickColor,
                trendService: trendService,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('basic rating fits on a phone without opening extra options', (
    tester,
  ) async {
    await _pump(tester, onFavorite: (_) async {});
    for (final garment in ['Top', 'Pants', 'Shoes', 'Layer']) {
      expect(
        find.byKey(ValueKey('rating-edit-$garment')).hitTestable(),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const Key('rate_current_outfit')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Dress code'), findsNothing);
    expect(find.text('Include current trends'), findsNothing);
    expect(find.byKey(const ValueKey('rating-Top-color-Red')), findsNothing);
    await tester.tap(find.byKey(const Key('rate_current_outfit')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('outfit_rating_score')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(const Key('rating_edit_outfit')), findsOneWidget);
    expect(find.byKey(const Key('rate_current_outfit')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rating saves a confirmed snapshot and edits invalidate the result',
    (tester) async {
      OutfitRecommendation? saved;
      await _pump(tester, onFavorite: (outfit) async => saved = outfit);
      expect(find.byKey(const Key('outfit_rating_result')), findsNothing);
      await _tapVisible(tester, find.byKey(const Key('rate_current_outfit')));
      expect(find.byKey(const Key('outfit_rating_score')), findsOneWidget);
      await _tapVisible(tester, find.byKey(const Key('favorite_rated_outfit')));
      expect(saved?.shirt.argb, ShirtColor.presets[3].argb);
      expect(saved?.pants.colorArgb, ShirtColor.presets[2].argb);
      expect(find.text('Saved to favorites'), findsOneWidget);
      await _tapVisible(tester, find.byKey(const Key('rating_edit_outfit')));
      await _tapVisible(tester, find.byKey(const ValueKey('rating-edit-Top')));
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('rating-Top-color-Red')),
      );
      await _tapVisible(tester, find.byKey(const Key('rating-editor-done')));
      expect(find.byKey(const Key('outfit_rating_result')), findsNothing);
      await _tapVisible(tester, find.byKey(const Key('rate_current_outfit')));
      await _tapVisible(tester, find.byKey(const Key('favorite_rated_outfit')));
      expect(saved?.shirt.name, 'Red');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed favorite can be retried and is not labeled saved', (
    tester,
  ) async {
    var saves = 0;
    await _pump(
      tester,
      onFavorite: (_) async {
        saves++;
        throw StateError('Storage unavailable');
      },
    );
    await _tapVisible(tester, find.byKey(const Key('rate_current_outfit')));
    await _tapVisible(tester, find.byKey(const Key('favorite_rated_outfit')));
    expect(find.text('Saved to favorites'), findsNothing);
    expect(
      find.text('The favorite could not be saved. Please try again.'),
      findsOneWidget,
    );
    expect(saves, 1);
    await tester.pump(const Duration(seconds: 5));
    await _tapVisible(tester, find.byKey(const Key('favorite_rated_outfit')));
    expect(saves, 2);
  });

  testWidgets(
    'photo color edits the requested garment without claiming fit detection',
    (tester) async {
      String? target;
      OutfitRecommendation? saved;
      await _pump(
        tester,
        onFavorite: (outfit) async => saved = outfit,
        onPickColor: (garment) async {
          target = garment;
          return const ShirtColor(name: 'Photo teal', argb: 0xFF367E7F);
        },
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('rating-edit-Pants')),
      );
      await _tapVisible(tester, find.byKey(const Key('rating-editor-photo')));
      expect(target, 'Pants');
      expect(find.text('Pants color: Photo teal'), findsOneWidget);
      await _tapVisible(tester, find.byKey(const Key('rating-editor-done')));
      await _tapVisible(tester, find.byKey(const Key('rate_current_outfit')));
      await _tapVisible(tester, find.byKey(const Key('favorite_rated_outfit')));
      expect(saved?.pants.colorArgb, 0xFF367E7F);
      expect(saved?.shirt.argb, ShirtColor.presets[3].argb);
    },
  );

  testWidgets(
    'canceling a garment edit leaves the confirmed outfit unchanged',
    (tester) async {
      OutfitRecommendation? saved;
      await _pump(tester, onFavorite: (outfit) async => saved = outfit);
      await _tapVisible(tester, find.byKey(const ValueKey('rating-edit-Top')));
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('rating-Top-color-Red')),
      );
      await _tapVisible(tester, find.byKey(const Key('rating-editor-cancel')));
      await _tapVisible(tester, find.byKey(const Key('rate_current_outfit')));
      await _tapVisible(tester, find.byKey(const Key('favorite_rated_outfit')));
      expect(saved?.shirt.argb, ShirtColor.presets[3].argb);
    },
  );

  testWidgets('late optional headlines keep the completed rating visible', (
    tester,
  ) async {
    final trends = _DeferredTrends();
    addTearDown(trends.dispose);
    await _pump(tester, onFavorite: (_) async {}, trendService: trends);
    await _tapVisible(tester, find.text('More options'));
    await _tapVisible(tester, find.text('Include current trends'));
    await _tapVisible(tester, find.byKey(const Key('rate_current_outfit')));
    expect(find.byKey(const Key('outfit_rating_score')), findsOneWidget);
    trends.response.complete(
      TrendSnapshot(
        fetchedAt: DateTime.now().toUtc(),
        headlines: const [],
        sources: const [],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('outfit_rating_score')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(const Key('rate_current_outfit')), findsNothing);
    await _tapVisible(tester, find.byKey(const Key('rating_edit_outfit')));
    expect(find.text('Include current trends'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow screen supports enlarged text and a complete rating', (
    tester,
  ) async {
    await _pump(
      tester,
      onFavorite: (_) async {},
      scale: 1.6,
      viewport: const Size(320, 800),
    );
    await _tapVisible(tester, find.byKey(const ValueKey('rating-edit-Layer')));
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('rating-Layer type-none')),
    );
    await _tapVisible(tester, find.text('Casual jacket').last);
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('rating-Layer-color-Navy')),
    );
    await _tapVisible(tester, find.byKey(const Key('rating-editor-done')));
    await _tapVisible(tester, find.byKey(const Key('rate_current_outfit')));
    // The result must reveal itself without another scroll after submitting.
    expect(
      find.byKey(const Key('outfit_rating_score')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('favorite_rated_outfit')).hitTestable(),
      findsOneWidget,
    );
    await _tapVisible(tester, find.byKey(const Key('favorite_rated_outfit')));
    expect(find.text('Saved to favorites'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
