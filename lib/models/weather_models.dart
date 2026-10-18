class CityLocation {
  const CityLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.country = '',
    this.region = '',
  });

  final String name;
  final double latitude;
  final double longitude;
  final String country;
  final String region;

  String get label => <String>{
    name,
    region,
    country,
  }.where((part) => part.isNotEmpty).join(', ');

  Map<String, dynamic> toJson() => {
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'country': country,
    'region': region,
  };

  factory CityLocation.fromJson(Map<String, dynamic> json) => CityLocation(
    name: _requiredText(json['name'], 'city name'),
    latitude: weatherNumber(json['latitude'], 'latitude', min: -90, max: 90),
    longitude: weatherNumber(
      json['longitude'],
      'longitude',
      min: -180,
      max: 180,
    ),
    country: _optionalText(json['country']),
    region: _optionalText(json['region']),
  );
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.location,
    required this.temperatureC,
    required this.apparentTemperatureC,
    required this.windKmh,
    required this.precipitationMm,
    required this.weatherCode,
    required this.fetchedAt,
  });

  final CityLocation location;
  final double temperatureC;
  final double apparentTemperatureC;
  final double windKmh;
  final double precipitationMm;
  final int weatherCode;
  final DateTime fetchedAt;

  /// Cached weather stops influencing new outfits after an hour. A timestamp
  /// far in the future is also unusable, for example after a device clock edit.
  bool get isStale {
    final age = DateTime.now().toUtc().difference(fetchedAt.toUtc());
    return age > const Duration(hours: 1) || age < const Duration(minutes: -5);
  }

  String get conditionLabel => switch (weatherCode) {
    0 => 'Clear sky',
    1 => 'Mainly clear',
    2 => 'Partly cloudy',
    3 => 'Overcast',
    45 || 48 => 'Foggy',
    51 || 53 || 55 => 'Drizzle',
    56 || 57 => 'Freezing drizzle',
    61 || 63 || 65 => 'Rain',
    66 || 67 => 'Freezing rain',
    71 || 73 || 75 || 77 => 'Snow',
    80 || 81 || 82 => 'Rain showers',
    85 || 86 => 'Snow showers',
    95 => 'Thunderstorm',
    96 || 99 => 'Thunderstorm with hail',
    _ => 'Conditions unavailable',
  };

  Map<String, dynamic> toJson() => {
    'location': location.toJson(),
    'temperatureC': temperatureC,
    'apparentTemperatureC': apparentTemperatureC,
    'windKmh': windKmh,
    'precipitationMm': precipitationMm,
    'weatherCode': weatherCode,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
  };

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) {
    final location = json['location'];
    if (location is! Map<String, dynamic>) {
      throw const FormatException('Invalid weather location.');
    }
    return WeatherSnapshot(
      location: CityLocation.fromJson(location),
      temperatureC: weatherNumber(
        json['temperatureC'],
        'temperature',
        min: -100,
        max: 70,
      ),
      apparentTemperatureC: weatherNumber(
        json['apparentTemperatureC'],
        'feels-like temperature',
        min: -130,
        max: 100,
      ),
      windKmh: weatherNumber(json['windKmh'], 'wind speed', min: 0, max: 500),
      precipitationMm: weatherNumber(
        json['precipitationMm'],
        'precipitation',
        min: 0,
        max: 2000,
      ),
      weatherCode: weatherCodeValue(json['weatherCode']),
      fetchedAt: weatherDate(json['fetchedAt']),
    );
  }
}

/// Shared validation for cached values and values received from the provider.
double weatherNumber(
  Object? value,
  String field, {
  required double min,
  required double max,
}) {
  if (value is! num || !value.isFinite || value < min || value > max) {
    throw FormatException('Invalid $field.');
  }
  return value.toDouble();
}

int weatherCodeValue(Object? value) {
  final number = weatherNumber(value, 'weather code', min: 0, max: 99);
  if (number != number.truncateToDouble()) {
    throw const FormatException('Invalid weather code.');
  }
  return number.toInt();
}

DateTime weatherDate(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid weather timestamp.');
  }
  // Open-Meteo omits the suffix when timezone=UTC is requested.
  final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
  final parsed = DateTime.tryParse(hasZone ? value : '${value}Z');
  if (parsed == null) throw const FormatException('Invalid weather timestamp.');
  return parsed.toUtc();
}

String _requiredText(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $field.');
  }
  return value.trim();
}

String _optionalText(Object? value) {
  if (value == null) return '';
  if (value is! String) throw const FormatException('Invalid location text.');
  return value.trim();
}
