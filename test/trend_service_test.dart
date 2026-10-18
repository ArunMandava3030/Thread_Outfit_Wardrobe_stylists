import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:thread_style/models/style_discovery_models.dart';
import 'package:thread_style/models/trend_models.dart';
import 'package:thread_style/services/trend_service.dart';

final now = DateTime.utc(2026, 10, 18, 12);

Map<String, dynamic> headline({
  String title = 'New denim shirts',
  String date = '2026-10-16T12:00:00Z',
  String url = 'https://www.gq.com/story/new-denim',
}) => {'headline': title, 'url': url, 'publisher': 'GQ', 'publishedAt': date};

Map<String, dynamic> feed({
  List<dynamic>? items,
  String date = '2026-10-18T10:00:00Z',
}) => {
  'schemaVersion': 1,
  'fetchedAt': date,
  'sources': [
    {'name': 'GQ', 'status': 'ok'},
  ],
  'items': items ?? [headline()],
};

void main() {
  test('loads metadata and keeps the repository subpath', () async {
    final service = TrendService(
      endpoint: Uri.parse('https://example.com/repository/data/trends.json'),
      clock: () => now,
      client: MockClient((request) async {
        expect(request.url.path, '/repository/data/trends.json');
        expect(request.url.queryParameters.keys, ['v']);
        return http.Response(jsonEncode(feed()), 200);
      }),
    );
    final result = await service.fetchTrends();
    expect(result.headlines.single.publisher, 'GQ');
    expect(result.headlines.single.suggestedDirection, StyleDirection.everyday);
    expect(result.isStaleAt(now), isFalse);
  });

  test(
    'sorts by actual publication date, deduplicates and filters malformed items',
    () {
      final result = TrendSnapshot.fromJson(
        feed(
          items: [
            headline(date: '2026-10-15T10:00:00Z'),
            headline(
              title: 'Suits for autumn',
              url: 'https://www.gq.com/story/suits',
            ),
            headline(),
            headline(url: 'https://www.gq.com.evil.example/story/a'),
            headline(url: 'javascript:alert(1)'),
            headline(
              date: '2027-01-01T00:00:00Z',
              url: 'https://www.gq.com/story/future',
            ),
            headline(
              date: '2026-01-01T00:00:00Z',
              url: 'https://www.gq.com/story/old',
            ),
            headline(
              date: '2026-09-31T00:00:00Z',
              url: 'https://www.gq.com/story/invalid',
            ),
            headline(
              date: '2026-10-16T00:00:00',
              url: 'https://www.gq.com/story/no-zone',
            ),
            12,
          ],
        ),
        now: now,
      );
      expect(result.headlines, hasLength(2));
      expect(result.headlines.first.headline, 'Suits for autumn');
    },
  );

  test('detects stale and partial feeds, and exposes honest empty state', () {
    final json = feed(items: [], date: '2026-10-14T10:00:00Z');
    json['sources'] = [
      {'name': 'GQ', 'status': 'error'},
      {'name': 'Esquire', 'status': 'ok'},
    ];
    final result = TrendSnapshot.fromJson(json, now: now);
    expect(result.headlines, isEmpty);
    expect(result.isStaleAt(now), isTrue);
    expect(result.isPartial, isTrue);
    expect(
      () =>
          TrendSnapshot.fromJson(feed(date: '2027-10-18T10:00:00Z'), now: now),
      throwsFormatException,
    );
  });

  test(
    'style shortcuts are explicit keywords and unrelated headlines have none',
    () {
      expect(
        TrendHeadline.fromJson(
          headline(title: 'New preppy loafers'),
        ).suggestedDirection,
        StyleDirection.preppy,
      );
      expect(
        TrendHeadline.fromJson(
          headline(title: 'Sneaker season'),
        ).suggestedDirection,
        StyleDirection.streetwear,
      );
      expect(
        TrendHeadline.fromJson(
          headline(title: 'Athleisure returns'),
        ).suggestedDirection,
        StyleDirection.athleisure,
      );
      expect(
        TrendHeadline.fromJson(
          headline(title: 'Tailoring for October'),
        ).suggestedDirection,
        StyleDirection.smartCasual,
      );
      expect(
        TrendHeadline.fromJson(
          headline(title: 'A designer interview'),
        ).suggestedDirection,
        isNull,
      );
    },
  );

  test(
    'rejects bad responses and handles timeouts and network failures',
    () async {
      for (final response in [
        http.Response('no', 503),
        http.Response('bad json', 200),
        http.Response('[]', 200),
        http.Response('{}', 200),
      ]) {
        final service = TrendService(
          client: MockClient((_) async => response),
          clock: () => now,
        );
        await expectLater(
          service.fetchTrends(),
          throwsA(isA<TrendException>()),
        );
      }
      final offline = TrendService(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(offline.fetchTrends(), throwsA(isA<TrendException>()));
      final slow = TrendService(
        client: MockClient((_) => Completer<http.Response>().future),
        requestTimeout: const Duration(milliseconds: 1),
      );
      await expectLater(slow.fetchTrends(), throwsA(isA<TrendException>()));
    },
  );
}
