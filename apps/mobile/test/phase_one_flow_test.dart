import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/main.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/onboarding/onboarding_screen.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Widget appWith(Dio dio) => ProviderScope(
    overrides: [api.overrideWithValue(dio)],
    child: const MaterialApp(home: AuthScreen()),
  );

  testWidgets('unauthenticated state renders the login form', (tester) async {
    await tester.pumpWidget(appWith(successfulDio()));

    expect(find.text('Profit Lens'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
  });

  testWidgets(
    'successful authentication persists tokens and enters onboarding',
    (tester) async {
      await tester.pumpWidget(appWith(successfulDio()));
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'owner@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'safe-password',
      );
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(
        find.text('Find the costs quietly eating your restaurant’s margin.'),
        findsOneWidget,
      );
      expect(await storage.read(key: 'accessToken'), 'access-token');
      expect(await storage.read(key: 'refreshToken'), 'refresh-token');
    },
  );

  testWidgets('API failure shows an error and restores the login action', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(failingDio()));
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to sign in.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Log in'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('in-flight authentication disables duplicate submission', (
    tester,
  ) async {
    final response = Completer<Response<dynamic>>();
    await tester.pumpWidget(appWith(deferredDio(response)));
    await tester.tap(find.text('Log in'));
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Log in'))
          .onPressed,
      isNull,
    );
    response.complete(
      Response(
        requestOptions: RequestOptions(path: '/auth/login'),
        data: {'accessToken': 'a', 'refreshToken': 'b'},
        statusCode: 200,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('onboarding completion routes to the dashboard shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          api.overrideWithValue(onboardingDio(step: 6)),
          activeLocationProvider.overrideWithValue(null),
          activeLocationStateProvider.overrideWithValue(
            const AsyncData(ActiveLocationState([], null)),
          ),
        ],
        child: const MaterialApp(home: Onboarding()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to Dashboard'));
    await tester.pumpAndSettle();

    expect(find.byType(Home), findsOneWidget);
  });

  testWidgets('dashboard exposes every Phase 1 navigation destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLocationProvider.overrideWithValue(null),
          activeLocationStateProvider.overrideWithValue(
            const AsyncData(ActiveLocationState([], null)),
          ),
        ],
        child: const MaterialApp(home: Home()),
      ),
    );

    for (final label in ['Home', 'Expenses', 'Revenue', 'Vendors', 'More']) {
      expect(find.text(label), findsOneWidget);
    }
  });
}

Dio successfulDio() => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(
        Response(
          requestOptions: options,
          data: {
            'accessToken': 'access-token',
            'refreshToken': 'refresh-token',
          },
          statusCode: 200,
        ),
      ),
    ),
  );

Dio failingDio() => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      ),
    ),
  );

Dio deferredDio(Completer<Response<dynamic>> response) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          handler.resolve(await response.future);
        } catch (error) {
          handler.reject(DioException(requestOptions: options, error: error));
        }
      },
    ),
  );

Dio onboardingDio({required int step}) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(
        Response(
          requestOptions: options,
          data: {
            'currentStep': step,
            'onboardingCompletedAt': options.path.endsWith('/complete')
                ? DateTime(2026).toIso8601String()
                : null,
            'selectedDataSources': ['INVOICES'],
            'organization': {'id': 'org-1', 'name': 'Test Restaurant Group'},
            'restaurantLocation': {
              'id': 'location-1',
              'name': 'Downtown',
              'timezone': 'America/Detroit',
            },
          },
          statusCode: 200,
        ),
      ),
    ),
  );
