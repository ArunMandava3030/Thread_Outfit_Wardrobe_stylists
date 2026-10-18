import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:thread_style/main.dart';
import 'package:thread_style/models/style_discovery_models.dart';
import 'package:thread_style/models/weather_models.dart';
import 'package:thread_style/services/style_discovery_service.dart';
import 'package:thread_style/services/style_store.dart';
import 'package:thread_style/services/weather_service.dart';
import 'package:thread_style/widgets/outfit_card.dart';

class _ContextStore implements StyleStore {
  WeatherSnapshot? weather;
  StyleDirection direction = StyleDirection.everyday;
  @override
  Future<StoredStyle> load() async =>
      StoredStyle(configured: true, weather: weather, direction: direction);
  @override
  Future<void> saveWeather(WeatherSnapshot? value) async => weather = value;
  @override
  Future<void> saveDirection(StyleDirection value) async => direction = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Unexpected storage operation: ${invocation.memberName}',
  );
}

class _BlockingDirectionStore extends _ContextStore {
  final directionWrite = Completer<void>();
  bool directionStarted = false;
  int weatherWrites = 0;

  @override
  Future<void> saveDirection(StyleDirection value) async {
    directionStarted = true;
    await directionWrite.future;
    direction = value;
  }

  @override
  Future<void> saveWeather(WeatherSnapshot? value) async {
    weatherWrites++;
    weather = value;
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'weather completed during a direction save persists after the pending write',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _BlockingDirectionStore()
        ..weather = WeatherSnapshot(
          location: const CityLocation(
            name: 'Chennai',
            latitude: 13.08,
            longitude: 80.27,
            country: 'India',
          ),
          temperatureC: 20,
          apparentTemperatureC: 20,
          windKmh: 10,
          precipitationMm: 0,
          weatherCode: 2,
          fetchedAt: DateTime.now().toUtc(),
        );
      final response = Completer<http.Response>();
      final client = MockClient((_) => response.future);
      addTearDown(client.close);
      await tester.pumpWidget(
        ThreadApp(
          store: store,
          weatherService: WeatherService(client: client),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byTooltip('Refresh weather'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh weather'));
      await tester.pump();
      final preppy = find.widgetWithText(ChoiceChip, 'Preppy');
      await tester.ensureVisible(preppy);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(preppy);
      await tester.pump();
      expect(store.directionStarted, isTrue);

      response.complete(
        http.Response(
          jsonEncode({
            'current': {
              'time': DateTime.now().toUtc().toIso8601String(),
              'temperature_2m': 31,
              'apparent_temperature': 34,
              'wind_speed_10m': 12,
              'precipitation': 0,
              'weather_code': 2,
            },
          }),
          200,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        store.weatherWrites,
        0,
        reason:
            'The weather result waits for the active persistence operation.',
      );

      store.directionWrite.complete();
      await tester.pumpAndSettle();
      expect(store.direction, StyleDirection.preppy);
      expect(store.weatherWrites, 1);
      expect(
        store.weather?.temperatureC,
        31,
        reason:
            'A completed refresh must not be silently dropped by the write lock.',
      );
      expect(find.textContaining('31°C · Feels like 34°C'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'chosen city and web style personalize garments and survive restart',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _ContextStore();
      final requests = <http.Request>[];
      var failWeather = false;
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.host == 'geocoding-api.open-meteo.com') {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'name': 'Chennai',
                  'latitude': 13.08,
                  'longitude': 80.27,
                  'country': 'India',
                },
              ],
            }),
            200,
          );
        }
        if (request.url.host == 'api.open-meteo.com') {
          if (failWeather) return http.Response('Unavailable', 503);
          return http.Response(
            jsonEncode({
              'current': {
                'time': DateTime.now().toUtc().toIso8601String(),
                'temperature_2m': 12,
                'apparent_temperature': 9,
                'wind_speed_10m': 15,
                'precipitation': 2,
                'weather_code': 61,
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'query': {
              'pages': [
                {
                  'title': 'Preppy',
                  'extract': 'A style with roots in collegiate clothing.',
                },
              ],
            },
          }),
          200,
        );
      });
      final weather = WeatherService(client: client);
      final discovery = StyleDiscoveryService(client: client);
      addTearDown(client.close);
      Future<void> mount() async {
        await tester.pumpWidget(
          ThreadApp(
            store: store,
            weatherService: weather,
            discoveryService: discovery,
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      expect(
        requests,
        isEmpty,
        reason: 'No external requests without an explicit action.',
      );
      await _tap(tester, find.byKey(const Key('choose_weather_city')));
      await tester.enterText(
        find.byKey(const Key('city_search_input')),
        'Chennai',
      );
      await _tap(tester, find.text('Search cities'));
      await _tap(tester, find.text('Chennai, India'));
      expect(store.weather?.weatherCode, 61);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Preppy'));
      expect(store.direction, StyleDirection.preppy);
      await _tap(tester, find.byKey(const Key('generate_outfits')));
      final look = tester
          .widget<OutfitCard>(find.byType(OutfitCard).first)
          .outfit;
      expect(look.layer.title.toLowerCase(), contains('rain'));
      expect(look.shoes.title.toLowerCase(), contains('water-resistant'));
      expect(look.reasons.any((reason) => reason.contains('Preppy')), isTrue);

      failWeather = true;
      await _tap(tester, find.byTooltip('Refresh weather'));
      expect(
        store.weather?.weatherCode,
        61,
        reason: 'Failed refresh preserves last successful weather.',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await mount();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Preppy'))
            .selected,
        isTrue,
      );
      expect(find.text('Chennai, India'), findsOneWidget);
      await _tap(tester, find.text('Turn off'));
      expect(store.weather, isNull);
      await _tap(tester, find.byKey(const Key('generate_outfits')));
      final dryLook = tester
          .widget<OutfitCard>(find.byType(OutfitCard).first)
          .outfit;
      expect(dryLook.layer.title, 'Fine-knit cardigan');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );
}
