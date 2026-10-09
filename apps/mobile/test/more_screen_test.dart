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
    final container = await pumpMore(tester);

    await tester.scrollUntilVisible(find.text('Downtown Grill'), 250);
    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pumpAndSettle();
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
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var logoutCalls = 0;
    final dio = successfulLogoutDio(onLogout: () => logoutCalls++);
    dio.options.headers['Authorization'] = 'Bearer access-token';
    final container = await pumpMore(tester, dio: dio);

    final signOut = find.text('Sign Out');
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
