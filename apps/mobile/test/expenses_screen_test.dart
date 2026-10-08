import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/expenses/expenses_screen.dart';
import 'package:restaurant_profit_mobile/features/expenses/foundation.dart';

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
const testLookups = ExpenseLookups(
  [
    ExpenseCategoryOption(id: 'food', name: 'Food'),
    ExpenseCategoryOption(id: 'labor', name: 'Labor'),
  ],
  [
    ExpenseVendorOption(id: 'sysco', name: 'Sysco'),
    ExpenseVendorOption(id: 'adp', name: 'ADP'),
  ],
);
final testActiveLocationProvider = StateProvider<RestaurantLocation>(
  (_) => downtown,
);

ExpenseRecord expense({
  required String id,
  String categoryId = 'food',
  String? vendorId = 'sysco',
  double amount = 1250,
  String? description = 'Weekly food delivery',
  String? notes,
}) => ExpenseRecord(
  id: id,
  restaurantLocationId: 'downtown',
  expenseCategoryId: categoryId,
  vendorId: vendorId,
  date: DateTime.utc(2026, 10, 7, 12),
  amount: amount,
  description: description,
  notes: notes,
  source: 'MANUAL',
);

ExpensePage page(
  List<ExpenseRecord> items, {
  int pageNumber = 1,
  int totalItems = 1,
  bool hasMore = false,
  double totalAmount = 1250,
}) => ExpensePage(
  items: items,
  pagination: ExpensePagination(
    page: pageNumber,
    limit: 25,
    totalItems: totalItems,
    totalPages: hasMore ? pageNumber + 1 : pageNumber,
    hasMore: hasMore,
  ),
  totalAmount: totalAmount,
);

class ExpenseRequest {
  const ExpenseRequest({
    required this.locationId,
    required this.dateRange,
    required this.filters,
    required this.page,
  });
  final String locationId;
  final DateRangeState dateRange;
  final ExpenseFilters filters;
  final int page;
}

class FakeExpenseRepository extends ExpenseRepository {
  FakeExpenseRepository({
    required this.onList,
    this.lookupData = testLookups,
    ExpenseRecord? detailData,
  }) : detailData = detailData ?? expense(id: 'one', notes: 'Paid in full'),
       super(Dio());

  final Future<ExpensePage> Function(ExpenseRequest request) onList;
  final ExpenseLookups lookupData;
  final ExpenseRecord detailData;
  final List<ExpenseRequest> requests = [];

  @override
  Future<ExpensePage> list({
    required String restaurantLocationId,
    required DateRangeState dateRange,
    required ExpenseFilters filters,
    required int page,
    int limit = 25,
  }) {
    final request = ExpenseRequest(
      locationId: restaurantLocationId,
      dateRange: dateRange,
      filters: filters,
      page: page,
    );
    requests.add(request);
    return onList(request);
  }

  @override
  Future<ExpenseLookups> lookups(String organizationId) async => lookupData;

  @override
  Future<ExpenseRecord> detail(String id) async => detailData;
}

void main() {
  Widget app(FakeExpenseRepository repository) => ProviderScope(
    overrides: [
      activeLocationProvider.overrideWithValue(downtown),
      availableLocationsProvider.overrideWithValue([downtown, lakeside]),
      expenseRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(home: Scaffold(body: ExpensesScreen())),
  );

  testWidgets('shows useful initial loading state', (tester) async {
    final pending = Completer<ExpensePage>();
    final repository = FakeExpenseRepository(onList: (_) => pending.future);
    await tester.pumpWidget(app(repository));
    await tester.pump();

    expect(find.text('Loading expenses...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(page([expense(id: 'one')]));
    await tester.pumpAndSettle();
  });

  testWidgets('renders authoritative total and expense list fields', (
    tester,
  ) async {
    final repository = FakeExpenseRepository(
      onList: (_) async => page(
        [
          expense(id: 'one'),
          expense(id: 'two', categoryId: 'labor', vendorId: 'adp', amount: 900),
        ],
        totalItems: 2,
        totalAmount: 2150,
      ),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Total Expenses'), findsOneWidget);
    expect(find.text('\$2,150'), findsOneWidget);
    expect(find.text('2 expenses'), findsOneWidget);
    expect(find.text('Sysco'), findsOneWidget);
    expect(find.text('Weekly food delivery'), findsNWidgets(2));
    expect(find.textContaining('Food • Oct 7, 2026'), findsOneWidget);
    expect(find.text('\$1,250'), findsOneWidget);
    expect(find.text('ADP'), findsOneWidget);
  });

  testWidgets('shows unfiltered empty state', (tester) async {
    final repository = FakeExpenseRepository(
      onList: (_) async => page([], totalItems: 0, totalAmount: 0),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    expect(find.text('No expenses found for this period.'), findsOneWidget);
  });

  testWidgets('shows error and retry state', (tester) async {
    final repository = FakeExpenseRepository(
      onList: (_) => Future<ExpensePage>.error('network failure'),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load expenses'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('debounces search and shows filtered empty message', (
    tester,
  ) async {
    final repository = FakeExpenseRepository(
      onList: (_) async => page([], totalItems: 0, totalAmount: 0),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(1));

    await tester.enterText(find.byKey(const Key('expense-search')), 'sysco');
    await tester.pump(const Duration(milliseconds: 399));
    expect(repository.requests, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(repository.requests.last.filters.search, 'sysco');
    expect(find.text('No expenses match your filters.'), findsOneWidget);
  });

  testWidgets('category filter refreshes expenses', (tester) async {
    final repository = FakeExpenseRepository(
      onList: (_) async => page([expense(id: 'one')]),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('category-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food').last);
    await tester.pumpAndSettle();

    expect(repository.requests.last.filters.categoryId, 'food');
  });

  testWidgets('vendor filter refreshes expenses', (tester) async {
    final repository = FakeExpenseRepository(
      onList: (_) async => page([expense(id: 'one')]),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vendor-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ADP').last);
    await tester.pumpAndSettle();

    expect(repository.requests.last.filters.vendorId, 'adp');
  });

  testWidgets('sort selection uses backend sort state', (tester) async {
    final repository = FakeExpenseRepository(
      onList: (_) async => page([expense(id: 'one')]),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('expense-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highest Amount').last);
    await tester.pumpAndSettle();

    expect(repository.requests.last.filters.sort, ExpenseSort.highestAmount);
  });

  testWidgets('location and date changes automatically refresh expenses', (
    tester,
  ) async {
    final repository = FakeExpenseRepository(
      onList: (_) async => page([expense(id: 'one')]),
    );
    final container = ProviderContainer(
      overrides: [
        activeLocationProvider.overrideWith(
          (ref) => ref.watch(testActiveLocationProvider),
        ),
        availableLocationsProvider.overrideWithValue([downtown, lakeside]),
        expenseRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ExpensesScreen())),
      ),
    );
    await tester.pumpAndSettle();

    container.read(testActiveLocationProvider.notifier).state = lakeside;
    await tester.pumpAndSettle();
    expect(repository.requests.last.locationId, 'lakeside');

    final lastMonth = DateRangeState.resolve(
      DatePreset.lastMonth,
      now: DateTime(2026, 10, 8),
    );
    container.read(dateRangeProvider.notifier).state = lastMonth;
    await tester.pumpAndSettle();
    expect(repository.requests.last.dateRange.startDate, lastMonth.startDate);
    expect(repository.requests.last.dateRange.endDate, lastMonth.endDate);
  });

  testWidgets('load more appends unique rows without duplicates', (
    tester,
  ) async {
    final repository = FakeExpenseRepository(
      onList: (request) async => request.page == 1
          ? page(
              [expense(id: 'one')],
              totalItems: 2,
              hasMore: true,
              totalAmount: 2000,
            )
          : page(
              [expense(id: 'one'), expense(id: 'two', amount: 750)],
              pageNumber: 2,
              totalItems: 2,
              totalAmount: 2000,
            ),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(repository.requests.map((request) => request.page), [1, 2]);
    expect(find.byKey(const Key('expense-one')), findsOneWidget);
    expect(find.byKey(const Key('expense-two')), findsOneWidget);
  });

  testWidgets('tapping a row renders expense details', (tester) async {
    final detail = expense(id: 'one', notes: 'Paid in full');
    final repository = FakeExpenseRepository(
      onList: (_) async => page([detail]),
      detailData: detail,
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('expense-one')));
    await tester.pumpAndSettle();

    expect(find.text('Expense Details'), findsOneWidget);
    expect(find.text('Vendor'), findsOneWidget);
    expect(find.text('Sysco'), findsWidgets);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Paid in full'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
  });
}
