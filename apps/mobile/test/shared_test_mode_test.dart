import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/main.dart';

void main() {
  Future<void> pumpBootstrap(
    WidgetTester tester,
    Dio dio, {
    required bool sharedMode,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          api.overrideWithValue(dio),
          sharedTestUserModeProvider.overrideWithValue(sharedMode),
          demoModeProvider.overrideWithValue(false),
          activeLocationStateProvider.overrideWithValue(
            const AsyncData(ActiveLocationState([], null)),
          ),
          activeLocationProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: AuthBootstrap()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shared test mode bypasses login and stores a fresh session', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    var sharedSessionCalls = 0;
    final dio = _dio((options) {
      expect(options.path, '/auth/shared-test-session');
      sharedSessionCalls++;
      return {'accessToken': 'shared-access', 'refreshToken': 'shared-refresh'};
    });

    await pumpBootstrap(tester, dio, sharedMode: true);

    expect(sharedSessionCalls, 1);
    expect(find.byType(Home), findsOneWidget);
    expect(find.text('Log in'), findsNothing);
    expect(await storage.read(key: 'accessToken'), 'shared-access');
    expect(await storage.read(key: 'refreshToken'), 'shared-refresh');
  });

  testWidgets('shared test mode replaces stale local credentials', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'accessToken': 'stale-access',
      'refreshToken': 'stale-refresh',
    });
    var sharedSessionCalls = 0;
    final dio = _dio((options) {
      expect(options.path, '/auth/shared-test-session');
      sharedSessionCalls++;
      return {'accessToken': 'fresh-access', 'refreshToken': 'fresh-refresh'};
    });

    await pumpBootstrap(tester, dio, sharedMode: true);

    expect(sharedSessionCalls, 1);
    expect(await storage.read(key: 'accessToken'), 'fresh-access');
    expect(await storage.read(key: 'refreshToken'), 'fresh-refresh');
  });

  testWidgets('disabled shared test mode preserves normal login flow', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await pumpBootstrap(tester, Dio(), sharedMode: false);

    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    expect(find.byType(Home), findsNothing);
  });
}

Dio _dio(Map<String, dynamic> Function(RequestOptions options) response) =>
    Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: response(options),
            ),
          ),
        ),
      );
