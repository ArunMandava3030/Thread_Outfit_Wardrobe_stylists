import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:thread_style/models/weather_models.dart';
import 'package:thread_style/services/weather_service.dart';

const _city = CityLocation(
  name: 'Chennai',
  latitude: 13.08,
  longitude: 80.27,
  region: 'Tamil Nadu',
  country: 'India',
);

Map<String, dynamic> _weatherJson({Map<String, dynamic> changes = const {}}) =>
    {
      'current': {
        'time': DateTime.now().toUtc().toIso8601String(),
        'temperature_2m': 31.5,
        'apparent_temperature': 34.2,
        'precipitation': 0,
        'weather_code': 2,
        'wind_speed_10m': 14,
        ...changes,
      },
    };

WeatherService _service(Map<String, dynamic> json) => WeatherService(
  client: MockClient((_) async => http.Response(jsonEncode(json), 200)),
);

void main() {
  group('WeatherService', () {
    test(
      'search encodes city names and retains valid coordinates and region',
      () async {
        final service = WeatherService(
          client: MockClient((request) async {
            expect(request.url.scheme, 'https');
            expect(request.url.host, 'geocoding-api.open-meteo.com');
            expect(request.url.path, '/v1/search');
            expect(request.url.queryParameters['name'], 'São Paulo, Brazil');
            expect(request.url.queryParameters['count'], '5');
            expect(request.url.queryParameters['language'], 'en');
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'name': 'São Paulo',
                    'latitude': -23.55,
                    'longitude': -46.63,
                    'admin1': 'São Paulo',
                    'country': 'Brazil',
                  },
                  {'name': 'Invalid', 'latitude': null, 'longitude': 20},
                  {'name': 'Invalid', 'latitude': 200, 'longitude': 20},
                  {'name': 'Empty region', 'latitude': 1, 'longitude': 2},
                ],
              }),
              200,
            );
          }),
        );
        final cities = await service.searchCities('  São Paulo, Brazil  ');
        expect(cities, hasLength(2));
        expect(cities.first.label, 'São Paulo, Brazil');
        expect(cities.first.latitude, -23.55);
        expect(cities.first.region, 'São Paulo');
        expect(cities.last.country, isEmpty);
      },
    );

    test(
      'short searches avoid a network request and no matches is valid',
      () async {
        var calls = 0;
        final service = WeatherService(
          client: MockClient((_) async {
            calls++;
            return http.Response('{"generationtime_ms": 1}', 200);
          }),
        );
        expect(await service.searchCities(' '), isEmpty);
        expect(await service.searchCities('x'), isEmpty);
        expect(calls, 0);
        expect(await service.searchCities('NoSuchCity'), isEmpty);
        expect(calls, 1);
      },
    );

    test(
      'current weather requests explicit units and returns usable measurements',
      () async {
        final service = WeatherService(
          client: MockClient((request) async {
            expect(request.url.scheme, 'https');
            expect(request.url.host, 'api.open-meteo.com');
            expect(request.url.path, '/v1/forecast');
            expect(request.url.queryParameters['latitude'], '13.08');
            expect(request.url.queryParameters['longitude'], '80.27');
            expect(request.url.queryParameters['temperature_unit'], 'celsius');
            expect(request.url.queryParameters['wind_speed_unit'], 'kmh');
            expect(request.url.queryParameters['precipitation_unit'], 'mm');
            expect(request.url.queryParameters['timezone'], 'UTC');
            expect(
              request.url.queryParameters['current']!.split(','),
              containsAll([
                'temperature_2m',
                'apparent_temperature',
                'precipitation',
                'weather_code',
                'wind_speed_10m',
              ]),
            );
            return http.Response(jsonEncode(_weatherJson()), 200);
          }),
        );
        final weather = await service.fetchCurrent(_city);
        expect(weather.location.label, 'Chennai, Tamil Nadu, India');
        expect(weather.temperatureC, 31.5);
        expect(weather.apparentTemperatureC, 34.2);
        expect(weather.windKmh, 14);
        expect(weather.precipitationMm, 0);
        expect(weather.conditionLabel, 'Partly cloudy');
        expect(weather.isStale, isFalse);
      },
    );

    test('current UTC timestamps without a suffix are parsed as UTC', () async {
      final observed = DateTime.now().toUtc().subtract(
        const Duration(minutes: 15),
      );
      final weather = await _service(
        _weatherJson(
          changes: {'time': observed.toIso8601String().replaceFirst('Z', '')},
        ),
      ).fetchCurrent(_city);
      expect(weather.fetchedAt, observed);
      expect(weather.fetchedAt.isUtc, isTrue);
      expect(weather.isStale, isFalse);
    });

    test(
      'old provider observations cannot become freshly cached weather',
      () async {
        await expectLater(
          _service(
            _weatherJson(
              changes: {
                'time': DateTime.now()
                    .toUtc()
                    .subtract(const Duration(hours: 2))
                    .toIso8601String(),
              },
            ),
          ).fetchCurrent(_city),
          throwsA(isA<WeatherException>()),
        );
      },
    );

    test(
      'rejects missing, non-numeric and out-of-range measurements',
      () async {
        for (final changes in <Map<String, dynamic>>[
          {'temperature_2m': null},
          {'apparent_temperature': '31'},
          {'precipitation': -1},
          {'wind_speed_10m': -10},
          {'weather_code': 3.5},
          {'weather_code': 100},
          {'time': 'not-a-date'},
        ]) {
          await expectLater(
            _service(_weatherJson(changes: changes)).fetchCurrent(_city),
            throwsA(isA<WeatherException>()),
          );
        }
      },
    );

    test('invalid location coordinates never reach the provider', () async {
      var called = false;
      final service = WeatherService(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        service.fetchCurrent(
          const CityLocation(name: 'Bad', latitude: 91, longitude: 0),
        ),
        throwsFormatException,
      );
      expect(called, isFalse);
    });

    test(
      'HTTP failures and malformed JSON produce recoverable errors',
      () async {
        for (final response in [
          http.Response('busy', 429),
          http.Response('unavailable', 503),
          http.Response('<html>invalid</html>', 200),
          http.Response('[]', 200),
          http.Response('{"error":true,"reason":"provider error"}', 200),
          http.Response('{"results":{}}', 200),
        ]) {
          final service = WeatherService(
            client: MockClient((_) async => response),
          );
          await expectLater(
            service.searchCities('Chennai'),
            throwsA(isA<WeatherException>()),
          );
        }
        await expectLater(
          _service({}).fetchCurrent(_city),
          throwsA(isA<WeatherException>()),
        );
      },
    );

    test(
      'connection failures and timeouts are explained without crashing',
      () async {
        final offline = WeatherService(
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        );
        await expectLater(
          offline.searchCities('Chennai'),
          throwsA(
            isA<WeatherException>().having(
              (e) => e.message,
              'message',
              contains('connection'),
            ),
          ),
        );

        final delayed = Completer<http.Response>();
        final timeout = WeatherService(
          client: MockClient((_) => delayed.future),
          requestTimeout: const Duration(milliseconds: 1),
        );
        await expectLater(
          timeout.searchCities('Chennai'),
          throwsA(
            isA<WeatherException>().having(
              (e) => e.message,
              'message',
              contains('too long'),
            ),
          ),
        );
        delayed.complete(http.Response('{}', 200));
      },
    );

    test(
      'disposing a service does not close its externally owned client',
      () async {
        final client = _TrackedClient();
        final service = WeatherService(client: client);
        service.dispose();
        service.dispose();
        expect(client.closed, isFalse);
        await expectLater(service.searchCities('Chennai'), throwsStateError);
        client.close();
      },
    );
  });

  group('Weather persistence', () {
    test('weather and city survive JSON round trips', () async {
      final original = await _service(_weatherJson()).fetchCurrent(_city);
      final restored = WeatherSnapshot.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), original.toJson());
      expect(restored.isStale, isFalse);
    });

    test('old and implausibly future caches are stale', () async {
      final weather = await _service(_weatherJson()).fetchCurrent(_city);
      for (final date in [
        DateTime.now().subtract(const Duration(hours: 2)),
        DateTime.now().add(const Duration(hours: 2)),
      ]) {
        final restored = WeatherSnapshot.fromJson({
          ...weather.toJson(),
          'fetchedAt': date.toUtc().toIso8601String(),
        });
        expect(restored.isStale, isTrue);
      }
    });

    test('corrupted caches reject non-finite and missing values', () async {
      final weather = await _service(_weatherJson()).fetchCurrent(_city);
      expect(
        () => WeatherSnapshot.fromJson({
          ...weather.toJson(),
          'temperatureC': double.nan,
        }),
        throwsFormatException,
      );
      expect(
        () => WeatherSnapshot.fromJson({
          ...weather.toJson(),
          'windKmh': double.infinity,
        }),
        throwsFormatException,
      );
      expect(
        () => WeatherSnapshot.fromJson({...weather.toJson(), 'location': null}),
        throwsFormatException,
      );
      expect(
        () => CityLocation.fromJson({..._city.toJson(), 'longitude': 'bad'}),
        throwsFormatException,
      );
    });
  });
}

class _TrackedClient extends MockClient {
  _TrackedClient() : super((_) async => http.Response('{}', 200));

  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}
