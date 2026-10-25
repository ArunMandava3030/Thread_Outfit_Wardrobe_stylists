import 'dart:math' as math;

import '../models/learning_models.dart';
import '../models/style_models.dart';

/// Small, local content-based preference model, trained only on explicit votes.
///
/// Logistic regression learns weights by minimizing binary cross entropy with
/// deterministic stochastic gradient descent and L2 regularization. Every call
/// fits from scratch using the latest unique labels, so removing or changing a
/// vote removes its previous contribution. It needs no server or ML runtime.
///
/// Features describe garment words, RGB/chroma/lightness, garment contrasts and
/// layer presence. Unit-normalized global and occasion-specific copies let a
/// preference transfer while preserving context (e.g. sneakers for casual days).
/// Outfit IDs, editorial copy, height, body shape and skin tone are not features.
/// This reorders existing suggestions; it cannot invent or validate new outfits.
class AdaptiveStylist {
  const AdaptiveStylist();

  static const int maxHistory = 200;
  static const int _epochs = 40;
  static const double _regularization = 0.04;

  List<OutfitRecommendation> rank(
    List<OutfitRecommendation> candidates,
    List<StyleFeedbackEntry> history,
  ) {
    final entries = _boundedHistory(history);
    if (entries.isEmpty || candidates.length < 2) {
      return List<OutfitRecommendation>.unmodifiable(candidates);
    }
    final weights = _train(entries);
    final scored = [
      for (var index = 0; index < candidates.length; index++)
        (
          outfit: candidates[index],
          index: index,
          score: _dot(weights, _features(candidates[index])),
        ),
    ];
    scored.sort((a, b) {
      final difference = b.score - a.score;
      // Keep the original curated order when numerical scores are tied.
      if (difference.abs() < 1e-10) return a.index.compareTo(b.index);
      return b.score.compareTo(a.score);
    });
    return List<OutfitRecommendation>.unmodifiable(
      scored.map((item) => item.outfit),
    );
  }

  /// Relative preference in [0, 1], NOT calibrated confidence or outfit quality.
  /// No feedback yields a neutral 0.5. Avoid presenting this as a match percent.
  double preferenceScore(
    OutfitRecommendation outfit,
    List<StyleFeedbackEntry> history,
  ) {
    final entries = _boundedHistory(history);
    if (entries.isEmpty) return 0.5;
    return _sigmoid(_dot(_train(entries), _features(outfit)));
  }

  /// Null clears a vote. Repeated identical votes are idempotent. Records are
  /// returned oldest first, with only the latest 200 distinct outfit IDs kept.
  List<StyleFeedbackEntry> record(
    List<StyleFeedbackEntry> history,
    OutfitRecommendation outfit,
    StyleFeedback? feedback, {
    DateTime? now,
  }) {
    final current = _boundedHistory(history);
    for (final entry in current) {
      if (entry.outfit.id == outfit.id && entry.feedback == feedback) {
        return current;
      }
    }
    return _boundedHistory([
      for (final entry in current)
        if (entry.outfit.id != outfit.id) entry,
      if (feedback != null)
        StyleFeedbackEntry(
          outfit: outfit,
          feedback: feedback,
          updatedAt: (now ?? DateTime.now()).toUtc(),
        ),
    ]);
  }

  List<StyleFeedbackEntry> _boundedHistory(List<StyleFeedbackEntry> history) {
    final latest = <String, StyleFeedbackEntry>{};
    for (final entry in history) {
      final previous = latest[entry.outfit.id];
      if (previous == null || !entry.updatedAt.isBefore(previous.updatedAt)) {
        latest[entry.outfit.id] = entry;
      }
    }
    final sorted = latest.values.toList()
      ..sort((a, b) {
        final timeOrder = a.updatedAt.compareTo(b.updatedAt);
        return timeOrder != 0 ? timeOrder : a.outfit.id.compareTo(b.outfit.id);
      });
    return List<StyleFeedbackEntry>.unmodifiable(
      sorted.skip(math.max(0, sorted.length - maxHistory)),
    );
  }

  Map<String, double> _train(List<StyleFeedbackEntry> entries) {
    final samples = [
      for (final entry in entries)
        (
          features: _features(entry.outfit),
          target: entry.feedback == StyleFeedback.like ? 1.0 : 0.0,
        ),
    ];
    final weights = <String, double>{};
    final order = List<int>.generate(samples.length, (index) => index);
    final random = math.Random(37);
    for (var epoch = 0; epoch < _epochs; epoch++) {
      // Seeded shuffling avoids depending on UI candidate order and limits the
      // effect of a run of consecutive likes/dislikes in stored history.
      order.shuffle(random);
      final rate = 0.65 / math.sqrt(1 + epoch * 0.15);
      final decay = 1 - rate * _regularization / samples.length;
      for (final index in order) {
        final sample = samples[index];
        final error = sample.target - _sigmoid(_dot(weights, sample.features));
        // Apply the L2 term to all weights, including currently absent features.
        // Divide by sample count so regularization per epoch is size-stable.
        weights.updateAll((key, value) => value * decay);
        for (final feature in sample.features.entries) {
          weights.update(
            feature.key,
            (value) => value + rate * error * feature.value,
            ifAbsent: () => rate * error * feature.value,
          );
        }
      }
    }
    return weights;
  }

  Map<String, double> _features(OutfitRecommendation outfit) {
    final hasLayer = ((outfit.layer.colorArgb >> 24) & 255) > 0;
    final base = <String, double>{
      'bias': 1,
      'layer-present': hasLayer ? 1 : -1,
    };
    _colorFeatures(base, 'shirt', outfit.shirt.argb);
    _colorFeatures(base, 'pants', outfit.pants.colorArgb);
    _colorFeatures(base, 'shoes', outfit.shoes.colorArgb);
    _garmentFeatures(base, 'pants', outfit.pants.title);
    _garmentFeatures(base, 'top', outfit.shirtTitle);
    _detailFeatures(base, 'top', outfit.topDetails);
    _detailFeatures(base, 'pants', outfit.pantsDetails);
    _garmentFeatures(base, 'shoes', outfit.shoes.title);
    if (hasLayer) {
      _colorFeatures(base, 'layer', outfit.layer.colorArgb);
      _garmentFeatures(base, 'layer', outfit.layer.title);
      _contrastFeatures(
        base,
        'shirt-layer',
        outfit.shirt.argb,
        outfit.layer.colorArgb,
      );
    }
    _contrastFeatures(
      base,
      'shirt-pants',
      outfit.shirt.argb,
      outfit.pants.colorArgb,
    );
    _contrastFeatures(
      base,
      'pants-shoes',
      outfit.pants.colorArgb,
      outfit.shoes.colorArgb,
    );

    final norm = math.sqrt(
      base.values.fold<double>(0, (sum, value) => sum + value * value),
    );
    return {
      for (final feature in base.entries)
        'shared:${feature.key}': 0.6 * feature.value / norm,
      for (final feature in base.entries)
        '${outfit.occasion.name}:${feature.key}': 0.8 * feature.value / norm,
    };
  }

  void _detailFeatures(
    Map<String, double> features,
    String garment,
    GarmentDetails details,
  ) {
    // Legacy votes have no invented category/pattern labels. Confirmed patterns
    // and colors transfer to new outfits without treating outfit IDs as inputs.
    if (!details.isSpecified) return;
    if (details.type != null) {
      features['$garment:type:${details.type!.name}'] = 1;
    }
    features['$garment:pattern:${details.pattern.name}'] = 1;
    final colors = details.accentColors.map((c) => c.argb).toSet().toList()
      ..sort();
    if (colors.isEmpty) return;
    final sums = <String, double>{};
    for (final color in colors) {
      final sample = <String, double>{};
      _colorFeatures(sample, '$garment:accent', color);
      for (final entry in sample.entries) {
        sums.update(
          entry.key,
          (value) => value + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }
    for (final entry in sums.entries) {
      features[entry.key] = entry.value / colors.length;
    }
    features['$garment:multicolor'] = 1;
  }

  void _garmentFeatures(
    Map<String, double> features,
    String garment,
    String title,
  ) {
    final words = RegExp(
      r'[a-z]+',
    ).allMatches(title.toLowerCase()).map((match) => match.group(0)!).toSet();
    if (words.isEmpty) return;
    // Each garment's words have total squared magnitude one, so long product
    // names do not outweigh short names. Shared words transfer to new outfits.
    final scale = 1 / math.sqrt(words.length);
    for (final word in words) {
      features['$garment:word:$word'] = scale;
    }
  }

  void _colorFeatures(Map<String, double> features, String garment, int argb) {
    final color = _ColorChannels(argb);
    features['$garment:r'] = color.r * 2 - 1;
    features['$garment:g'] = color.g * 2 - 1;
    features['$garment:b'] = color.b * 2 - 1;
    features['$garment:lightness'] = color.lightness * 2 - 1;
    // Chroma coordinates avoid discontinuities at the red hue wraparound and
    // become zero for grayscale. All raw color features remain within [-1, 1].
    features['$garment:chroma-x'] = color.r - (color.g + color.b) / 2;
    features['$garment:chroma-y'] = (color.g - color.b) * math.sqrt(3) / 2;
  }

  void _contrastFeatures(
    Map<String, double> features,
    String pair,
    int first,
    int second,
  ) {
    final a = _ColorChannels(first);
    final b = _ColorChannels(second);
    features['$pair:lightness-contrast'] =
        (a.lightness - b.lightness).abs() * 2 - 1;
    final dr = a.r - b.r;
    final dg = a.g - b.g;
    final db = a.b - b.b;
    features['$pair:rgb-contrast'] =
        math.sqrt((dr * dr + dg * dg + db * db) / 3) * 2 - 1;
  }

  double _dot(Map<String, double> weights, Map<String, double> features) =>
      features.entries.fold<double>(
        0,
        (sum, feature) => sum + (weights[feature.key] ?? 0) * feature.value,
      );

  double _sigmoid(double value) {
    // This form is numerically stable even if a future model has large weights.
    if (value >= 0) return 1 / (1 + math.exp(-value));
    final exponential = math.exp(value);
    return exponential / (1 + exponential);
  }
}

class _ColorChannels {
  _ColorChannels(int argb)
    : r = ((argb >> 16) & 255) / 255,
      g = ((argb >> 8) & 255) / 255,
      b = (argb & 255) / 255;

  final double r;
  final double g;
  final double b;

  double get lightness =>
      (math.max(r, math.max(g, b)) + math.min(r, math.min(g, b))) / 2;
}
