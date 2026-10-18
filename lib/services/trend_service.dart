import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/trend_models.dart';

class TrendException implements Exception {
  const TrendException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads the public RSS metadata snapshot. No profile or photo is transmitted.
class TrendService {
  TrendService({
    http.Client? client,
    Uri? endpoint,
    this.requestTimeout = const Duration(seconds: 12),
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _clock = clock ?? DateTime.now,
       endpoint =
           endpoint ??
           (kIsWeb
               ? Uri.base.resolve('data/trends.json')
               : Uri.parse(
                   'https://arunmandava3030.github.io/Thread_Outfit_Wardrobe_stylists/data/trends.json',
                 ));

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _clock;
  final Uri endpoint;
  final Duration requestTimeout;
  bool _disposed = false;

  Future<TrendSnapshot> fetchTrends() async {
    if (_disposed) throw StateError('TrendService has been disposed.');
    try {
      final now = _clock();
      final response = await _client
          .get(
            endpoint.replace(
              queryParameters: {
                ...endpoint.queryParameters,
                'v': (now.millisecondsSinceEpoch ~/ 60000).toString(),
              },
            ),
          )
          .timeout(requestTimeout);
      if (response.statusCode != 200) {
        throw const TrendException(
          'Recent headlines are unavailable right now. Try refreshing later.',
        );
      }
      if (response.bodyBytes.length > 1000000) {
        throw const FormatException('Oversized trend feed.');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid trend feed.');
      }
      return TrendSnapshot.fromJson(data, now: now);
    } on TrendException {
      rethrow;
    } on TimeoutException {
      throw const TrendException(
        'The headline request timed out. Your outfit suggestions still work.',
      );
    } on FormatException {
      throw const TrendException(
        'The headline feed could not be read. Try refreshing later.',
      );
    } on http.ClientException {
      throw const TrendException(
        'Could not connect to the headline feed. Check your connection and try again.',
      );
    }
  }

  void dispose() {
    _disposed = true;
    if (_ownsClient) _client.close();
  }
}
