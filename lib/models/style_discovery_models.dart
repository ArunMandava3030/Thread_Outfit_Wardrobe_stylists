enum StyleDirection {
  everyday,
  smartCasual,
  streetwear,
  athleisure,
  preppy;

  String get label => switch (this) {
    everyday => 'Everyday',
    smartCasual => 'Smart casual',
    streetwear => 'Streetwear',
    athleisure => 'Athleisure',
    preppy => 'Preppy',
  };

  String get articleTitle => switch (this) {
    everyday => 'Casual wear',
    smartCasual => 'Smart casual',
    streetwear => 'Streetwear',
    athleisure => 'Athleisure',
    preppy => 'Preppy',
  };
}

class StyleInspiration {
  const StyleInspiration({
    required this.direction,
    required this.title,
    required this.summary,
    required this.sourceUrl,
    required this.fetchedAt,
  });

  final StyleDirection direction;
  final String title;
  final String summary;
  final String sourceUrl;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
    'direction': direction.name,
    'title': title,
    'summary': summary,
    'sourceUrl': sourceUrl,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
  };

  factory StyleInspiration.fromJson(Map<String, dynamic> json) {
    StyleDirection? direction;
    for (final value in StyleDirection.values) {
      if (value.name == json['direction']) direction = value;
    }
    final title = json['title'];
    final summary = json['summary'];
    final sourceUrl = json['sourceUrl'];
    final date = json['fetchedAt'];
    if (direction == null ||
        title is! String ||
        title.trim().isEmpty ||
        summary is! String ||
        summary.trim().isEmpty ||
        sourceUrl is! String ||
        !isWikipediaSource(sourceUrl) ||
        date is! String) {
      throw const FormatException('Invalid style inspiration.');
    }
    final parsedDate = DateTime.tryParse(date);
    if (parsedDate == null) {
      throw const FormatException('Invalid inspiration date.');
    }
    return StyleInspiration(
      direction: direction,
      title: title,
      summary: summary,
      sourceUrl: sourceUrl,
      fetchedAt: parsedDate.toUtc(),
    );
  }
}

bool isWikipediaSource(String sourceUrl) {
  final uri = Uri.tryParse(sourceUrl);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'en.wikipedia.org' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      uri.path.startsWith('/wiki/') &&
      uri.path.length > 6;
}
