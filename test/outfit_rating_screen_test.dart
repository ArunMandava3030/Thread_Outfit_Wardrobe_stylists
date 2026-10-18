import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/screens/outfit_rating_screen.dart';
import 'package:thread_style/theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Future<void> Function(OutfitRecommendation) onFavorite,
  double scale = 1,
  Future<ShirtColor?> Function(String)? onPickColor,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThreadTheme.theme,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 800),
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
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('rating-Top-color-Red')),
      );
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
      await _tapVisible(tester, find.text('Read Pants color from photo'));
      expect(target, 'Pants');
      expect(find.text('Pants color: Photo teal'), findsOneWidget);
      await _tapVisible(tester, find.byKey(const Key('rate_current_outfit')));
      await _tapVisible(tester, find.byKey(const Key('favorite_rated_outfit')));
      expect(saved?.pants.colorArgb, 0xFF367E7F);
      expect(saved?.shirt.argb, ShirtColor.presets[3].argb);
    },
  );

  testWidgets('narrow screen supports enlarged text and a complete rating', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, onFavorite: (_) async {}, scale: 1.6);
    await _tapVisible(tester, find.byKey(const Key('rate_current_outfit')));
    await _tapVisible(tester, find.byKey(const Key('favorite_rated_outfit')));
    expect(find.text('Saved to favorites'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
