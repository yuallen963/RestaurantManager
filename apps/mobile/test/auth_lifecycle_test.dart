import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/auth/auth_screens.dart';
import 'package:restaurant_profit_mobile/main.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Widget app(Dio dio, {Widget home = const AuthScreen()}) => ProviderScope(
    overrides: [
      api.overrideWithValue(dio),
      authDeviceIdProvider.overrideWith((_) async => 'test-device'),
    ],
    child: MaterialApp(home: home),
  );

  testWidgets(
    'registration leads to check-email instead of creating a session',
    (tester) async {
      final dio = stubDio((options) {
        expect(options.path, '/auth/register');
        expect(
          options.data,
          containsPair(
            'invitationToken',
            'invitation-code-12345678901234567890',
          ),
        );
        return {
          'verificationRequired': true,
          'email': 'owner@example.com',
          'developmentVerificationToken': 'v-token',
        };
      });
      await tester.pumpWidget(app(dio));
      await tester.tap(find.text('New to FundWell? Create account'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        ' Owner@Example.com ',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'secure-password',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Invitation code'),
        'invitation-code-12345678901234567890',
      );
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('owner@example.com'), findsOneWidget);
      expect(find.text('Verify now (development)'), findsOneWidget);
    },
  );

  testWidgets('invitation registration displays a specific server rejection', (
    tester,
  ) async {
    final dio = Dio()
      ..httpClientAdapter = _AuthAdapter(
        (options) => _jsonResponse(401, {'message': 'Invitation has expired'}),
      );
    await tester.pumpWidget(
      app(dio, home: const AuthScreen(initialCreatingAccount: true)),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Invitation has expired'), findsOneWidget);
  });

  testWidgets('duplicate registration gives an actionable safe error', (
    tester,
  ) async {
    await tester.pumpWidget(app(errorDio(409)));
    await tester.tap(find.text('New to FundWell? Create account'));
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

  testWidgets(
    'login challenge is persisted and shown before a session exists',
    (tester) async {
      final dio = stubDio((options) {
        expect(options.path, '/auth/login');
        return {
          'challengeRequired': true,
          'challengeId': 'challenge-1',
          'method': 'EMAIL',
          'expiresInSeconds': 300,
        };
      });
      await tester.pumpWidget(app(dio));
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'owner@example.com',
      );
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Verify sign-in'), findsOneWidget);
      expect(find.text('Verify and sign in'), findsOneWidget);
      expect(await storage.read(key: 'accessToken'), isNull);
      expect(await storage.read(key: pendingAuthChallengeKey), 'challenge-1');
    },
  );

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

  test(
    'an expired access token refreshes once and retries the request',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'accessToken': 'expired-access',
        'refreshToken': 'refresh-one',
      });
      final resourceAdapter = _AuthAdapter((options) {
        if (options.headers['Authorization'] == 'Bearer fresh-access') {
          return _jsonResponse(200, {'items': <dynamic>[]});
        }
        return _jsonResponse(401, {'message': 'Unauthorized'});
      });
      final refreshAdapter = _AuthAdapter((options) {
        expect(options.path, '/auth/refresh');
        expect(jsonDecode(utf8.decode(options.data as List<int>)), {
          'refreshToken': 'refresh-one',
        });
        return _jsonResponse(200, {
          'accessToken': 'fresh-access',
          'refreshToken': 'refresh-two',
        });
      });
      final client = Dio(BaseOptions(baseUrl: 'https://fundwell.test'))
        ..options.headers['Authorization'] = 'Bearer expired-access'
        ..httpClientAdapter = resourceAdapter;
      final refreshClient = Dio(BaseOptions(baseUrl: 'https://fundwell.test'))
        ..httpClientAdapter = refreshAdapter;
      installAuthRefreshInterceptor(client, refreshClient: refreshClient);

      final response = await client.get('/expenses');

      expect(response.statusCode, 200);
      expect(resourceAdapter.calls, 2);
      expect(refreshAdapter.calls, 1);
      expect(await storage.read(key: 'accessToken'), 'fresh-access');
      expect(await storage.read(key: 'refreshToken'), 'refresh-two');
    },
  );

  test(
    'a rejected refresh preserves the original unauthorized response',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'accessToken': 'expired-access',
        'refreshToken': 'expired-refresh',
      });
      final resourceAdapter = _AuthAdapter(
        (_) => _jsonResponse(401, {'message': 'Unauthorized'}),
      );
      final refreshAdapter = _AuthAdapter(
        (_) => _jsonResponse(401, {'message': 'Unauthorized'}),
      );
      final client = Dio(BaseOptions(baseUrl: 'https://fundwell.test'))
        ..options.headers['Authorization'] = 'Bearer expired-access'
        ..httpClientAdapter = resourceAdapter;
      final refreshClient = Dio(BaseOptions(baseUrl: 'https://fundwell.test'))
        ..httpClientAdapter = refreshAdapter;
      var sessionExpiredCalls = 0;
      installAuthRefreshInterceptor(
        client,
        refreshClient: refreshClient,
        onSessionExpired: () => sessionExpiredCalls++,
      );

      await expectLater(
        client.get('/expenses'),
        throwsA(
          isA<DioException>().having(
            (error) => error.response?.statusCode,
            'status',
            401,
          ),
        ),
      );
      expect(resourceAdapter.calls, 1);
      expect(refreshAdapter.calls, 1);
      expect(await storage.read(key: 'accessToken'), isNull);
      expect(await storage.read(key: 'refreshToken'), isNull);
      expect(sessionExpiredCalls, 1);
    },
  );

  test('a public login rejection never attempts token refresh', () async {
    var expiredCalls = 0;
    final resourceAdapter = _AuthAdapter(
      (_) => _jsonResponse(401, {'message': 'Unauthorized'}),
    );
    final refreshAdapter = _AuthAdapter(
      (_) => _jsonResponse(200, {
        'accessToken': 'unexpected',
        'refreshToken': 'unexpected',
      }),
    );
    final client = Dio(BaseOptions(baseUrl: 'https://fundwell.test'))
      ..httpClientAdapter = resourceAdapter;
    installAuthRefreshInterceptor(
      client,
      refreshClient: Dio(BaseOptions(baseUrl: 'https://fundwell.test'))
        ..httpClientAdapter = refreshAdapter,
      onSessionExpired: () => expiredCalls++,
    );

    await expectLater(client.post('/auth/login'), throwsA(isA<DioException>()));
    expect(refreshAdapter.calls, 0);
    expect(expiredCalls, 0);
  });
}

ResponseBody _jsonResponse(int status, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

class _AuthAdapter implements HttpClientAdapter {
  _AuthAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
      options.data = bytes;
    }
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
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
