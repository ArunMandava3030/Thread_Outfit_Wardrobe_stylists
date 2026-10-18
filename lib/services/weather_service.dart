import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/weather_models.dart';

class WeatherException implements Exception {
  const WeatherException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Requests only a city query or city coordinates; photos and style profiles
/// never form part of these requests. The hosted free API is non-commercial.
class WeatherService {
  WeatherService({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;
  bool _disposed = false;

  Future<List<CityLocation>> searchCities(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    final data = await _get(
      Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': normalized,
        'count': '5',
        'language': 'en',
        'format': 'json',
      }),
    );
    final results = data['results'];
    if (results == null) return const [];
    if (results is! List) {
      throw const WeatherException(
        'City search returned an unreadable response. Try again.',
      );
    }
    final locations = <CityLocation>[];
    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;
      try {
        locations.add(
          CityLocation.fromJson({...item, 'region': item['admin1']}),
        );
      } on FormatException {
        // A single unusable search result should not hide other matching cities.
        continue;
      }
    }
    return List.unmodifiable(locations.take(5));
  }

  Future<WeatherSnapshot> fetchCurrent(CityLocation location) async {
    // Validate even directly constructed locations before making a request.
    CityLocation.fromJson(location.toJson());
    final data = await _get(
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': location.latitude.toString(),
        'longitude': location.longitude.toString(),
        'current':
            'temperature_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m',
        'temperature_unit': 'celsius',
        'wind_speed_unit': 'kmh',
        'precipitation_unit': 'mm',
        'timezone': 'UTC',
        'forecast_days': '1',
      }),
    );
    try {
      final current = data['current'];
      if (current is! Map<String, dynamic>) {
        throw const FormatException('Missing current weather.');
      }
      final now = DateTime.now().toUtc();
      final observed = weatherDate(current['time']);
      final observationAge = now.difference(observed);
      if (observationAge > const Duration(hours: 1) ||
          observationAge < const Duration(minutes: -30)) {
        throw const WeatherException(
          'Current weather is not available for this city yet. Try refreshing later.',
        );
      }
      return WeatherSnapshot.fromJson({
        'location': location.toJson(),
        'temperatureC': current['temperature_2m'],
        'apparentTemperatureC': current['apparent_temperature'],
        'windKmh': current['wind_speed_10m'],
        'precipitationMm': current['precipitation'],
        'weatherCode': current['weather_code'],
        // Age the cache from the weather time, not the download time: fetching
        // an old provider observation cannot make it fresh for another hour.
        'fetchedAt': (observed.isBefore(now) ? observed : now)
            .toIso8601String(),
      });
    } on FormatException {
      throw const WeatherException(
        'Weather data is incomplete. Try refreshing later.',
      );
    }
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    if (_disposed) throw StateError('WeatherService has been disposed.');
    try {
      final response = await _client.get(uri).timeout(requestTimeout);
      if (response.statusCode == 429) {
        throw const WeatherException(
          'Weather requests are busy. Wait a moment and try again.',
        );
      }
      if (response.statusCode != 200) {
        throw const WeatherException(
          'The weather service is unavailable. Try again later.',
        );
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['error'] == true) {
        throw const FormatException('Invalid provider response.');
      }
      return data;
    } on TimeoutException {
      throw const WeatherException(
        'Weather took too long to load. Check your connection and try again.',
      );
    } on FormatException {
      throw const WeatherException(
        'The weather service returned an unreadable response. Try again.',
      );
    } on http.ClientException {
      throw const WeatherException(
        'Could not connect to weather. Check your connection and try again.',
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsClient) _client.close();
  }
}
