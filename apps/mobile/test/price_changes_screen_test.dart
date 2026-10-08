import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/price_intelligence/foundation.dart';
import 'package:restaurant_profit_mobile/features/price_intelligence/price_changes_screen.dart';

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

PriceChangeItem change({
  String key = 'chicken',
  String name = 'Boneless Chicken Breast',
  String vendor = 'Sysco',
  double previous = 91,
  double current = 106.5,
  double percentage = 17.03,
  double impact = 186,
}) => PriceChangeItem(
  vendorId: vendor.toLowerCase(),
  vendorName: vendor,
  itemKey: key,
  displayName: name,
  sku: '384920',
  unit: 'CASE',
  packSize: '4 x 10 lb',
  previousUnitPrice: previous,
  currentUnitPrice: current,
  absoluteChange: current - previous,
  percentageChange: percentage,
  typicalMonthlyQuantity: 12,
  estimatedMonthlyImpact: impact,
  estimatedAnnualImpact: impact * 12,
  firstSeenAt: DateTime.utc(2026, 8, 5),
  latestSeenAt: DateTime.utc(2026, 10, 2),
);

final increase = change();
final decrease = change(
  key: 'cola',
  name: 'Cola Syrup',
  vendor: 'US Foods',
  previous: 55,
  current: 49,
  percentage: -10.91,
  impact: -72,
);

class FakePriceRepository extends PriceIntelligenceRepository {
  FakePriceRepository({this.onChanges, this.onHistory}) : super(Dio());
  final Future<PriceChangesData> Function(
    String location,
    PriceChangeSort sort,
  )?
  onChanges;
  final Future<PriceHistoryData> Function(String location, String itemKey)?
  onHistory;
  final calls = <String>[];
  final sorts = <PriceChangeSort>[];

  @override
  Future<PriceChangesData> changes({
    required String restaurantLocationId,
    required PriceChangeSort sort,
  }) {
    calls.add(restaurantLocationId);
    sorts.add(sort);
    return onChanges?.call(restaurantLocationId, sort) ??
        Future.value(
          PriceChangesData(items: [increase, decrease], lookbackDays: 90),
        );
  }

  @override
  Future<PriceHistoryData> history({
    required String restaurantLocationId,
    required String itemKey,
  }) {
    return onHistory?.call(restaurantLocationId, itemKey) ??
        Future.value(
          PriceHistoryData(
            item: increase,
            history: [
              PriceHistoryPoint(
                date: DateTime.utc(2026, 8, 5),
                invoiceId: 'invoice-one',
                unitPrice: 91,
                quantity: 12,
              ),
              PriceHistoryPoint(
                date: DateTime.utc(2026, 9, 3),
                invoiceId: 'invoice-two',
                unitPrice: 98,
                quantity: 12,
              ),
              PriceHistoryPoint(
                date: DateTime.utc(2026, 10, 2),
                invoiceId: 'invoice-three',
                unitPrice: 106.5,
                quantity: 12,
              ),
            ],
          ),
        );
  }
}

void main() {
  Widget app(FakePriceRepository repository, {ProviderContainer? container}) {
    const child = MaterialApp(home: PriceChangesScreen());
    if (container != null) {
      return UncontrolledProviderScope(container: container, child: child);
    }
    return ProviderScope(
      overrides: [
        activeLocationProvider.overrideWithValue(downtown),
        availableLocationsProvider.overrideWithValue([downtown, lakeside]),
        priceIntelligenceRepositoryProvider.overrideWithValue(repository),
      ],
      child: child,
    );
  }

  testWidgets('shows loading, empty, and error states', (tester) async {
    final pending = Completer<PriceChangesData>();
    await tester.pumpWidget(
      app(FakePriceRepository(onChanges: (_, _) => pending.future)),
    );
    await tester.pump();
    expect(find.text('Loading price changes...'), findsOneWidget);
    pending.complete(const PriceChangesData(items: [], lookbackDays: 90));
    await tester.pumpAndSettle();
    expect(find.text('No significant price changes found.'), findsOneWidget);

    await tester.pumpWidget(
      app(FakePriceRepository(onChanges: (_, _) => Future.error('network'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load price changes'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('renders increases, decreases, and estimated monthly impact', (
    tester,
  ) async {
    await tester.pumpWidget(app(FakePriceRepository()));
    await tester.pumpAndSettle();
    expect(find.text('Boneless Chicken Breast'), findsOneWidget);
    expect(find.text('\$91.00 → \$106.50 / CASE'), findsOneWidget);
    expect(find.text('↑ 17.0%'), findsOneWidget);
    expect(find.text('Est. added cost +\$186.00/month'), findsOneWidget);
    expect(find.text('Cola Syrup'), findsOneWidget);
    expect(find.text('↓ 10.9%'), findsOneWidget);
    expect(find.text('Est. savings -\$72.00/month'), findsOneWidget);
    expect(
      find.text('NITRILE GLOVES LARGE'),
      findsNothing,
      reason: 'incompatible data is excluded by the API',
    );
  });

  testWidgets('changing sort refetches with the selected server sort', (
    tester,
  ) async {
    final repository = FakePriceRepository();
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('price-change-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Largest Monthly Impact').last);
    await tester.pumpAndSettle();
    expect(repository.sorts.last, PriceChangeSort.largestMonthlyImpact);
  });

  testWidgets('active location changes trigger a location-scoped refresh', (
    tester,
  ) async {
    final repository = FakePriceRepository();
    final container = ProviderContainer(
      overrides: [
        activeLocationProvider.overrideWith(
          (ref) => ref.watch(mutableLocationProvider),
        ),
        availableLocationsProvider.overrideWithValue([downtown, lakeside]),
        priceIntelligenceRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(app(repository, container: container));
    await tester.pumpAndSettle();
    container.read(mutableLocationProvider.notifier).state = lakeside;
    await tester.pumpAndSettle();
    expect(repository.calls, containsAllInOrder(['downtown', 'lakeside']));
  });

  testWidgets('opens traceable price history detail and renders chart', (
    tester,
  ) async {
    await tester.pumpWidget(app(FakePriceRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Boneless Chicken Breast'));
    await tester.pumpAndSettle();
    expect(find.text('Price History'), findsOneWidget);
    expect(find.text('Current price'), findsOneWidget);
    expect(find.text('Typical monthly volume'), findsOneWidget);
    expect(find.text('Estimated annual impact'), findsOneWidget);
    expect(find.byKey(const Key('price-history-chart')), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('\$98.00'), findsOneWidget);
    expect(find.byKey(const Key('price-point-invoice-two')), findsOneWidget);
  });
}
