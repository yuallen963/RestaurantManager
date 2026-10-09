import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/revenue/foundation.dart';
import 'package:restaurant_profit_mobile/features/revenue/revenue_screen.dart';

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

RevenueRecord record(
  String id, {
  double amount = 4218,
  String? notes = 'Daily sales',
}) => RevenueRecord(
  id: id,
  date: DateTime.utc(2026, 10, 7, 12),
  amount: amount,
  source: 'POS_IMPORT',
  notes: notes,
);
RevenuePage page(
  List<RevenueRecord> items, {
  int pageNumber = 1,
  int totalItems = 1,
  bool hasMore = false,
}) => RevenuePage(
  items: items,
  pagination: RevenuePagination(
    page: pageNumber,
    totalItems: totalItems,
    hasMore: hasMore,
  ),
  summary: RevenueSummary(
    total: 89726,
    previousTotal: 80000,
    averageDaily: 2990.87,
    highestDay: DailyRevenue(DateTime.utc(2026, 10, 7), 5120.44),
    lowestDay: DailyRevenue(DateTime.utc(2026, 10, 2), 1810.22),
    dailyTrend: [
      DailyRevenue(DateTime.utc(2026, 10, 1), 2000),
      DailyRevenue(DateTime.utc(2026, 10, 7), 5120.44),
    ],
  ),
);

class Request {
  Request(this.location, this.range, this.sort, this.page);
  final String location;
  final DateRangeState range;
  final RevenueSort sort;
  final int page;
}

class FakeRevenueRepository extends RevenueRepository {
  FakeRevenueRepository(this.onList, {RevenueRecord? detail})
    : detailRecord = detail ?? record('one'),
      super(Dio());
  final Future<RevenuePage> Function(Request) onList;
  final RevenueRecord detailRecord;
  final requests = <Request>[];
  @override
  Future<RevenuePage> list({
    required String locationId,
    required DateRangeState dateRange,
    required RevenueSort sort,
    required int page,
    int limit = 25,
  }) {
    final request = Request(locationId, dateRange, sort, page);
    requests.add(request);
    return onList(request);
  }

  @override
  Future<RevenueRecord> detail(String id) async => detailRecord;
}

void main() {
  Widget app(FakeRevenueRepository repository) => ProviderScope(
    overrides: [
      activeLocationProvider.overrideWithValue(downtown),
      availableLocationsProvider.overrideWithValue([downtown, lakeside]),
      revenueRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(home: Scaffold(body: RevenueScreen())),
  );

  Future<void> pumpApp(
    WidgetTester tester,
    FakeRevenueRepository repository,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(repository));
  }

  testWidgets('shows loading then revenue summary, chart, and daily row', (
    tester,
  ) async {
    final pending = Completer<RevenuePage>();
    final repository = FakeRevenueRepository((_) => pending.future);
    await pumpApp(tester, repository);
    await tester.pump();
    expect(find.text('Loading revenue...'), findsOneWidget);
    pending.complete(page([record('one')]));
    await tester.pumpAndSettle();
    expect(find.text('Total Revenue'), findsOneWidget);
    expect(find.text('\$89,726'), findsOneWidget);
    expect(find.textContaining('12.2% increase'), findsOneWidget);
    expect(find.text('Average Daily Revenue'), findsOneWidget);
    expect(find.text('\$2,991'), findsOneWidget);
    expect(find.text('Strongest Sales Day'), findsOneWidget);
    expect(find.text('Weakest Sales Day'), findsOneWidget);
    expect(find.byKey(const Key('revenue-chart')), findsOneWidget);
    expect(find.text('Daily sales'), findsOneWidget);
  });

  testWidgets('shows empty and error states', (tester) async {
    await pumpApp(
      tester,
      FakeRevenueRepository((_) async => page([], totalItems: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No revenue found for this period.'), findsOneWidget);
    await pumpApp(
      tester,
      FakeRevenueRepository((_) => Future.error('offline')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load revenue'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('sort selection refreshes with server sort', (tester) async {
    final repository = FakeRevenueRepository(
      (_) async => page([record('one')]),
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('revenue-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highest Revenue').last);
    await tester.pumpAndSettle();
    expect(repository.requests.last.sort, RevenueSort.highestRevenue);
  });

  testWidgets('location and date-range changes refresh all revenue data', (
    tester,
  ) async {
    final repository = FakeRevenueRepository(
      (_) async => page([record('one')]),
    );
    final container = ProviderContainer(
      overrides: [
        activeLocationProvider.overrideWith(
          (ref) => ref.watch(mutableLocationProvider),
        ),
        availableLocationsProvider.overrideWithValue([downtown, lakeside]),
        revenueRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: RevenueScreen())),
      ),
    );
    await tester.pumpAndSettle();
    container.read(mutableLocationProvider.notifier).state = lakeside;
    await tester.pumpAndSettle();
    expect(repository.requests.last.location, 'lakeside');
    final range = DateRangeState.resolve(
      DatePreset.lastMonth,
      now: DateTime(2026, 10, 8),
    );
    container.read(dateRangeProvider.notifier).state = range;
    await tester.pumpAndSettle();
    expect(repository.requests.last.range.startDate, range.startDate);
  });

  testWidgets('load more appends unique records', (tester) async {
    final repository = FakeRevenueRepository(
      (request) async => request.page == 1
          ? page([record('one')], totalItems: 2, hasMore: true)
          : page(
              [record('one'), record('two', amount: 3000)],
              pageNumber: 2,
              totalItems: 2,
            ),
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(repository.requests.map((request) => request.page), [1, 2]);
    expect(find.byKey(const Key('revenue-one')), findsOneWidget);
    expect(find.byKey(const Key('revenue-two')), findsOneWidget);
  });

  testWidgets('opens revenue detail with available fields', (tester) async {
    final detail = record('one', notes: 'Dinner service');
    await pumpApp(
      tester,
      FakeRevenueRepository((_) async => page([detail]), detail: detail),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('revenue-one')));
    await tester.pumpAndSettle();
    expect(find.text('Revenue Details'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Square'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Dinner service'), findsWidgets);
  });
}
