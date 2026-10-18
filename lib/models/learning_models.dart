import 'style_models.dart';

enum StyleFeedback { like, dislike }

/// One explicit preference and the outfit features available when it was given.
/// A full snapshot keeps feedback useful if the suggestion catalog changes.
class StyleFeedbackEntry {
  const StyleFeedbackEntry({
    required this.outfit,
    required this.feedback,
    required this.updatedAt,
  });

  final OutfitRecommendation outfit;
  final StyleFeedback feedback;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'outfit': outfit.toJson(),
    'feedback': feedback.name,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory StyleFeedbackEntry.fromJson(Map<String, dynamic> json) {
    final feedback = switch (json['feedback']) {
      'like' => StyleFeedback.like,
      'dislike' => StyleFeedback.dislike,
      _ => throw const FormatException('Unknown style feedback'),
    };
    final timestamp = json['updatedAt'];
    final updatedAt = timestamp is String ? DateTime.tryParse(timestamp) : null;
    if (updatedAt == null) {
      throw const FormatException('Invalid feedback date');
    }
    return StyleFeedbackEntry(
      outfit: OutfitRecommendation.fromJson(
        Map<String, dynamic>.from(json['outfit'] as Map),
      ),
      feedback: feedback,
      updatedAt: updatedAt,
    );
  }
}
