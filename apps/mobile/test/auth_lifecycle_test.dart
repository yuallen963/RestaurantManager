import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/auth/auth_screens.dart';
import 'package:restaurant_profit_mobile/main.dart';

void main() {
  Widget app(Dio dio, {Widget home = const AuthScreen()}) => ProviderScope(
    overrides: [api.overrideWithValue(dio)],
    child: MaterialApp(home: home),
  );

  testWidgets(
    'registration leads to check-email instead of creating a session',
    (tester) async {
      final dio = stubDio((options) {
        expect(options.path, '/auth/register');
        return {
          'verificationRequired': true,
          'email': 'owner@example.com',
          'developmentVerificationToken': 'v-token',
        };
      });
      await tester.pumpWidget(app(dio));
      await tester.tap(find.text('New to ProfitLens? Create account'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        ' Owner@Example.com ',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'secure-password',
      );
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('owner@example.com'), findsOneWidget);
      expect(find.text('Verify now (development)'), findsOneWidget);
    },
  );

  testWidgets('duplicate registration gives an actionable safe error', (
    tester,
  ) async {
    await tester.pumpWidget(app(errorDio(409)));
    await tester.tap(find.text('New to ProfitLens? Create account'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(
      find.text('An account already exists. Log in or reset your password.'),
      findsOneWidget,
    );
  });

  testWidgets('unverified login routes to verification recovery', (
    tester,
  ) async {
    await tester.pumpWidget(app(errorDio(403)));
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'owner@example.com',
    );
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Check your email'), findsOneWidget);
    expect(find.text('Resend verification'), findsOneWidget);
  });

  testWidgets('forgot password always shows the neutral response', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        stubDio((options) {
          expect(options.path, '/auth/forgot-password');
          return {
            'message':
                'If an account exists, password reset instructions were sent.',
          };
        }),
      ),
    );
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'unknown@example.com',
    );
    await tester.tap(find.text('Send reset instructions'));
    await tester.pumpAndSettle();

    expect(find.textContaining('If an account exists'), findsOneWidget);
  });

  testWidgets(
    'reset password enforces the production minimum before the API call',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        app(
          stubDio((_) {
            calls++;
            return <String, dynamic>{};
          }),
          home: const ResetPasswordScreen(initialToken: 'reset-token'),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'New password'),
        'short',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
      await tester.pump();

      expect(find.text('Use at least 12 characters.'), findsOneWidget);
      expect(calls, 0);
    },
  );
}

Dio stubDio(Map<String, dynamic> Function(RequestOptions options) response) =>
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

Dio errorDio(int statusCode) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.reject(
        DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: statusCode),
          type: DioExceptionType.badResponse,
        ),
      ),
    ),
  );
