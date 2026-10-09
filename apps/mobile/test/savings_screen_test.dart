import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/savings/foundation.dart';
import 'package:restaurant_profit_mobile/features/savings/savings_screen.dart';

const downtown = RestaurantLocation(
  id: 'downtown',
  name: 'Downtown Grill',
  organizationId: 'org',
);
const lakeside = RestaurantLocation(
  id: 'lakeside',
  name: 'Lakeside Grill',
  organizationId: 'org',
);
final mutableLocationProvider = StateProvider<RestaurantLocation>(
  (_) => downtown,
);

final opportunity = SavingsOpportunity(
  productGroupId: 'chicken',
  productName: 'Boneless Skinless Chicken Breast',
  currentVendor: const SavingsVendor(
    id: 'sysco',
    name: 'Sysco',
    unitPrice: 106.5,
  ),
  lowerCostVendor: const SavingsVendor(
    id: 'usf',
    name: 'US Foods',
    unitPrice: 94.2,
  ),
  unit: 'CASE',
  packSize: '40 lb',
  absoluteDifference: 12.3,
  percentageDifference: 11.55,
  typicalMonthlyQuantity: 12,
  estimatedMonthlySavings: 147.6,
  estimatedAnnualSavings: 1771.2,
  latestHigherPriceDate: DateTime.utc(2026, 10, 4),
  latestLowerPriceDate: DateTime.utc(2026, 9, 29),
  evidence: [
    SavingsEvidence(
      invoiceId: 'invoice-one',
      vendorName: 'Sysco',
      date: DateTime.utc(2026, 10, 4),
      unitPrice: 106.5,
      quantity: 12,
    ),
    SavingsEvidence(
      invoiceId: 'invoice-two',
      vendorName: 'US Foods',
      date: DateTime.utc(2026, 9, 29),
      unitPrice: 94.2,
      quantity: 12,
    ),
  ],
);
final success = SavingsData(
  opportunityCount: 1,
  estimatedMonthlySavings: 147.6,
  estimatedAnnualSavings: 1771.2,
  items: [opportunity],
  lookbackDays: 90,
);

class FakeSavingsRepository extends SavingsRepository {
  FakeSavingsRepository(this.loader) : super(Dio());
  final Future<SavingsData> Function(String) loader;
  final calls = <String>[];
  @override
  Future<SavingsData> get(String restaurantLocationId) {
    calls.add(restaurantLocationId);
    return loader(restaurantLocationId);
  }
}

Widget app(FakeSavingsRepository repository, {ProviderContainer? container}) {
  const child = MaterialApp(home: SavingsOpportunitiesScreen());
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: child);
  }
  return ProviderScope(
    overrides: [
      activeLocationProvider.overrideWithValue(downtown),
      availableLocationsProvider.overrideWithValue([downtown, lakeside]),
      savingsRepositoryProvider.overrideWithValue(repository),
    ],
    child: child,
  );
}

void main() {
  testWidgets(
    'renders loading then monthly and annual summary with opportunity',
    (tester) async {
      final pending = Completer<SavingsData>();
      await tester.pumpWidget(
        app(FakeSavingsRepository((_) => pending.future)),
      );
      await tester.pump();
      expect(find.text('Loading savings opportunities...'), findsOneWidget);
      pending.complete(success);
      await tester.pumpAndSettle();
      expect(find.text(r'$148'), findsOneWidget);
      expect(find.text(r'$1,771'), findsOneWidget);
      expect(find.text('Boneless Skinless Chicken Breast'), findsOneWidget);
      expect(find.textContaining(r'Sysco — $106.50/case'), findsOneWidget);
      expect(find.textContaining(r'US Foods — $94.20/case'), findsOneWidget);
    },
  );

  testWidgets('renders error and empty states', (tester) async {
    await tester.pumpWidget(
      app(FakeSavingsRepository((_) => Future.error('network'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load savings opportunities'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.pumpWidget(
      app(
        FakeSavingsRepository(
          (_) async => const SavingsData(
            opportunityCount: 0,
            estimatedMonthlySavings: 0,
            estimatedAnnualSavings: 0,
            items: [],
            lookbackDays: 90,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No meaningful savings opportunities found from recent confirmed products.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'opens detail with dates, calculations, evidence, and disclaimer',
    (tester) async {
      await tester.pumpWidget(app(FakeSavingsRepository((_) async => success)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Boneless Skinless Chicken Breast'));
      await tester.pumpAndSettle();
      expect(find.text('Savings Detail'), findsOneWidget);
      expect(find.text('Oct 4'), findsOneWidget);
      expect(find.text('Sep 29'), findsOneWidget);
      expect(find.text('12.0 cases'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.textContaining('Actual pricing may vary'), findsOneWidget);
    },
  );

  testWidgets('active location refreshes location-scoped opportunities', (
    tester,
  ) async {
    final repository = FakeSavingsRepository(
      (location) async => location == downtown.id
          ? success
          : const SavingsData(
              opportunityCount: 0,
              estimatedMonthlySavings: 0,
              estimatedAnnualSavings: 0,
              items: [],
              lookbackDays: 90,
            ),
    );
    final container = ProviderContainer(
      overrides: [
        activeLocationProvider.overrideWith(
          (ref) => ref.watch(mutableLocationProvider),
        ),
        availableLocationsProvider.overrideWithValue([downtown, lakeside]),
        savingsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(app(repository, container: container));
    await tester.pumpAndSettle();
    container.read(mutableLocationProvider.notifier).state = lakeside;
    await tester.pumpAndSettle();
    expect(repository.calls, containsAllInOrder(['downtown', 'lakeside']));
    expect(
      find.text(
        'No meaningful savings opportunities found from recent confirmed products.',
      ),
      findsOneWidget,
    );
  });
}
