@TestOn('browser')
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/auth/auth_session_store_web.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/main.dart';

void main() {
  test('shared beta auto-login is disabled for every web build', () {
    expect(sharedTestModeAllowed(requested: true, isWeb: true), isFalse);
    expect(sharedTestModeAllowed(requested: true, isWeb: false), isTrue);
  });

  test('OAuth login return paths remain local to the PWA', () {
    expect(
      safeWebReturnPath('/plaid/oauth?oauth_state_id=state-a'),
      '/plaid/oauth?oauth_state_id=state-a',
    );
    expect(safeWebReturnPath('https://evil.example/steal'), isNull);
    expect(safeWebReturnPath('//evil.example/steal'), isNull);
    expect(safeWebReturnPath('javascript:alert(1)'), isNull);
  });

  test(
    'browser access and refresh tokens are not persisted in web storage',
    () async {
      final first = WebAuthSessionStore();
      await first.write(key: 'accessToken', value: 'short-lived-access');
      await first.write(key: 'refreshToken', value: 'refresh-secret');
      await first.write(key: 'accountSessionMode', value: 'private');

      final reloaded = WebAuthSessionStore();
      expect(await reloaded.read(key: 'accessToken'), isNull);
      expect(await reloaded.read(key: 'refreshToken'), isNull);
      expect(await reloaded.read(key: 'accountSessionMode'), 'private');

      await first.delete(key: 'accountSessionMode');
    },
  );

  test(
    'browser API client requests cookie credentials with an explicit marker',
    () {
      final client = createApiClient();
      expect(client.options.headers['X-FundWell-Client'], 'web');
    },
  );

  testWidgets(
    'browser reload restores a session through the cookie refresh endpoint',
    (tester) async {
      await storage.delete(key: 'accessToken');
      await storage.delete(key: 'refreshToken');
      var refreshCalls = 0;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              if (options.path == '/auth/refresh') {
                refreshCalls++;
                expect(options.data, isEmpty);
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'accessToken': 'restored-access'},
                  ),
                );
                return;
              }
              if (options.path == '/onboarding') {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'onboardingCompletedAt': '2026-10-22T00:00:00.000Z',
                      'currentStep': 5,
                      'selectedDataSources': <String>[],
                    },
                  ),
                );
                return;
              }
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{},
                ),
              );
            },
          ),
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            api.overrideWithValue(dio),
            demoModeProvider.overrideWithValue(false),
            sharedTestUserModeProvider.overrideWithValue(false),
            activeLocationStateProvider.overrideWithValue(
              const AsyncData(ActiveLocationState([], null)),
            ),
            activeLocationProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(home: AuthBootstrap()),
        ),
      );
      await tester.pumpAndSettle();

      expect(refreshCalls, 1);
      expect(find.byType(Home), findsOneWidget);
      expect(await storage.read(key: 'accessToken'), 'restored-access');
      expect(await storage.read(key: 'refreshToken'), isNull);
    },
  );

  testWidgets(
    'browser enters the read-only public demo when no private session exists',
    (tester) async {
      await storage.delete(key: 'accessToken');
      await storage.delete(key: 'refreshToken');
      await storage.delete(key: sessionModeStorageKey);
      final paths = <String>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              paths.add(options.path);
              if (options.path == '/auth/refresh') {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 401,
                    ),
                  ),
                );
                return;
              }
              if (options.path == '/auth/public-demo-session') {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'accessToken': 'public-demo-access',
                      'tokenType': 'Bearer',
                      'accountMode': 'demo',
                    },
                  ),
                );
                return;
              }
              if (options.path == '/onboarding') {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'onboardingCompletedAt': '2026-10-22T00:00:00.000Z',
                      'currentStep': 6,
                      'selectedDataSources': <String>[],
                    },
                  ),
                );
                return;
              }
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{},
                ),
              );
            },
          ),
        );

      final container = ProviderContainer(
        overrides: [
          api.overrideWithValue(dio),
          sharedTestUserModeProvider.overrideWithValue(false),
          activeLocationStateProvider.overrideWithValue(
            const AsyncData(ActiveLocationState([], null)),
          ),
          activeLocationProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AuthBootstrap()),
        ),
      );
      await tester.pumpAndSettle();

      expect(paths, contains('/auth/public-demo-session'));
      expect(find.byType(Home), findsOneWidget);
      expect(
        container.read(accountSessionModeProvider),
        AccountSessionMode.demo,
      );
      expect(container.read(demoModeProvider), isTrue);
      expect(await storage.read(key: 'refreshToken'), isNull);
    },
  );
}
