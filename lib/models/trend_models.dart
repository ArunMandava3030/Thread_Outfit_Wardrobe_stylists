import 'style_discovery_models.dart';

const trendPublishers = <String, String>{
  'GQ': 'gq.com',
  'Esquire': 'esquire.com',
  'FashionBeans': 'fashionbeans.com',
};

bool isTrendSource(String url, String publisher) {
  final domain = trendPublishers[publisher];
  final uri = Uri.tryParse(url);
  return domain != null &&
      uri != null &&
      uri.scheme == 'https' &&
      (uri.host == domain || uri.host == 'www.$domain') &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      uri.path.isNotEmpty &&
      url.length <= 2000;
}

DateTime _utcDate(Object? value) {
  final match = value is String
      ? RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:?\d{2})$',
        ).firstMatch(value)
      : null;
  if (match == null) {
    throw const FormatException('A dated UTC observation is required.');
  }
  final fields = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final calendar = DateTime.utc(
    fields[0],
    fields[1],
    fields[2],
    fields[3],
    fields[4],
    fields[5],
  );
  if (calendar.year != fields[0] ||
      calendar.month != fields[1] ||
      calendar.day != fields[2] ||
      calendar.hour != fields[3] ||
      calendar.minute != fields[4] ||
      calendar.second != fields[5]) {
    throw const FormatException('Invalid publication date.');
  }
  return DateTime.parse(value as String).toUtc();
}

class TrendHeadline {
  const TrendHeadline({
    required this.headline,
    required this.url,
    required this.publisher,
    required this.publishedAt,
  });

  final String headline;
  final String url;
  final String publisher;
  final DateTime publishedAt;

  factory TrendHeadline.fromJson(Map<String, dynamic> json) {
    final headline = json['headline'];
    final url = json['url'];
    final publisher = json['publisher'];
    if (headline is! String ||
        headline.trim().isEmpty ||
        headline.length > 160 ||
        url is! String ||
        publisher is! String ||
        !isTrendSource(url, publisher)) {
      throw const FormatException('Invalid trend headline.');
    }
    return TrendHeadline(
      headline: headline.trim(),
      url: url,
      publisher: publisher,
      publishedAt: _utcDate(json['publishedAt']),
    );
  }

  /// Explicit headline keyword mapping, not an ML trend or popularity score.
  StyleDirection? get suggestedDirection {
    final title = headline.toLowerCase();
    if (RegExp(r'\b(preppy|ivy|polo|rugby|loafer)').hasMatch(title)) {
      return StyleDirection.preppy;
    }
    if (RegExp(
      r'\b(athleisure|running|gym|workout|track|jogger)',
    ).hasMatch(title)) {
      return StyleDirection.athleisure;
    }
    if (RegExp(
      r'\b(streetwear|sneaker|baggy|hoodie|cargo|oversized)',
    ).hasMatch(title)) {
      return StyleDirection.streetwear;
    }
    if (RegExp(
      r'\b(suit|tailor|blazer|smart.casual|business.casual|formal)',
    ).hasMatch(title)) {
      return StyleDirection.smartCasual;
    }
    if (RegExp(
      r'\b(denim|jeans|shirt|knitwear|sweater|cardigan|casual)',
    ).hasMatch(title)) {
      return StyleDirection.everyday;
    }
    return null;
  }
}

class TrendSourceStatus {
  const TrendSourceStatus({required this.name, required this.available});
  final String name;
  final bool available;
}

class TrendSnapshot {
  const TrendSnapshot({
    required this.fetchedAt,
    required this.headlines,
    required this.sources,
  });

  final DateTime fetchedAt;
  final List<TrendHeadline> headlines;
  final List<TrendSourceStatus> sources;

  bool isStaleAt(DateTime now) =>
      now.toUtc().difference(fetchedAt) > const Duration(hours: 48);
  bool get isPartial => sources.any((source) => !source.available);

  factory TrendSnapshot.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final checkedAt = (now ?? DateTime.now()).toUtc();
    if (json['schemaVersion'] != 1 ||
        json['items'] is! List ||
        json['sources'] is! List) {
      throw const FormatException('Unsupported trend feed.');
    }
    final fetchedAt = _utcDate(json['fetchedAt']);
    if (fetchedAt.isAfter(checkedAt.add(const Duration(minutes: 5)))) {
      throw const FormatException('Trend feed date is in the future.');
    }
    final seen = <String>{};
    final headlines = <TrendHeadline>[];
    for (final item in (json['items'] as List).take(200)) {
      try {
        if (item is! Map<String, dynamic>) continue;
        final headline = TrendHeadline.fromJson(item);
        final age = checkedAt.difference(headline.publishedAt);
        if (age.isNegative || age > const Duration(days: 90)) continue;
        if (headline.publishedAt.isAfter(
          fetchedAt.add(const Duration(minutes: 5)),
        )) {
          continue;
        }
        if (seen.add(headline.url)) headlines.add(headline);
      } on FormatException {
        continue;
      }
    }
    headlines.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final sources = <TrendSourceStatus>[];
    final sourceNames = <String>{};
    for (final source in json['sources'] as List) {
      if (source is! Map<String, dynamic>) continue;
      final name = source['name'];
      final status = source['status'];
      if (name is! String ||
          !trendPublishers.containsKey(name) ||
          (status != 'ok' && status != 'error') ||
          !sourceNames.add(name)) {
        continue;
      }
      sources.add(TrendSourceStatus(name: name, available: status == 'ok'));
    }
    if (sources.isEmpty) throw const FormatException('Missing trend sources.');
    return TrendSnapshot(
      fetchedAt: fetchedAt,
      headlines: List.unmodifiable(headlines.take(18)),
      sources: List.unmodifiable(sources),
    );
  }
}
