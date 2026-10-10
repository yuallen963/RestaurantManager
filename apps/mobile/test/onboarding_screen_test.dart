import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/onboarding/onboarding_screen.dart';
import 'package:restaurant_profit_mobile/main.dart';

void main() {
  Widget app(int step, {List<String> sources = const []}) => ProviderScope(
    overrides: [
      api.overrideWithValue(_dio(step, sources)),
      activeLocationProvider.overrideWithValue(null),
      activeLocationStateProvider.overrideWithValue(
        const AsyncData(ActiveLocationState([], null)),
      ),
    ],
    child: const MaterialApp(home: Onboarding()),
  );

  testWidgets('new onboarding starts at the focused welcome step', (
    tester,
  ) async {
    await tester.pumpWidget(app(1));
    await tester.pumpAndSettle();
    expect(
      find.text('Find the costs quietly eating your restaurant’s margin.'),
      findsOneWidget,
    );
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('restaurant step validates required names', (tester) async {
    await tester.pumpWidget(app(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Enter Organization / business name'), findsOneWidget);
    expect(find.text('Enter Restaurant location name'), findsOneWidget);
  });

  testWidgets('interrupted onboarding resumes data-source selection', (
    tester,
  ) async {
    await tester.pumpWidget(app(3, sources: const ['INVOICES', 'BANK']));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'How would you like ProfitLens to learn about your restaurant?',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Invoices'),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Bank'),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('invoice step allows upload or skipping without extraction', (
    tester,
  ) async {
    await tester.pumpWidget(app(4, sources: const ['INVOICES']));
    await tester.pumpAndSettle();
    expect(find.text('Upload a few recent vendor invoices'), findsOneWidget);
    expect(find.text('Upload Invoice'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);
  });

  testWidgets('optional connections can be skipped and resume at finish', (
    tester,
  ) async {
    await tester.pumpWidget(app(5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up later'));
    await tester.pumpAndSettle();
    expect(find.text('You’re ready to start.'), findsOneWidget);
    expect(find.text('Go to Dashboard'), findsOneWidget);
  });
}

Dio _dio(int initialStep, List<String> initialSources) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final requestedStep = (options.data as Map?)?['currentStep'] as int?;
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'currentStep': requestedStep ?? initialStep,
              'onboardingCompletedAt': null,
              'selectedDataSources':
                  (options.data as Map?)?['selectedDataSources'] ??
                  initialSources,
              'organization': null,
              'restaurantLocation': null,
            },
          ),
        );
      },
    ),
  );
