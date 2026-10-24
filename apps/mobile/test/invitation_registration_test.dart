import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/auth/auth_screens.dart';
import 'package:restaurant_profit_mobile/main.dart';

void main() {
  testWidgets('invitation preview locks identity and creates an account', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            if (options.path == '/auth/invitation-preview') {
              expect(options.data, {'token': 'synthetic-invitation-token'});
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'email': 'owner@example.com',
                    'type': 'JOIN_ORGANIZATION',
                    'organizationName': 'Private Account',
                    'role': 'ADMIN',
                    'expiresAt': '2030-01-01T00:00:00.000Z',
                  },
                ),
              );
              return;
            }
            if (options.path == '/auth/register') {
              expect(options.data, {
                'email': 'owner@example.com',
                'password': 'a-secure-password',
                'invitationToken': 'synthetic-invitation-token',
              });
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'verificationRequired': true,
                    'email': 'owner@example.com',
                  },
                ),
              );
              return;
            }
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 404),
              ),
            );
          },
        ),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [api.overrideWithValue(dio)],
        child: const MaterialApp(
          home: InvitationRegistrationScreen(
            invitationToken: 'synthetic-invitation-token',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Join Private Account'), findsOneWidget);
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);
    expect(find.byKey(const Key('invitation-email')), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.enterText(
      find.byKey(const Key('invitation-password')),
      'a-secure-password',
    );
    await tester.enterText(
      find.byKey(const Key('invitation-password-confirmation')),
      'a-secure-password',
    );
    await tester.tap(find.byKey(const Key('accept-invitation')));
    await tester.pumpAndSettle();

    expect(find.text('Check your email'), findsOneWidget);
    expect(requests.map((request) => request.path), [
      '/auth/invitation-preview',
      '/auth/register',
    ]);
  });

  testWidgets('new restaurant invitation explains owner setup accurately', (
    tester,
  ) async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'email': 'new-owner@example.com',
                  'type': 'NEW_ORGANIZATION',
                  'organizationName': 'New Restaurant Group',
                  'role': 'OWNER',
                  'expiresAt': '2030-01-01T00:00:00.000Z',
                },
              ),
            );
          },
        ),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [api.overrideWithValue(dio)],
        child: const MaterialApp(
          home: InvitationRegistrationScreen(
            invitationToken: 'synthetic-new-organization-token',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set up New Restaurant Group'), findsOneWidget);
    expect(find.text('Restaurant owner'), findsOneWidget);
    expect(find.text('Join New Restaurant Group'), findsNothing);
  });

  testWidgets('missing invitation token fails without an API request', (
    tester,
  ) async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) =>
              handler.reject(DioException(requestOptions: options)),
        ),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [api.overrideWithValue(dio)],
        child: const MaterialApp(home: InvitationRegistrationScreen()),
      ),
    );
    await tester.pump();

    expect(
      find.text('This invitation link is incomplete or invalid.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('invalid invitation fails safely', (tester) async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 401),
            ),
          ),
        ),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [api.overrideWithValue(dio)],
        child: const MaterialApp(
          home: InvitationRegistrationScreen(
            invitationToken: 'invalid-synthetic-token',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This invitation is invalid, expired, or already used.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
  });
}
