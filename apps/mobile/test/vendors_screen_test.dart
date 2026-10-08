import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/vendors/foundation.dart';
import 'package:restaurant_profit_mobile/features/vendors/vendors_screen.dart';

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
final mutableLocation = StateProvider<RestaurantLocation>((_) => downtown);
VendorSummary vendor(
  String id, {
  String name = 'Sysco',
  double spend = 12840,
  double previous = 11185.2,
  int count = 18,
}) => VendorSummary(
  id: id,
  name: name,
  currentSpend: spend,
  previousSpend: previous,
  percentageChange: previous == 0
      ? null
      : ((spend - previous) / previous) * 100,
  transactionCount: count,
  lastPurchaseDate: DateTime.utc(2026, 10, 6),
);
VendorPage page(
  List<VendorSummary> items, {
  int number = 1,
  int total = 1,
  bool more = false,
}) => VendorPage(items, VendorPagination(number, total, more));

class Request {
  Request(this.location, this.range, this.filters, this.page);
  final String location;
  final DateRangeState range;
  final VendorFilters filters;
  final int page;
}

class FakeVendorRepository extends VendorRepository {
  FakeVendorRepository(this.onList, {VendorDetail? detail})
    : detailData =
          detail ??
          VendorDetail(
            vendor: vendor('sysco'),
            averageTransaction: 713.33,
            trend: [VendorTrendPoint(DateTime.utc(2026, 10, 6), 1200)],
            recentExpenses: [
              VendorExpense(
                'expense',
                DateTime.utc(2026, 10, 6),
                'Food delivery',
                'Food',
                1200,
              ),
            ],
          ),
      super(Dio());
  final Future<VendorPage> Function(Request) onList;
  final VendorDetail detailData;
  final requests = <Request>[];
  @override
  Future<VendorPage> list({
    required String locationId,
    required DateRangeState range,
    required VendorFilters filters,
    required int page,
    int limit = 25,
  }) {
    final request = Request(locationId, range, filters, page);
    requests.add(request);
    return onList(request);
  }

  @override
  Future<VendorDetail> detail(
    String id,
    String locationId,
    DateRangeState range,
  ) async => detailData;
}

void main() {
  Widget app(FakeVendorRepository repository, {ProviderContainer? container}) {
    final child = const MaterialApp(home: Scaffold(body: VendorsScreen()));
    if (container != null) {
      return UncontrolledProviderScope(container: container, child: child);
    }
    return ProviderScope(
      overrides: [
        activeLocationProvider.overrideWithValue(downtown),
        availableLocationsProvider.overrideWithValue([downtown, lakeside]),
        vendorRepositoryProvider.overrideWithValue(repository),
      ],
      child: child,
    );
  }

  Future<void> pump(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(widget);
  }

  testWidgets('loading then success renders authoritative vendor metrics', (
    tester,
  ) async {
    final pending = Completer<VendorPage>(),
        repository = FakeVendorRepository((_) => pending.future);
    await pump(tester, app(repository));
    await tester.pump();
    expect(find.text('Loading vendors...'), findsOneWidget);
    pending.complete(page([vendor('sysco')]));
    await tester.pumpAndSettle();
    expect(find.text('Sysco'), findsOneWidget);
    expect(find.text('\$12,840'), findsOneWidget);
    expect(find.textContaining('14.8% vs previous period'), findsOneWidget);
    expect(find.textContaining('18 transactions'), findsOneWidget);
    expect(find.textContaining('Last purchase: Oct 6'), findsOneWidget);
  });
  testWidgets('empty, search-empty, and error states render', (tester) async {
    final repository = FakeVendorRepository((_) async => page([], total: 0));
    await pump(tester, app(repository));
    await tester.pumpAndSettle();
    expect(
      find.text('No vendor activity found for this period.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('vendor-search')), 'none');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('No vendors match your search.'), findsOneWidget);
    await pump(
      tester,
      app(FakeVendorRepository((_) => Future.error('offline'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load vendors'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
  testWidgets('debounced search and sorting refresh server query', (
    tester,
  ) async {
    final repository = FakeVendorRepository(
      (_) async => page([vendor('sysco')]),
    );
    await pump(tester, app(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vendor-search')), 'sys');
    await tester.pump(const Duration(milliseconds: 399));
    expect(repository.requests, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(repository.requests.last.filters.search, 'sys');
    await tester.tap(find.byKey(const Key('vendor-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Most Transactions').last);
    await tester.pumpAndSettle();
    expect(repository.requests.last.filters.sort, VendorSort.mostTransactions);
  });
  testWidgets('location and date changes refresh vendor summaries', (
    tester,
  ) async {
    final repository = FakeVendorRepository(
      (_) async => page([vendor('sysco')]),
    );
    final container = ProviderContainer(
      overrides: [
        activeLocationProvider.overrideWith(
          (ref) => ref.watch(mutableLocation),
        ),
        availableLocationsProvider.overrideWithValue([downtown, lakeside]),
        vendorRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await pump(tester, app(repository, container: container));
    await tester.pumpAndSettle();
    container.read(mutableLocation.notifier).state = lakeside;
    await tester.pumpAndSettle();
    expect(repository.requests.last.location, 'lakeside');
    final range = DateRangeState.resolve(
      DatePreset.last30Days,
      now: DateTime(2026, 10, 8),
    );
    container.read(dateRangeProvider.notifier).state = range;
    await tester.pumpAndSettle();
    expect(repository.requests.last.range.startDate, range.startDate);
  });
  testWidgets('pagination appends unique vendors', (tester) async {
    final repository = FakeVendorRepository(
      (request) async => request.page == 1
          ? page([vendor('one')], total: 2, more: true)
          : page(
              [vendor('one'), vendor('two', name: 'ADP')],
              number: 2,
              total: 2,
            ),
    );
    await pump(tester, app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vendor-one')), findsOneWidget);
    expect(find.byKey(const Key('vendor-two')), findsOneWidget);
  });
  testWidgets('vendor detail renders metrics, trend, and recent expenses', (
    tester,
  ) async {
    final repository = FakeVendorRepository(
      (_) async => page([vendor('sysco')]),
    );
    await pump(tester, app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vendor-sysco')));
    await tester.pumpAndSettle();
    expect(find.text('Current Spend'), findsOneWidget);
    expect(find.text('Previous Spend'), findsOneWidget);
    expect(find.text('Average Transaction'), findsOneWidget);
    expect(find.text('\$713'), findsOneWidget);
    expect(find.text('Spend Trend'), findsOneWidget);
    expect(find.byKey(const Key('revenue-chart')), findsOneWidget);
    expect(find.text('Recent Expenses'), findsOneWidget);
    expect(find.text('Food delivery'), findsOneWidget);
    expect(find.textContaining('Food • Oct 6'), findsOneWidget);
  });
}
