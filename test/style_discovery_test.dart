import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:thread_style/models/style_discovery_models.dart';
import 'package:thread_style/models/style_models.dart';
import 'package:thread_style/services/style_direction_stylist.dart';
import 'package:thread_style/services/style_discovery_service.dart';
import 'package:thread_style/services/style_engine.dart';
import 'package:thread_style/services/weather_stylist.dart';
import 'package:thread_style/models/weather_models.dart';
import 'package:thread_style/widgets/style_discovery_panel.dart';

Map<String, dynamic> _articles() => {
  'query': {
    'pages': [
      for (final direction in StyleDirection.values)
        {
          'title': direction.articleTitle,
          'extract': 'An introduction to ${direction.label.toLowerCase()}.',
          'fullurl': 'https://untrusted.example/article',
        },
    ],
  },
};

StyleDiscoveryService _service(Object json) => StyleDiscoveryService(
  client: MockClient((_) async => http.Response(jsonEncode(json), 200)),
);

List<OutfitRecommendation> _outfits(
  Occasion occasion, {
  bool includeLayer = true,
}) => const StyleEngine().generate(
  shirt: ShirtColor.presets.first,
  occasion: occasion,
  profile: const StyleProfile(),
  includeLayer: includeLayer,
);

void main() {
  group('Style discovery API', () {
    test(
      'fetches all style intros in a single request and constructs trusted source links',
      () async {
        var calls = 0;
        final service = StyleDiscoveryService(
          client: MockClient((request) async {
            calls++;
            expect(request.url.scheme, 'https');
            expect(request.url.host, 'en.wikipedia.org');
            expect(request.url.path, '/w/api.php');
            expect(request.url.queryParameters['origin'], '*');
            expect(request.url.queryParameters['exintro'], '1');
            expect(request.url.queryParameters['explaintext'], '1');
            expect(
              request.url.queryParameters['titles']!.split('|'),
              StyleDirection.values.map((direction) => direction.articleTitle),
            );
            expect(request.headers['Api-User-Agent'], contains('ThreadStyle'));
            return http.Response(jsonEncode(_articles()), 200);
          }),
        );
        final sources = await service.fetchInspirations();
        expect(calls, 1);
        expect(
          sources.map((source) => source.direction),
          StyleDirection.values,
        );
        expect(
          sources[1].sourceUrl,
          'https://en.wikipedia.org/wiki/Smart_casual',
        );
        expect(
          sources.every((source) => isWikipediaSource(source.sourceUrl)),
          isTrue,
        );
        expect(sources.first.summary, 'An introduction to everyday.');
      },
    );

    test(
      'resolves redirects and omits unavailable articles without inventing content',
      () async {
        final service = _service({
          'query': {
            'redirects': [
              {'from': 'Casual wear', 'to': 'Casual attire'},
            ],
            'pages': [
              {
                'title': 'Casual attire',
                'extract': 'A retrieved casual introduction.',
              },
              {'title': 'Streetwear', 'extract': ''},
              {'title': 'Preppy', 'missing': true},
              {'title': 'Athleisure', 'extract': null},
            ],
          },
        });
        final results = await service.fetchInspirations();
        expect(results, hasLength(1));
        expect(results.single.direction, StyleDirection.everyday);
        expect(
          results.single.sourceUrl,
          'https://en.wikipedia.org/wiki/Casual_attire',
        );
      },
    );

    test(
      'malformed, missing and failed responses are explicit errors',
      () async {
        for (final data in [
          [],
          {
            'error': {'code': 'ratelimited'},
          },
          {'query': {}},
          {
            'query': {'pages': []},
          },
        ]) {
          await expectLater(
            _service(data).fetchInspirations(),
            throwsA(isA<StyleDiscoveryException>()),
          );
        }
        for (final response in [
          http.Response('unavailable', 503),
          http.Response('bad-json', 200),
        ]) {
          final service = StyleDiscoveryService(
            client: MockClient((_) async => response),
          );
          await expectLater(
            service.fetchInspirations(),
            throwsA(isA<StyleDiscoveryException>()),
          );
        }
      },
    );

    test(
      'network failure and timeout preserve a local-style fallback message',
      () async {
        final offline = StyleDiscoveryService(
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        );
        await expectLater(
          offline.fetchInspirations(),
          throwsA(
            isA<StyleDiscoveryException>().having(
              (error) => error.message,
              'message',
              contains('local style'),
            ),
          ),
        );
        final response = Completer<http.Response>();
        final delayed = StyleDiscoveryService(
          client: MockClient((_) => response.future),
          requestTimeout: const Duration(milliseconds: 1),
        );
        await expectLater(
          delayed.fetchInspirations(),
          throwsA(
            isA<StyleDiscoveryException>().having(
              (error) => error.message,
              'message',
              contains('too long'),
            ),
          ),
        );
        response.complete(http.Response('{}', 200));
      },
    );

    test(
      'persisted source attribution round trips and unsafe URLs are rejected',
      () async {
        final original = (await _service(
          _articles(),
        ).fetchInspirations()).first;
        final restored = StyleInspiration.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
        );
        expect(restored.toJson(), original.toJson());
        for (final source in [
          'javascript:alert(1)',
          'https://evil.test/wiki/Casual_wear',
          'https://en.wikipedia.org@evil.test/wiki/Casual_wear',
          'http://en.wikipedia.org/wiki/Casual_wear',
        ]) {
          expect(
            () => StyleInspiration.fromJson({
              ...original.toJson(),
              'sourceUrl': source,
            }),
            throwsFormatException,
          );
        }
      },
    );
  });

  group('Style direction recipes', () {
    const stylist = StyleDirectionStylist();

    test(
      'directions change actual garments with stable unique saved identities',
      () {
        final originals = _outfits(Occasion.casual);
        final ids = <String>{};
        final pants = <String>{};
        final layers = <String>{};
        for (final direction in StyleDirection.values) {
          final adapted = stylist.adapt(originals, direction);
          ids.add(adapted.first.id);
          pants.add(adapted.first.pants.title);
          layers.add(adapted.first.layer.title);
          expect(
            adapted.first.id,
            stylist.adapt(originals, direction).first.id,
          );
          for (var i = 0; i < adapted.length; i++) {
            expect(adapted[i].shirt, originals[i].shirt);
            expect(adapted[i].pants.colorArgb, originals[i].pants.colorArgb);
            expect(adapted[i].shoes.colorArgb, originals[i].shoes.colorArgb);
            expect(adapted[i].layer.colorArgb, originals[i].layer.colorArgb);
            expect(adapted[i].occasion, Occasion.casual);
          }
        }
        expect(ids, hasLength(5));
        expect(pants.length, greaterThanOrEqualTo(3));
        expect(layers, hasLength(5));
      },
    );

    test(
      'all directions retain motorcycle protective garments and safety advice',
      () {
        final originals = _outfits(Occasion.bikeRide, includeLayer: false);
        for (final direction in StyleDirection.values) {
          final adapted = stylist.adapt(originals, direction);
          for (var i = 0; i < adapted.length; i++) {
            expect(adapted[i].pants, originals[i].pants);
            expect(adapted[i].shoes, originals[i].shoes);
            expect(adapted[i].layer, originals[i].layer);
            expect(adapted[i].safetyNote, originals[i].safetyNote);
            expect(adapted[i].fitAdvice, originals[i].fitAdvice);
          }
        }
      },
    );

    test(
      'office styles stay in trousers and closed shoes while layers off stays respected',
      () {
        for (final direction in StyleDirection.values) {
          final office = stylist.adapt(
            _outfits(Occasion.office, includeLayer: false),
            direction,
          );
          for (final outfit in office) {
            expect(outfit.pants.title, isNot(contains('shorts')));
            expect(outfit.pants.title, isNot(contains('track')));
            expect(outfit.shoes.title, isNot(contains('sandals')));
            expect(outfit.layer.colorArgb, 0);
          }
        }
      },
    );

    test(
      'weather adaptation still changes an inspired outfit for wet conditions',
      () {
        final inspired = stylist.adapt(
          _outfits(Occasion.casual),
          StyleDirection.streetwear,
        );
        final weather = WeatherSnapshot(
          location: const CityLocation(name: 'City', latitude: 1, longitude: 2),
          temperatureC: 20,
          apparentTemperatureC: 20,
          windKmh: 5,
          precipitationMm: 2,
          weatherCode: 61,
          fetchedAt: DateTime.now(),
        );
        final adapted = const WeatherStylist().adapt(
          inspired,
          weather,
          includeLayer: true,
        );
        expect(adapted.first.layer.title, 'Lightweight rain shell');
        expect(adapted.first.reasons.join(' '), contains('Streetwear'));
        expect(adapted.first.id, contains('style-streetwear'));
        expect(adapted.first.id, isNot(inspired.first.id));
      },
    );
  });

  group('Style discovery panel', () {
    testWidgets('presets work without making an automatic web request', (
      tester,
    ) async {
      var requests = 0;
      StyleDirection? chosen;
      final service = StyleDiscoveryService(
        client: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode(_articles()), 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StyleDiscoveryPanel(
                selected: StyleDirection.everyday,
                onSelected: (value) => chosen = value,
                service: service,
              ),
            ),
          ),
        ),
      );
      expect(requests, 0);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Streetwear'));
      await tester.pump();
      expect(chosen, StyleDirection.streetwear);
      expect(requests, 0);
      await tester.tap(find.text('Explore styles'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('CC BY-SA 4.0'), findsOneWidget);
      expect(find.text('Wikipedia · Streetwear'), findsOneWidget);
    });

    testWidgets(
      'failed retrieval reports the failure while keeping presets usable',
      (tester) async {
        StyleDirection? chosen;
        final service = StyleDiscoveryService(
          client: MockClient((_) async => http.Response('unavailable', 503)),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: StyleDiscoveryPanel(
                  selected: StyleDirection.everyday,
                  onSelected: (value) => chosen = value,
                  service: service,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Explore styles'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Wikipedia is unavailable'), findsOneWidget);
        expect(find.text('Read source'), findsNothing);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Preppy'));
        expect(chosen, StyleDirection.preppy);
      },
    );

    testWidgets(
      'pending retrieval can finish safely after the panel is removed',
      (tester) async {
        final response = Completer<http.Response>();
        final service = StyleDiscoveryService(
          client: MockClient((_) => response.future),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StyleDiscoveryPanel(
                selected: StyleDirection.everyday,
                onSelected: (_) {},
                service: service,
              ),
            ),
          ),
        );
        await tester.tap(find.text('Explore styles'));
        await tester.pump();
        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        response.complete(http.Response(jsonEncode(_articles()), 200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
