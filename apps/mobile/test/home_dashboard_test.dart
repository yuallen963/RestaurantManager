import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/tabs.dart';

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
const currentDashboard = DashboardData(
  DashboardSummary(94200, 85900, 8300, 8.8, 28600, 30.4, 31900, 33.9),
  [
    ExpenseBreakdown('food', 'Food', 28600, 33.3),
    ExpenseBreakdown('labor', 'Labor', 31900, 37.1),
    ExpenseBreakdown('rent', 'Rent', 7500, 8.7),
  ],
);
const previousDashboard = DashboardData(
  DashboardSummary(90000, 81000, 9000, 10, 24300, 27, 26100, 29),
  [],
);

void main() {
  Widget dashboardApp({
    Future<DashboardData?> Function(Ref ref)? dashboard,
    Future<DashboardData?> Function(Ref ref)? previous,
  }) => ProviderScope(
    overrides: [
      activeLocationProvider.overrideWithValue(downtown),
      availableLocationsProvider.overrideWithValue([downtown, lakeside]),
      dashboardProvider.overrideWith(
        dashboard ?? (ref) async => currentDashboard,
      ),
      previousDashboardProvider.overrideWith(
        previous ?? (ref) async => previousDashboard,
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: HomeScreen())),
  );

  testWidgets('non-zero dashboard renders financial cards and profit focus', (
    tester,
  ) async {
    await tester.pumpWidget(dashboardApp());
    await tester.pumpAndSettle();

    expect(find.text('Downtown Grill'), findsOneWidget);
    expect(find.byKey(const Key('profit-card')), findsOneWidget);
    expect(find.text('Estimated Profit'), findsOneWidget);
    expect(find.text('\$8,300'), findsOneWidget);
    expect(find.byKey(const Key('revenue-card')), findsOneWidget);
    expect(find.text('\$94,200'), findsOneWidget);
    expect(find.byKey(const Key('expenses-card')), findsOneWidget);
    expect(find.text('\$85,900'), findsOneWidget);
    expect(find.byKey(const Key('margin-card')), findsOneWidget);
    expect(find.text('8.8%'), findsOneWidget);
  });

  testWidgets('food and labor cost bars and expense breakdown render', (
    tester,
  ) async {
    await tester.pumpWidget(dashboardApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('food-cost-bar')),
      250,
    );
    expect(find.text('Key Costs'), findsOneWidget);
    expect(find.byKey(const Key('food-cost-bar')), findsOneWidget);
    expect(find.byKey(const Key('labor-cost-bar')), findsOneWidget);
    expect(find.text('30.4%'), findsOneWidget);
    expect(find.text('33.9%'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Where your money went'), 250);
    await tester.scrollUntilVisible(find.text('Labor'), 200);
    expect(find.text('Labor'), findsOneWidget);
    expect(find.text('\$31,900'), findsOneWidget);
    expect(find.text('37.1%'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
  });

  testWidgets('comparison communicates positive and negative changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PercentageChange(current: 112, previous: 100),
              PercentageChange(current: 90, previous: 100),
            ],
          ),
        ),
      ),
    );

    expect(find.text('12.0% increase vs previous period'), findsOneWidget);
    expect(find.text('10.0% decrease vs previous period'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
  });

  testWidgets('zero previous value uses comparison fallback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PercentageChange(current: 100, previous: 0)),
      ),
    );

    expect(find.text('— vs previous period'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
  });

  testWidgets('location selector offers accessible locations and selects one', (
    tester,
  ) async {
    RestaurantLocation? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationSelector(
            active: downtown,
            locations: const [downtown, lakeside],
            onSelected: (location) async => selected = location,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('location-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a restaurant'), findsOneWidget);
    expect(find.text('Lakeside Grill'), findsOneWidget);

    await tester.tap(find.text('Lakeside Grill'));
    await tester.pumpAndSettle();
    expect(selected, lakeside);
  });

  testWidgets('date range selector updates existing date state', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: DateRangeSelector())),
        ),
      ),
    );

    expect(find.text('This Month'), findsOneWidget);
    await tester.tap(find.byKey(const Key('date-range-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 30 Days').last);
    await tester.pumpAndSettle();

    expect(container.read(dateRangeProvider).preset, DatePreset.last30Days);
    expect(find.text('Last 30 Days'), findsOneWidget);
  });

  testWidgets('all-zero dashboard shows the empty state', (tester) async {
    await tester.pumpWidget(
      dashboardApp(
        dashboard: (ref) async =>
            const DashboardData(DashboardSummary(0, 0, 0, 0, 0, 0, 0, 0), []),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No financial activity found for this period.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('profit-card')), findsNothing);
  });

  testWidgets('dashboard error shows a retry action', (tester) async {
    await tester.pumpWidget(
      dashboardApp(
        dashboard: (ref) => Future<DashboardData?>.error('network failure'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unable to load dashboard'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('dashboard fits a small iPhone width without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(dashboardApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
