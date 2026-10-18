import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/style_discovery_models.dart';

class StyleDiscoveryException implements Exception {
  const StyleDiscoveryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Retrieves openly licensed article introductions for context. Local garment
/// recipes are explicit rules; downloading articles does not train a model.
class StyleDiscoveryService {
  StyleDiscoveryService({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;
  bool _disposed = false;

  Future<List<StyleInspiration>> fetchInspirations() async {
    if (_disposed) throw StateError('StyleDiscoveryService has been disposed.');
    final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'formatversion': '2',
      'prop': 'extracts',
      'exintro': '1',
      'explaintext': '1',
      'exchars': '500',
      'exlimit': '5',
      'redirects': '1',
      'titles': StyleDirection.values
          .map((value) => value.articleTitle)
          .join('|'),
      'origin': '*',
    });
    try {
      const agent = String.fromEnvironment(
        'WIKIMEDIA_USER_AGENT',
        defaultValue: 'ThreadStyle/1.0 (personal wardrobe prototype)',
      );
      final response = await _client
          .get(
            uri,
            headers: {
              'Api-User-Agent': agent,
              if (!kIsWeb) 'User-Agent': agent,
            },
          )
          .timeout(requestTimeout);
      if (response.statusCode != 200) {
        throw const StyleDiscoveryException(
          'Wikipedia is unavailable right now. You can still try the local style directions.',
        );
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['error'] != null) {
        throw const FormatException('Invalid article response.');
      }
      final query = data['query'];
      if (query is! Map<String, dynamic> || query['pages'] is! List) {
        throw const FormatException('Missing articles.');
      }
      final aliases = <String, String>{};
      for (final key in ['normalized', 'redirects']) {
        final mappings = query[key];
        if (mappings is! List) continue;
        for (final mapping in mappings) {
          if (mapping is Map<String, dynamic> &&
              mapping['from'] is String &&
              mapping['to'] is String) {
            aliases[mapping['from'] as String] = mapping['to'] as String;
          }
        }
      }
      final pages = <String, Map<String, dynamic>>{};
      for (final page in query['pages'] as List) {
        if (page is Map<String, dynamic> &&
            page['title'] is String &&
            page['missing'] != true &&
            page['invalid'] != true &&
            page['extract'] is String &&
            (page['extract'] as String).trim().isNotEmpty) {
          pages[page['title'] as String] = page;
        }
      }
      final now = DateTime.now().toUtc();
      final results = <StyleInspiration>[];
      for (final direction in StyleDirection.values) {
        var title = direction.articleTitle;
        final visited = <String>{};
        while (aliases.containsKey(title) && visited.add(title)) {
          title = aliases[title]!;
        }
        final page = pages[title];
        if (page == null) continue;
        final summary = (page['extract'] as String).trim();
        // Construct links only under the fixed Wikipedia host. No URL returned
        // by an external page is forwarded into the link launcher.
        final sourceUrl = Uri.https(
          'en.wikipedia.org',
          '/wiki/${title.replaceAll(' ', '_')}',
        ).toString();
        results.add(
          StyleInspiration(
            direction: direction,
            title: title,
            summary: summary.length > 1200
                ? '${summary.substring(0, 1200)}…'
                : summary,
            sourceUrl: sourceUrl,
            fetchedAt: now,
          ),
        );
      }
      if (results.isEmpty) {
        throw const StyleDiscoveryException(
          'No readable style articles were returned. Local style directions are still available.',
        );
      }
      return List.unmodifiable(results);
    } on TimeoutException {
      throw const StyleDiscoveryException(
        'The style guides took too long to load. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const StyleDiscoveryException(
        'Could not connect to Wikipedia. Your local style directions still work.',
      );
    } on FormatException {
      throw const StyleDiscoveryException(
        'The style guides could not be read. Try again later; local styles still work.',
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsClient) _client.close();
  }
}
