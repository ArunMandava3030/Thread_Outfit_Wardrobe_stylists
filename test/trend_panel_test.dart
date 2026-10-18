import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:thread_style/models/style_discovery_models.dart';
import 'package:thread_style/services/trend_service.dart';
import 'package:thread_style/theme.dart';
import 'package:thread_style/widgets/trend_panel.dart';

void main() {
  testWidgets(
    'requests headlines explicitly, applies style and retains data when refresh fails',
    (tester) async {
      var calls = 0;
      StyleDirection? selected;
      final now = DateTime.now().toUtc();
      final service = TrendService(
        client: MockClient((_) async {
          calls++;
          if (calls > 1) throw http.ClientException('offline');
          return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'fetchedAt': now.toIso8601String(),
              'sources': [
                {'name': 'GQ', 'status': 'ok'},
              ],
              'items': [
                {
                  'headline': 'Try preppy loafers',
                  'url': 'https://www.gq.com/story/loafers',
                  'publisher': 'GQ',
                  'publishedAt': now
                      .subtract(const Duration(days: 1))
                      .toIso8601String(),
                },
              ],
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThreadTheme.theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TrendPanel(
                service: service,
                onSelected: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      expect(calls, 0);
      await tester.tap(find.text('Check latest headlines'));
      await tester.pumpAndSettle();
      expect(find.text('Try preppy loafers'), findsOneWidget);
      await tester.tap(find.text('Try preppy'));
      expect(selected, StyleDirection.preppy);
      await tester.tap(find.text('Refresh headlines'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Showing the last loaded headlines'),
        findsOneWidget,
      );
      expect(find.text('Try preppy loafers'), findsOneWidget);
    },
  );

  testWidgets('fits a narrow screen with large text and an empty feed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = TrendService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'schemaVersion': 1,
            'fetchedAt': DateTime.now().toUtc().toIso8601String(),
            'sources': [
              {'name': 'GQ', 'status': 'ok'},
            ],
            'items': [],
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThreadTheme.theme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: TrendPanel(service: service, onSelected: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Check latest headlines'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No eligible headlines'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
