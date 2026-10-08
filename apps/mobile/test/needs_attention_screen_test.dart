import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/expenses/foundation.dart';
import 'package:restaurant_profit_mobile/features/needs_attention/foundation.dart';
import 'package:restaurant_profit_mobile/features/needs_attention/needs_attention_screen.dart';
import 'package:restaurant_profit_mobile/features/price_intelligence/foundation.dart';
import 'package:restaurant_profit_mobile/features/vendors/foundation.dart';

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

AttentionItem issue({
  String id = 'price:item-key',
  String type = 'REPEATED_ITEM_PRICE_INCREASE',
  AttentionSeverity severity = AttentionSeverity.high,
  String title = 'Chicken Breast keeps increasing',
  String? subtitle = 'Sysco',
  double? percentage = 8.7,
  double? points,
  double? impact = 102,
  AttentionActionType action = AttentionActionType.openPriceHistory,
  String target = 'item-key',
}) => AttentionItem(
  id: id,
  type: type,
  severity: severity,
  title: title,
  subtitle: subtitle,
  currentValue: 106.5,
  previousValue: 98,
  percentageChange: percentage,
  percentagePointChange: points,
  estimatedMonthlyImpact: impact,
  message: type == 'REPEATED_ITEM_PRICE_INCREASE'
      ? 'Chicken Breast increased on 2 consecutive purchases.'
      : '$title compared with the previous period.',
  occurredAt: DateTime.utc(2026, 10, 3),
  action: AttentionAction(type: action, targetId: target),
);

final vendorIssue = issue(
  id: 'vendor:vendor-a',
  type: 'VENDOR_SPEND_INCREASE',
  severity: AttentionSeverity.critical,
  title: 'Sysco spend increased',
  impact: 7125,
  action: AttentionActionType.openVendor,
  target: 'vendor-a',
);
final categoryIssue = issue(
  id: 'category:food',
  type: 'CATEGORY_SPEND_INCREASE',
  title: 'Food spending increased',
  subtitle: 'Food',
  impact: 1500,
  action: AttentionActionType.openExpenseCategory,
  target: 'food',
);
final laborIssue = issue(
  id: 'labor:period',
  type: 'LABOR_COST_DETERIORATION',
  title: 'Labor cost increased',
  percentage: null,
  points: 5,
  impact: null,
  action: AttentionActionType.openDashboardCost,
  target: 'labor',
);
final attentionData = NeedsAttentionData(
  summary: const AttentionSummary(
    critical: 1,
    high: 3,
    medium: 0,
    low: 0,
    estimatedMonthlyImpact: 102,
  ),
  items: [vendorIssue, categoryIssue, issue(), laborIssue],
);
const emptyAttention = NeedsAttentionData(
  summary: AttentionSummary(
    critical: 0,
    high: 0,
    medium: 0,
    low: 0,
    estimatedMonthlyImpact: 0,
  ),
  items: [],
);

class FakeNeedsRepository extends NeedsAttentionRepository {
  FakeNeedsRepository(this.loader) : super(Dio());
  final Future<NeedsAttentionData> Function(String locationId) loader;
  final calls = <String>[];

  @override
  Future<NeedsAttentionData> get(String locationId, DateRangeState range) {
    calls.add(locationId);
    return loader(locationId);
  }
}

class EmptyExpenseController extends ExpenseListController {
  @override
  Future<ExpenseListState> build() async => const ExpenseListState(
    items: [],
    pagination: ExpensePagination(
      page: 1,
      limit: 25,
      totalItems: 0,
      totalPages: 0,
      hasMore: false,
    ),
    totalAmount: 0,
  );
}

PriceHistoryData historyData() => PriceHistoryData(
  item: PriceChangeItem(
    vendorId: 'vendor-a',
    vendorName: 'Sysco',
    itemKey: 'item-key',
    displayName: 'Chicken Breast',
    sku: '384920',
    unit: 'CASE',
    packSize: '4 x 10 lb',
    previousUnitPrice: 98,
    currentUnitPrice: 106.5,
    absoluteChange: 8.5,
    percentageChange: 8.67,
    typicalMonthlyQuantity: 12,
    estimatedMonthlyImpact: 102,
    estimatedAnnualImpact: 1224,
    firstSeenAt: DateTime.utc(2026, 8, 1),
    latestSeenAt: DateTime.utc(2026, 10, 3),
  ),
  history: [
    PriceHistoryPoint(
      date: DateTime.utc(2026, 8, 1),
      invoiceId: 'invoice-one',
      unitPrice: 91,
      quantity: 12,
    ),
    PriceHistoryPoint(
      date: DateTime.utc(2026, 10, 3),
      invoiceId: 'invoice-two',
      unitPrice: 106.5,
      quantity: 12,
    ),
  ],
);

VendorDetail vendorDetail() => VendorDetail(
  vendor: VendorSummary(
    id: 'vendor-a',
    name: 'Sysco',
    currentSpend: 10100,
    previousSpend: 8200,
    percentageChange: 23.2,
    transactionCount: 8,
    lastPurchaseDate: DateTime.utc(2026, 10, 8),
  ),
  averageTransaction: 1262.5,
  trend: const [],
  recentExpenses: const [],
);

void main() {
  Widget app({
    required Widget child,
    NeedsAttentionData? data,
    List<Override> overrides = const [],
  }) => ProviderScope(
    overrides: [
      activeLocationProvider.overrideWithValue(downtown),
      availableLocationsProvider.overrideWithValue([downtown, lakeside]),
      needsAttentionProvider.overrideWith((_) async => data ?? attentionData),
      ...overrides,
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );

  testWidgets(
    'Home preview shows issue count, severity, impact, and View All navigation',
    (tester) async {
      await tester.pumpWidget(app(child: const NeedsAttentionPreview()));
      await tester.pumpAndSettle();
      expect(find.text('4 issues'), findsOneWidget);
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('+\$7,125/mo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('view-all-attention')));
      await tester.pumpAndSettle();
      expect(find.text('Needs Attention'), findsWidgets);
      expect(find.byKey(const Key('needs-attention-list')), findsOneWidget);
    },
  );

  testWidgets(
    'full list renders severity, monthly impact, empty state, and no overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(child: const NeedsAttentionScreen()));
      await tester.pumpAndSettle();
      expect(find.text('4 meaningful issues'), findsOneWidget);
      expect(
        find.text('Known item-price impact: +\$102/month'),
        findsOneWidget,
      );
      expect(find.text('Sysco spend increased'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        app(child: const NeedsAttentionScreen(), data: emptyAttention),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('needs-attention-list')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No major cost issues detected for this period.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('error state retries successfully', (tester) async {
    var attempts = 0;
    final repository = FakeNeedsRepository((_) async {
      attempts += 1;
      if (attempts == 1) throw Exception('network');
      return emptyAttention;
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLocationProvider.overrideWithValue(downtown),
          availableLocationsProvider.overrideWithValue([downtown]),
          needsAttentionRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: NeedsAttentionScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load issues'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('No major cost issues detected for this period.'),
      findsOneWidget,
    );
    expect(attempts, 2);
  });

  testWidgets('active location refreshes the list', (tester) async {
    final repository = FakeNeedsRepository(
      (location) async =>
          location == 'downtown' ? attentionData : emptyAttention,
    );
    final container = ProviderContainer(
      overrides: [
        activeLocationProvider.overrideWith(
          (ref) => ref.watch(mutableLocationProvider),
        ),
        availableLocationsProvider.overrideWithValue([downtown, lakeside]),
        needsAttentionRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NeedsAttentionScreen()),
      ),
    );
    await tester.pumpAndSettle();
    container.read(mutableLocationProvider.notifier).state = lakeside;
    await tester.pumpAndSettle();
    expect(repository.calls, containsAllInOrder(['downtown', 'lakeside']));
    expect(
      find.text('No major cost issues detected for this period.'),
      findsOneWidget,
    );
  });

  testWidgets('price issue opens Price History', (tester) async {
    await tester.pumpWidget(
      app(
        child: const NeedsAttentionScreen(),
        data: NeedsAttentionData(
          summary: const AttentionSummary(
            critical: 0,
            high: 1,
            medium: 0,
            low: 0,
            estimatedMonthlyImpact: 102,
          ),
          items: [issue()],
        ),
        overrides: [
          priceHistoryProvider(
            'item-key',
          ).overrideWith((_) async => historyData()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chicken Breast keeps increasing'));
    await tester.pumpAndSettle();
    expect(find.text('Price History'), findsOneWidget);
    expect(find.text('Chicken Breast'), findsOneWidget);
  });

  testWidgets('vendor issue opens existing vendor detail', (tester) async {
    await tester.pumpWidget(
      app(
        child: const NeedsAttentionScreen(),
        data: NeedsAttentionData(
          summary: const AttentionSummary(
            critical: 1,
            high: 0,
            medium: 0,
            low: 0,
            estimatedMonthlyImpact: 0,
          ),
          items: [vendorIssue],
        ),
        overrides: [
          vendorDetailProvider(
            'vendor-a',
          ).overrideWith((_) async => vendorDetail()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sysco spend increased'));
    await tester.pumpAndSettle();
    expect(find.text('Current Spend'), findsOneWidget);
    expect(find.text('\$10,100'), findsOneWidget);
  });

  testWidgets(
    'category issue opens Expenses with the category filter applied',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          activeLocationProvider.overrideWithValue(downtown),
          availableLocationsProvider.overrideWithValue([downtown]),
          needsAttentionProvider.overrideWith(
            (_) async => NeedsAttentionData(
              summary: const AttentionSummary(
                critical: 0,
                high: 1,
                medium: 0,
                low: 0,
                estimatedMonthlyImpact: 0,
              ),
              items: [categoryIssue],
            ),
          ),
          expenseLookupsProvider.overrideWith(
            (_) async => const ExpenseLookups([
              ExpenseCategoryOption(id: 'food', name: 'Food'),
            ], []),
          ),
          expenseListProvider.overrideWith(EmptyExpenseController.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NeedsAttentionScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food spending increased'));
      await tester.pumpAndSettle();
      expect(container.read(expenseFiltersProvider).categoryId, 'food');
      expect(find.text('Category Expenses'), findsOneWidget);
      expect(find.text('All Categories'), findsNothing);
      expect(find.text('Food'), findsWidgets);
    },
  );
}
