import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/more/foundation.dart';
import 'package:restaurant_profit_mobile/features/more/more_screen.dart';
import 'package:restaurant_profit_mobile/main.dart';

const downtown = RestaurantLocation(
  id: 'downtown',
  name: 'Downtown Grill',
  organizationId: 'organization',
);
const lakeside = RestaurantLocation(
  id: 'lakeside',
  name: 'Lakeside Grill',
  organizationId: 'organization',
);
const account = MoreAccountData(
  email: 'demo@profitlens.local',
  organizationName: 'Demo Restaurant Group',
  accountMode: AccountSessionMode.standard,
  role: 'OWNER',
);
const metadata = AppMetadata(version: '1.2.3', buildNumber: '45');

class TestLocationController extends ActiveLocationController {
  @override
  Future<ActiveLocationState> build() async =>
      const ActiveLocationState([downtown, lakeside], downtown);
}

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'accessToken': 'access-token',
      'refreshToken': 'refresh-token',
    }),
  );

  ProviderContainer createContainer({
    bool demoMode = false,
    Dio? dio,
    AsyncValue<MoreAccountData> accountValue = const AsyncData(account),
  }) => ProviderContainer(
    overrides: [
      api.overrideWithValue(dio ?? successfulLogoutDio()),
      activeLocationControllerProvider.overrideWith(TestLocationController.new),
      moreAccountProvider.overrideWith(
        (_) => accountValue.when(
          data: Future.value,
          error: Future.error,
          loading: () => Completer<MoreAccountData>().future,
        ),
      ),
      appMetadataProvider.overrideWith((_) async => metadata),
      demoModeProvider.overrideWithValue(demoMode),
    ],
  );

  Future<ProviderContainer> pumpMore(
    WidgetTester tester, {
    bool demoMode = false,
    Dio? dio,
    AsyncValue<MoreAccountData> accountValue = const AsyncData(account),
  }) async {
    final container = createContainer(
      demoMode: demoMode,
      dio: dio,
      accountValue: accountValue,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: MoreScreen())),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('renders organization, location, account, version, and build', (
    tester,
  ) async {
    await pumpMore(tester);

    expect(find.text('Demo Restaurant Group'), findsOneWidget);
    expect(find.text('Downtown Grill'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('demo@profitlens.local'), 250);
    expect(find.text('demo@profitlens.local'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Version'), 250);
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
  });

  testWidgets('location selector opens and updates the shared location state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await pumpMore(tester);

    await tester.scrollUntilVisible(find.text('Downtown Grill'), 250);
    await tester.ensureVisible(find.text('Downtown Grill'));
    await tester.tap(find.text('Downtown Grill'));
    await tester.pumpAndSettle();
    expect(find.text('Select restaurant'), findsOneWidget);
    expect(find.text('Lakeside Grill'), findsOneWidget);

    await tester.tap(find.text('Lakeside Grill'));
    await tester.pumpAndSettle();

    expect(find.text('Lakeside Grill'), findsOneWidget);
    expect(container.read(activeLocationProvider)?.id, 'lakeside');
  });

  testWidgets('sign out calls logout, clears credentials, and shows login', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var logoutCalls = 0;
    final dio = successfulLogoutDio(onLogout: () => logoutCalls++);
    dio.options.headers['Authorization'] = 'Bearer access-token';
    final container = await pumpMore(tester, dio: dio);

    final signOut = find.text('Sign Out');
    await tester.scrollUntilVisible(signOut, 250);
    await tester.tap(signOut);
    await tester.pumpAndSettle();

    expect(logoutCalls, 1);
    expect(await storage.read(key: 'accessToken'), isNull);
    expect(await storage.read(key: 'refreshToken'), isNull);
    expect(dio.options.headers['Authorization'], isNull);
    expect(container.read(activeLocationProvider), isNull);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
  });

  testWidgets('demo mode label appears only when enabled', (tester) async {
    await pumpMore(tester, demoMode: true);
    expect(find.text('Demo Mode'), findsOneWidget);

    await pumpMore(tester, demoMode: false);
    expect(find.text('Demo Mode'), findsNothing);
  });

  testWidgets('account failure renders an error and retry action', (
    tester,
  ) async {
    await pumpMore(
      tester,
      accountValue: AsyncError(Exception('network'), StackTrace.empty),
    );

    expect(find.text('Unable to load restaurant information'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Unable to load account information'),
      250,
    );
    expect(find.text('Unable to load account information'), findsOneWidget);
    expect(find.text('Retry'), findsNWidgets(2));
  });

  testWidgets(
    'private entry is at the bottom and opens an obscured password dialog',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpMore(tester);
      final entry = find.text('Private Account');
      await tester.scrollUntilVisible(entry.last, 300);
      await tester.tap(entry.last);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
      expect(find.text('Submit'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    },
  );

  testWidgets(
    'incorrect private code shows an error and does not switch sessions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(requestOptions: options, statusCode: 401),
                ),
              );
            },
          ),
        );
      final container = await pumpMore(tester, dio: dio);
      final entry = find.text('Private Account');
      await tester.scrollUntilVisible(entry.last, 300);
      await tester.tap(entry.last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(find.text('Incorrect password.'), findsOneWidget);
      expect(
        container.read(accountSessionModeProvider),
        AccountSessionMode.standard,
      );
    },
  );

  test(
    'private and beta session switches replace secure credentials',
    () async {
      final paths = <String>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              paths.add(options.path);
              if (options.path == '/auth/private-session') {
                return handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'accessToken': 'private-access',
                      'refreshToken': 'private-refresh',
                      'accountMode': 'private',
                    },
                  ),
                );
              }
              if (options.path == '/auth/shared-test-session') {
                expect(
                  options.headers['X-FundWell-Shared-Test-Token'],
                  sharedTestClientToken,
                );
                return handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'accessToken': 'beta-access',
                      'refreshToken': 'beta-refresh',
                    },
                  ),
                );
              }
              return handler.resolve(
                Response<void>(requestOptions: options, statusCode: 204),
              );
            },
          ),
        );
      final repository = MoreRepository(dio, storage);
      await repository.unlockPrivate(
        'server-verified-only',
        deviceId: 'test-device',
        deviceName: 'Test iPhone',
      );
      expect(await storage.read(key: 'accessToken'), 'private-access');
      expect(await storage.read(key: sessionModeStorageKey), 'private');
      await repository.returnToBeta();
      expect(
        paths,
        containsAllInOrder([
          '/auth/private-session',
          '/auth/logout',
          '/auth/shared-test-session',
        ]),
      );
      expect(await storage.read(key: 'accessToken'), 'beta-access');
      expect(await storage.read(key: sessionModeStorageKey), 'standard');
    },
  );
}

Dio successfulLogoutDio({VoidCallback? onLogout}) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path == '/auth/logout') onLogout?.call();
        handler.resolve(
          Response<void>(requestOptions: options, statusCode: 204),
        );
      },
    ),
  );
