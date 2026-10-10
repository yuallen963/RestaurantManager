import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/more/account_security_screen.dart';
import 'package:restaurant_profit_mobile/features/more/foundation.dart';
import 'package:restaurant_profit_mobile/main.dart';

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'accessToken': 'access',
      'refreshToken': 'refresh',
    }),
  );

  Widget app(Dio dio, {bool demo = false}) => ProviderScope(
    overrides: [
      demoModeProvider.overrideWithValue(demo),
      moreRepositoryProvider.overrideWithValue(MoreRepository(dio, storage)),
    ],
    child: const MaterialApp(home: AccountSecurityScreen()),
  );

  testWidgets('demo account deletion is visibly disabled', (tester) async {
    await tester.pumpWidget(app(Dio(), demo: true));

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Demo account cannot be deleted'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('account deletion requires password and explicit confirmation', (
    tester,
  ) async {
    var deletes = 0;
    final dio = requestDio((options) {
      if (options.method == 'DELETE' && options.path == '/auth/account') {
        deletes++;
        expect((options.data as Map)['password'], 'secure-password');
      }
    });
    dio.options.headers['Authorization'] = 'Bearer access';
    await tester.pumpWidget(app(dio));

    await tester.tap(find.widgetWithText(FilledButton, 'Delete account').last);
    await tester.pump();
    expect(
      find.text('Enter your password to confirm deletion.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'secure-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete account?'), findsOneWidget);
    expect(deletes, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account').last);
    await tester.pumpAndSettle();

    expect(deletes, 1);
    expect(await storage.read(key: 'accessToken'), isNull);
    expect(await storage.read(key: 'refreshToken'), isNull);
    expect(dio.options.headers['Authorization'], isNull);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
  });

  testWidgets(
    'ownership conflict preserves the account and explains recovery',
    (tester) async {
      await tester.pumpWidget(app(errorDio(409)));
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm password'),
        'secure-password',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Delete account').last,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Delete account').last,
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Transfer organization ownership before deleting your account.',
        ),
        findsOneWidget,
      );
      expect(await storage.read(key: 'accessToken'), 'access');
    },
  );
}

Dio requestDio(void Function(RequestOptions options) inspect) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        inspect(options);
        handler.resolve(
          Response<void>(requestOptions: options, statusCode: 204),
        );
      },
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
