import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/learning_models.dart';
import 'package:thread_style/models/outfit_rating_models.dart';
import 'package:thread_style/models/style_discovery_models.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/models/trend_models.dart';
import 'package:thread_style/services/outfit_rater.dart';

const _white = ShirtColor(name: 'White', argb: 0xFFF4F2EB);
const _navy = ShirtColor(name: 'Navy', argb: 0xFF25394F);
const _red = ShirtColor(name: 'Red', argb: 0xFFC94F4F);

OutfitRatingInput _input({
  RatingTop top = RatingTop.shirt,
  ShirtColor topColor = _white,
  RatingBottom bottom = RatingBottom.chinos,
  RatingShoes shoes = RatingShoes.sneakers,
  RatingLayer layer = RatingLayer.none,
  ShirtColor layerColor = _navy,
  Occasion occasion = Occasion.casual,
  bool trends = false,
  StyleDirection direction = StyleDirection.smartCasual,
  FitComfort comfort = FitComfort.unknown,
  TrouserHem hem = TrouserHem.unknown,
  SilhouetteFit silhouette = SilhouetteFit.unknown,
}) => OutfitRatingInput(
  top: top,
  topColor: topColor,
  bottom: bottom,
  pantsColor: _navy,
  shoes: shoes,
  shoesColor: _white,
  layer: layer,
  layerColor: layerColor,
  occasion: occasion,
  direction: direction,
  includeTrends: trends,
  comfort: comfort,
  hem: hem,
  silhouette: silhouette,
);

final _now = DateTime.utc(2026, 10, 18, 12);
TrendSnapshot _snapshot({
  Duration age = Duration.zero,
  Duration articleAge = const Duration(days: 2),
  bool available = true,
  bool match = true,
}) => TrendSnapshot(
  fetchedAt: _now.subtract(age),
  sources: [TrendSourceStatus(name: 'GQ', available: available)],
  headlines: [
    TrendHeadline(
      headline: match
          ? 'A guide to the new tailored blazer'
          : 'Running gear for autumn',
      url: 'https://www.gq.com/story/new-blazer',
      publisher: 'GQ',
      publishedAt: _now.subtract(articleAge),
    ),
  ],
);

void main() {
  const rater = OutfitRater();

  test('scores are finite and bounded across every garment and occasion', () {
    for (final occasion in Occasion.values) {
      for (final bottom in RatingBottom.values) {
        for (final shoes in RatingShoes.values) {
          final result = rater.rate(
            _input(occasion: occasion, bottom: bottom, shoes: shoes),
          );
          expect(result.score.isFinite, isTrue);
          expect(result.score, inInclusiveRange(0, 5));
        }
      }
    }
  });

  test(
    'skin, height and body shape tailor advice without changing the score',
    () {
      final input = _input();
      final baseline = rater.rate(input);
      for (final shape in BodyShape.values) {
        for (final skin in [0xFF432719, 0xFFC68642, 0xFFF5DECE]) {
          final result = rater.rate(
            input,
            hasProfile: true,
            profile: StyleProfile(
              heightCm: shape == BodyShape.balanced ? 152 : 196,
              bodyShape: shape,
              skinToneArgb: skin,
              useSkinTone: true,
              undertone: Undertone.warm,
            ),
          );
          expect(result.score, baseline.score);
          expect(result.profileAdvice.join(' '), contains('saved'));
          expect(result.profileAdvice.join(' '), contains('skin swatch'));
          expect(
            result.profileAdvice.join(' '),
            contains('never lower your score'),
          );
        }
      }
    },
  );

  test(
    'skin opt-out excludes skin advice and absent profile excludes default height',
    () {
      final hidden = rater.rate(
        _input(),
        profile: const StyleProfile(
          skinToneArgb: 0xFFC68642,
          useSkinTone: true,
        ),
      );
      expect(hidden.profileAdvice.join(' '), isNot(contains('175')));
      expect(hidden.profileAdvice.join(' '), isNot(contains('skin swatch')));
      final optedOut = rater.rate(
        _input(),
        hasProfile: true,
        profile: const StyleProfile(skinToneArgb: 0xFFC68642),
      );
      expect(optedOut.profileAdvice.join(' '), isNot(contains('skin swatch')));
    },
  );

  test(
    'fit is not invented; reported discomfort produces actionable changes',
    () {
      final unknown = rater.rate(_input());
      final comfortable = rater.rate(
        _input(
          comfort: FitComfort.comfortable,
          hem: TrouserHem.clear,
          silhouette: SilhouetteFit.intended,
        ),
      );
      final restrictive = rater.rate(
        _input(
          comfort: FitComfort.restrictive,
          hem: TrouserHem.dragging,
          silhouette: SilhouetteFit.different,
        ),
      );
      expect(
        unknown.components.map((component) => component.label),
        isNot(contains('Observed fit')),
      );
      expect(unknown.suggestions.join(' '), contains('currently unscored'));
      expect(restrictive.score, lessThan(comfortable.score));
      expect(restrictive.suggestions.join(' '), contains('Shorten or cuff'));
      final shorts = rater.rate(
        _input(bottom: RatingBottom.shorts, hem: TrouserHem.dragging),
      );
      expect(
        shorts.components.map((component) => component.label),
        isNot(contains('Observed fit')),
      );
    },
  );

  test(
    'formal and motorcycle recommendations use actual garment categories',
    () {
      final beachClothes = _input(
        occasion: Occasion.special,
        top: RatingTop.tee,
        bottom: RatingBottom.shorts,
        shoes: RatingShoes.sandals,
      );
      final formal = _input(
        occasion: Occasion.special,
        bottom: RatingBottom.tailored,
        shoes: RatingShoes.dress,
        layer: RatingLayer.blazer,
      );
      expect(
        rater.rate(beachClothes).score,
        lessThan(rater.rate(formal).score),
      );
      expect(
        rater.rate(beachClothes).suggestions.join(' '),
        contains('formal'),
      );
      final riding = rater.rate(_input(occasion: Occasion.bikeRide));
      expect(riding.outfit.safetyNote, contains('cannot verify'));
      expect(riding.suggestions.join(' '), contains('helmet and gloves'));
    },
  );

  test(
    'only opted-in fresh sourced headlines provide a small direction bonus',
    () {
      final baseline = rater.rate(_input(), now: _now, trends: _snapshot());
      final fresh = rater.rate(
        _input(trends: true),
        now: _now,
        trends: _snapshot(),
      );
      expect(baseline.trendAdjustment, 0);
      expect(fresh.trendAdjustment, .1);
      expect(fresh.score - baseline.score, closeTo(.1, .000001));
      expect(fresh.trendEvidence?.publisher, 'GQ');
      for (final snapshot in [
        _snapshot(age: const Duration(hours: 49)),
        _snapshot(age: const Duration(minutes: -10)),
        _snapshot(articleAge: const Duration(days: 31)),
        _snapshot(articleAge: const Duration(days: -1)),
        _snapshot(available: false),
        _snapshot(match: false),
      ]) {
        final ignored = rater.rate(
          _input(trends: true),
          trends: snapshot,
          now: _now,
        );
        expect(ignored.trendAdjustment, 0);
        expect(ignored.score, baseline.score);
      }
    },
  );

  test('a style label alone cannot earn a headline bonus', () {
    final runningHeadline = _snapshot(match: false);
    final mismatched = rater.rate(
      _input(
        trends: true,
        direction: StyleDirection.athleisure,
        bottom: RatingBottom.tailored,
        shoes: RatingShoes.dress,
        layer: RatingLayer.blazer,
      ),
      trends: runningHeadline,
      now: _now,
    );
    expect(mismatched.trendAdjustment, 0);
    expect(mismatched.trendEvidence, isNull);
    final compatible = rater.rate(
      _input(
        trends: true,
        direction: StyleDirection.athleisure,
        top: RatingTop.tee,
        bottom: RatingBottom.track,
      ),
      trends: runningHeadline,
      now: _now,
    );
    expect(compatible.trendAdjustment, .1);
    expect(compatible.trendEvidence, isNotNull);
  });

  test('preference learning changes scores only within the documented cap', () {
    final input = _input();
    final likes = [
      StyleFeedbackEntry(
        outfit: input.toOutfit(),
        feedback: StyleFeedback.like,
        updatedAt: _now,
      ),
    ];
    final dislikes = [
      StyleFeedbackEntry(
        outfit: input.toOutfit(),
        feedback: StyleFeedback.dislike,
        updatedAt: _now,
      ),
    ];
    final liked = rater.rate(input, history: likes);
    final disliked = rater.rate(input, history: dislikes);
    expect(liked.preferenceAdjustment, inExclusiveRange(0, .25));
    expect(disliked.preferenceAdjustment, inExclusiveRange(-.25, 0));
    expect(liked.score, greaterThan(disliked.score));
    expect(
      rater
          .rate(input, history: List.filled(30, likes.single))
          .preferenceAdjustment,
      liked.preferenceAdjustment,
    );
  });

  test(
    'favorites have stable IDs for actual garment colors, categories and layers',
    () {
      final original = _input().toOutfit();
      expect(rater.rate(_input()).outfit.id, original.id);
      expect(
        _input(comfort: FitComfort.comfortable).toOutfit().id,
        original.id,
      );
      expect(
        _input(layerColor: _red).toOutfit().id,
        original.id,
        reason: 'Unused layer colors do not split a favorite.',
      );
      for (final changed in [
        _input(topColor: _red),
        _input(top: RatingTop.polo),
        _input(bottom: RatingBottom.jeans),
        _input(shoes: RatingShoes.loafers),
        _input(layer: RatingLayer.blazer),
        _input(occasion: Occasion.party),
      ]) {
        expect(changed.toOutfit().id, isNot(original.id));
      }
      expect(original.layer.colorArgb, 0);
      expect(original.shirtTitle, 'Button-up shirt');
      expect(OutfitRecommendation.fromJson(original.toJson()).id, original.id);
    },
  );
}
