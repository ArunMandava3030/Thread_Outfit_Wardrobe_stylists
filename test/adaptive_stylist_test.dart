import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thread_style/models/learning_models.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/services/adaptive_stylist.dart';
import 'package:thread_style/services/style_engine.dart';

void main() {
  const stylist = AdaptiveStylist();
  final outfits = const StyleEngine().generate(
    shirt: ShirtColor.presets.first,
    occasion: Occasion.casual,
    profile: const StyleProfile(),
  );
  final now = DateTime.utc(2026, 10, 18);

  test('cold start preserves curated order and returns a neutral score', () {
    final reversed = outfits.reversed.toList();
    expect(stylist.rank(reversed, []), orderedEquals(reversed));
    expect(stylist.preferenceScore(outfits.first, []), 0.5);
    expect(stylist.rank([], []), isEmpty);
  });

  test('a like promotes the known style and a dislike demotes it', () {
    final likes = stylist.record(
      [],
      outfits.last,
      StyleFeedback.like,
      now: now,
    );
    expect(stylist.rank(outfits, likes).first.id, outfits.last.id);
    expect(stylist.preferenceScore(outfits.last, likes), greaterThan(0.5));

    final dislikes = stylist.record(
      [],
      outfits.first,
      StyleFeedback.dislike,
      now: now,
    );
    expect(stylist.rank(outfits, dislikes).last.id, outfits.first.id);
    expect(stylist.preferenceScore(outfits.first, dislikes), lessThan(0.5));
  });

  test('learned preferences generalize to unseen IDs and nearby colors', () {
    final likes = stylist.record(
      [],
      outfits.last,
      StyleFeedback.like,
      now: now,
    );
    final related = _copy(outfits.last, {
      'id': 'unseen-related-outfit',
      'shirt': {'name': 'Nearby sample', 'argb': 0xFF9BAF98},
      'pants': {
        ...outfits.last.pants.toJson(),
        'colorArgb': outfits.last.pants.colorArgb + 1,
      },
    });
    expect(stylist.rank([outfits.first, related], likes).first.id, related.id);
  });

  test(
    'opposite occasion preferences can be learned for the same garments',
    () {
      final office = _copy(outfits.first, {
        'id': 'office-version',
        'occasion': Occasion.office.name,
      });
      final beach = _copy(outfits.first, {
        'id': 'beach-version',
        'occasion': Occasion.beach.name,
      });
      final history = stylist.record(
        stylist.record([], office, StyleFeedback.like, now: now),
        beach,
        StyleFeedback.dislike,
        now: now.add(const Duration(seconds: 1)),
      );
      expect(stylist.preferenceScore(office, history), greaterThan(0.5));
      expect(stylist.preferenceScore(beach, history), lessThan(0.5));
    },
  );

  test('IDs and profile-derived advice do not become model features', () {
    final modified = _copy(outfits.last, {
      'id': 'different-id',
      'title': 'Different marketing title',
      'description': 'Different description',
      'reasons': ['Different skin tone and undertone advice'],
      'fitAdvice': 'Different height and body shape advice',
    });
    final history = stylist.record(
      [],
      outfits.last,
      StyleFeedback.like,
      now: now,
    );
    expect(
      stylist.preferenceScore(modified, history),
      stylist.preferenceScore(outfits.last, history),
    );
    expect(
      stylist.rank([modified, outfits.last], history),
      orderedEquals([modified, outfits.last]),
    );
  });

  test('changing or clearing a vote removes its old training contribution', () {
    final liked = stylist.record(
      [],
      outfits.last,
      StyleFeedback.like,
      now: now,
    );
    final changed = stylist.record(
      liked,
      outfits.last,
      StyleFeedback.dislike,
      now: now.add(const Duration(minutes: 1)),
    );
    expect(changed, hasLength(1));
    expect(changed.single.feedback, StyleFeedback.dislike);
    expect(stylist.preferenceScore(outfits.last, changed), lessThan(0.5));
    final removed = stylist.record(changed, outfits.last, null, now: now);
    expect(removed, isEmpty);
    expect(stylist.rank(outfits, removed), orderedEquals(outfits));
  });

  test(
    'repeating the same label is idempotent and cannot amplify preference',
    () {
      final original = stylist.record(
        [],
        outfits.last,
        StyleFeedback.like,
        now: now,
      );
      var history = original;
      for (var index = 0; index < 100; index++) {
        history = stylist.record(
          history,
          outfits.last,
          StyleFeedback.like,
          now: now.add(Duration(seconds: index + 1)),
        );
      }
      expect(history, hasLength(1));
      expect(history.single.updatedAt, now);
      expect(
        stylist.preferenceScore(outfits.last, history),
        stylist.preferenceScore(outfits.last, original),
      );
      expect(
        stylist.preferenceScore(
          outfits.last,
          List.filled(500, original.single),
        ),
        stylist.preferenceScore(outfits.last, original),
      );
    },
  );

  test('history is capped at the most recent 200 distinct outfit votes', () {
    var history = <StyleFeedbackEntry>[];
    for (var index = 0; index < 205; index++) {
      history = stylist.record(
        history,
        _copy(outfits.first, {'id': 'outfit-$index'}),
        index.isEven ? StyleFeedback.like : StyleFeedback.dislike,
        now: now.add(Duration(seconds: index)),
      );
    }
    expect(history, hasLength(AdaptiveStylist.maxHistory));
    expect(history.first.outfit.id, 'outfit-5');
    expect(history.last.outfit.id, 'outfit-204');
    final score = stylist.preferenceScore(outfits.first, history);
    expect(score.isFinite, isTrue);
    expect(score, inInclusiveRange(0.0, 1.0));
  });

  test(
    'unordered imported history uses the latest vote and trains deterministically',
    () {
      final oldVote = StyleFeedbackEntry(
        outfit: outfits.last,
        feedback: StyleFeedback.like,
        updatedAt: now,
      );
      final newVote = StyleFeedbackEntry(
        outfit: outfits.last,
        feedback: StyleFeedback.dislike,
        updatedAt: now.add(const Duration(minutes: 1)),
      );
      final imported = [newVote, oldVote];
      expect(
        stylist.preferenceScore(outfits.last, imported),
        stylist.preferenceScore(outfits.last, [newVote]),
      );
      expect(
        stylist.rank(outfits, imported),
        orderedEquals(stylist.rank(outfits, imported.reversed.toList())),
      );
    },
  );

  test(
    'feedback snapshots survive JSON and invalid labels/dates are rejected',
    () {
      final original = StyleFeedbackEntry(
        outfit: outfits.last,
        feedback: StyleFeedback.like,
        updatedAt: now,
      );
      final decoded = StyleFeedbackEntry.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.toJson(), original.toJson());
      expect(
        () => StyleFeedbackEntry.fromJson({
          ...original.toJson(),
          'feedback': 'maybe',
        }),
        throwsFormatException,
      );
      expect(
        () => StyleFeedbackEntry.fromJson({
          ...original.toJson(),
          'updatedAt': 'not-a-date',
        }),
        throwsFormatException,
      );
    },
  );
}

OutfitRecommendation _copy(
  OutfitRecommendation outfit,
  Map<String, dynamic> changes,
) => OutfitRecommendation.fromJson({...outfit.toJson(), ...changes});
