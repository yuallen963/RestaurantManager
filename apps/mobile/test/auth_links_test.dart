import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/auth/auth_links.dart';
import 'package:restaurant_profit_mobile/features/auth/auth_screens.dart';
import 'package:restaurant_profit_mobile/main.dart';

class FakeAuthLinkSource implements AuthLinkSource {
  FakeAuthLinkSource({this.initial});
  final Uri? initial;
  final controller = StreamController<Uri>.broadcast();
  @override
  Future<Uri?> initialLink() async => initial;
  @override
  Stream<Uri> get links => controller.stream;
}

void main() {
  test('accepts only fixed production auth paths with a non-empty token', () {
    expect(parseAuthLink(Uri.parse('https://restaurantmanager-production-6231.up.railway.app/verify-email?token=v'))?.kind, AuthLinkKind.verifyEmail);
    expect(parseAuthLink(Uri.parse('https://restaurantmanager-production-6231.up.railway.app/reset-password?token=r'))?.kind, AuthLinkKind.resetPassword);
    expect(parseAuthLink(Uri.parse('https://evil.example/reset-password?token=r')), isNull);
    expect(parseAuthLink(Uri.parse('https://restaurantmanager-production-6231.up.railway.app/plaid/oauth?token=r')), isNull);
    expect(parseAuthLink(Uri.parse('https://restaurantmanager-production-6231.up.railway.app/reset-password')), isNull);
  });

  testWidgets('terminated launch waits until bootstrap is ready and routes once', (tester) async {
    final key = GlobalKey<NavigatorState>();
    final source = FakeAuthLinkSource(initial: Uri.parse('https://restaurantmanager-production-6231.up.railway.app/reset-password?token=reset-token'));
    final coordinator = AuthLinkCoordinator(navigatorKey: key, source: source);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(navigatorKey: key, home: const Text('Home'))));
    await coordinator.start();
    await tester.pump();
    expect(find.text('Reset password'), findsNothing);
    coordinator.ready();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    source.controller.add(Uri.parse('https://restaurantmanager-production-6231.up.railway.app/reset-password?token=reset-token'));
    await tester.pumpAndSettle();
    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    coordinator.dispose();
    await source.controller.close();
  });

  testWidgets('open app handles a valid stream link and ignores invalid links or cancellation', (tester) async {
    final key = GlobalKey<NavigatorState>();
    final source = FakeAuthLinkSource();
    final coordinator = AuthLinkCoordinator(navigatorKey: key, source: source);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(navigatorKey: key, home: const Text('Home'))));
    await coordinator.start();
    coordinator.ready();
    source.controller.add(Uri.parse('https://evil.example/reset-password?token=x'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    source.controller.add(Uri.parse('https://restaurantmanager-production-6231.up.railway.app/reset-password?token=valid'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    coordinator.dispose();
    await source.controller.close();
  });

  testWidgets('expired verification link fails safely', (tester) async {
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) => handler.reject(DioException(requestOptions: options, response: Response(requestOptions: options, statusCode: 401), type: DioExceptionType.badResponse))));
    await tester.pumpWidget(ProviderScope(overrides: [api.overrideWithValue(dio)], child: const MaterialApp(home: VerifyEmailLinkScreen(token: 'expired'))));
    await tester.pumpAndSettle();
    expect(find.text('Verification link is invalid or expired.'), findsOneWidget);
  });
}
