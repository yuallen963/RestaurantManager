import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/banking/foundation.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/needs_attention/foundation.dart';
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
const noSources = DashboardAvailability(
  bank: false,
  reviewedInvoices: false,
  revenue: false,
  pos: false,
  expenses: false,
  profitability: false,
);

DashboardData adaptiveDashboard({
  bool bank = false,
  bool invoices = false,
  bool revenue = false,
  bool pos = false,
  bool expenses = false,
  bool profitability = false,
}) => DashboardData(
  DashboardSummary(
    revenue ? 12000 : 0,
    expenses ? 7000 : 0,
    5000,
    41.7,
    0,
    0,
    0,
    0,
  ),
  const [],
  availability: DashboardAvailability(
    bank: bank,
    reviewedInvoices: invoices,
    revenue: revenue,
    pos: pos,
    expenses: expenses,
    profitability: profitability,
  ),
  bank: bank
      ? const BankDashboardInsights(
          trackedOutflows: 4200,
          previousTrackedOutflows: 4000,
          uncategorizedCount: 2,
          unmatchedCount: 3,
          matchedInvoiceCount: 1,
          categoryBreakdown: [NamedAmount('Food', 3000)],
          topVendors: [NamedAmount('Atlas', 2500)],
          largestExpenses: [],
        )
      : null,
  invoices: invoices
      ? const InvoiceDashboardInsights(
          reviewedPurchases: 3600,
          reviewedCount: 4,
          requiringReviewCount: 1,
          unmatchedCount: 2,
          topVendors: [NamedAmount('Atlas', 2400)],
        )
      : null,
);

void main() {
  Widget dashboardApp({
    Future<DashboardData?> Function(Ref ref)? dashboard,
    Future<DashboardData?> Function(Ref ref)? previous,
    Stream<BankSyncStatus> Function(Ref ref)? bankSync,
    Future<List<BankTransactionData>> Function(Ref ref)? bankTransactions,
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
      bankSyncStatusProvider.overrideWith(
        bankSync ??
            (_) => Stream.value(
              const BankSyncStatus(
                state: BankImportState.complete,
                connectionCount: 1,
                transactionCount: 12,
                canRetry: false,
              ),
            ),
      ),
      bankTransactionsProvider.overrideWith(
        bankTransactions ?? (_) async => const [],
      ),
      bankTransactionsAwaitingReviewProvider.overrideWith(
        (_) async => const [],
      ),
      allBankTransactionsProvider.overrideWith((_) async => const []),
      bankConnectionsProvider.overrideWith((_) async => const []),
      needsAttentionProvider.overrideWith(
        (_) async => const NeedsAttentionData(
          summary: AttentionSummary(
            critical: 0,
            high: 0,
            medium: 0,
            low: 0,
            estimatedMonthlyImpact: 0,
          ),
          items: [],
        ),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: HomeScreen()),
            Consumer(
              builder: (context, ref, _) {
                ref.watch(bankTransactionsProvider);
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    ),
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

    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('Where your recorded expenses went'), findsOneWidget);
    expect(find.text('Labor'), findsOneWidget);
    expect(find.text('\$31,900'), findsOneWidget);
    expect(find.text('37.1%'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Key Costs'), findsOneWidget);
    expect(find.byKey(const Key('food-cost-bar')), findsOneWidget);
    expect(find.byKey(const Key('labor-cost-bar')), findsOneWidget);
    expect(find.text('30.4%'), findsOneWidget);
    expect(find.text('33.9%'), findsOneWidget);
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

  testWidgets('no sources shows honest setup guidance', (tester) async {
    await tester.pumpWidget(
      dashboardApp(
        dashboard: (ref) async => const DashboardData(
          DashboardSummary(0, 0, 0, 0, 0, 0, 0, 0),
          [],
          availability: noSources,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Connect a data source to start building your dashboard.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('profit-card')), findsNothing);
    expect(find.text('Connect Bank'), findsOneWidget);
    expect(find.text('Connect POS'), findsOneWidget);
  });

  testWidgets('bank-only data shows outflows but not profit or revenue', (
    tester,
  ) async {
    await tester.pumpWidget(
      dashboardApp(dashboard: (_) async => adaptiveDashboard(bank: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tracked bank outflows'), findsOneWidget);
    expect(find.text('\$4,200'), findsOneWidget);
    expect(
      find.textContaining('not necessarily total business costs'),
      findsOneWidget,
    );
    expect(find.text('Estimated Profit'), findsNothing);
    expect(find.text('Recorded revenue'), findsNothing);
  });

  testWidgets('reviewed invoices show purchases, not paid expenses', (
    tester,
  ) async {
    await tester.pumpWidget(
      dashboardApp(dashboard: (_) async => adaptiveDashboard(invoices: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reviewed invoice purchases'), findsOneWidget);
    expect(find.text('\$3,600'), findsOneWidget);
    expect(find.text('Purchases are not confirmed payments.'), findsOneWidget);
    expect(find.text('Estimated Profit'), findsNothing);
  });

  testWidgets('bank and invoice values stay visibly separate', (tester) async {
    await tester.pumpWidget(
      dashboardApp(
        dashboard: (_) async => adaptiveDashboard(bank: true, invoices: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tracked bank outflows'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(find.text('Reviewed invoice purchases'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('not added together'),
      250,
    );
    expect(find.textContaining('not added together'), findsOneWidget);
    expect(find.text('Estimated Profit'), findsNothing);
  });

  testWidgets(
    'POS/revenue only shows revenue and explains unavailable profit',
    (tester) async {
      await tester.pumpWidget(
        dashboardApp(
          dashboard: (_) async => adaptiveDashboard(revenue: true, pos: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recorded revenue'), findsOneWidget);
      expect(find.text('\$12,000'), findsOneWidget);
      expect(find.text('Profit unavailable'), findsOneWidget);
      expect(find.text('Estimated Profit'), findsNothing);
    },
  );

  testWidgets('complete sources permit estimated profitability', (
    tester,
  ) async {
    await tester.pumpWidget(
      dashboardApp(
        dashboard: (_) async => adaptiveDashboard(
          bank: true,
          invoices: true,
          revenue: true,
          pos: true,
          expenses: true,
          profitability: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Estimated Profit'), findsOneWidget);
    expect(find.byKey(const Key('revenue-card')), findsOneWidget);
    expect(find.byKey(const Key('expenses-card')), findsOneWidget);
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

  testWidgets(
    'delayed bank import is nonblocking and refreshes dashboard on completion',
    (tester) async {
      final statuses = StreamController<BankSyncStatus>();
      addTearDown(statuses.close);
      var dashboardLoads = 0;
      var transactionLoads = 0;
      await tester.pumpWidget(
        dashboardApp(
          dashboard: (_) async {
            dashboardLoads++;
            return currentDashboard;
          },
          bankSync: (_) => statuses.stream,
          bankTransactions: (_) async {
            transactionLoads++;
            return const [];
          },
        ),
      );
      statuses.add(
        const BankSyncStatus(
          state: BankImportState.importing,
          connectionCount: 1,
          transactionCount: 0,
          canRetry: false,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('Importing bank transactions'),
        findsOneWidget,
      );
      expect(find.text('Estimated Profit'), findsOneWidget);

      statuses.add(
        const BankSyncStatus(
          state: BankImportState.complete,
          connectionCount: 1,
          transactionCount: 8,
          canRetry: false,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(dashboardLoads, 2);
      expect(transactionLoads, 2);
      expect(find.byKey(const Key('bank-sync-banner')), findsOneWidget);
      expect(
        find.textContaining('bank transactions are ready'),
        findsOneWidget,
      );
      expect(find.textContaining('We found 8'), findsOneWidget);
    },
  );

  testWidgets('failed bank import shows an actionable error', (tester) async {
    await tester.pumpWidget(
      dashboardApp(
        bankSync: (_) => Stream.value(
          const BankSyncStatus(
            state: BankImportState.failed,
            connectionCount: 1,
            transactionCount: 0,
            canRetry: true,
            message: 'Reconnect your bank to continue syncing.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Reconnect your bank to continue syncing.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Manage'), findsOneWidget);
  });

  testWidgets(
    'completed empty bank history is distinct from an unfinished import',
    (tester) async {
      await tester.pumpWidget(
        dashboardApp(
          bankSync: (_) => Stream.value(
            const BankSyncStatus(
              state: BankImportState.complete,
              connectionCount: 1,
              transactionCount: 0,
              canRetry: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('sync is complete'), findsOneWidget);
      expect(find.textContaining('No transactions were found'), findsOneWidget);
      expect(find.textContaining('Importing bank transactions'), findsNothing);
    },
  );

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
