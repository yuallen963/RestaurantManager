import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
import 'package:restaurant_profit_mobile/features/banking/foundation.dart';
import 'package:restaurant_profit_mobile/features/revenue/foundation.dart';
import 'package:restaurant_profit_mobile/features/revenue/revenue_screen.dart';
import 'package:restaurant_profit_mobile/main.dart' show demoModeProvider;

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
  String source = 'POS_IMPORT',
  ManualRevenueType? manualType,
  bool additionalToPos = false,
}) => RevenueRecord(
  id: id,
  date: DateTime.utc(2026, 10, 7, 12),
  amount: amount,
  source: source,
  restaurantLocationId: downtown.id,
  manualType: manualType,
  additionalToPos: additionalToPos,
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
  FakeRevenueRepository(
    this.onList, {
    RevenueRecord? detail,
    this.onCreate,
    this.onUpdate,
    this.onDelete,
  }) : detailRecord = detail ?? record('one'),
       super(Dio());
  final Future<RevenuePage> Function(Request) onList;
  final RevenueRecord detailRecord;
  final Future<RevenueRecord> Function(RevenueMutation)? onCreate;
  final Future<RevenueRecord> Function(String, RevenueMutation)? onUpdate;
  final Future<void> Function(String)? onDelete;
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

  @override
  Future<RevenueRecord> create(RevenueMutation mutation) => onCreate!(mutation);

  @override
  Future<RevenueRecord> update(String id, RevenueMutation mutation) =>
      onUpdate!(id, mutation);

  @override
  Future<void> delete(String id) => onDelete!(id);
}

void main() {
  Widget app(
    FakeRevenueRepository repository, {
    List<BankTransactionData> deposits = const [],
    bool demo = false,
  }) => ProviderScope(
    overrides: [
      demoModeProvider.overrideWithValue(demo),
      activeLocationProvider.overrideWithValue(downtown),
      availableLocationsProvider.overrideWithValue([downtown, lakeside]),
      revenueRepositoryProvider.overrideWithValue(repository),
      unverifiedBankDepositsProvider.overrideWith((_) async => deposits),
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

  testWidgets('bank deposits remain visibly unverified revenue', (
    tester,
  ) async {
    final deposit = BankTransactionData(
      id: 'deposit',
      merchant: 'Incoming transfer',
      description: 'ACH CREDIT',
      amount: -500,
      postedDate: DateTime(2026, 10, 7),
      status: 'NEEDS_REVIEW',
      categorizationSource: 'UNRESOLVED',
      matchConfidence: 'NO_MATCH',
      pending: false,
      restaurantLocationId: downtown.id,
    );
    await tester.pumpWidget(
      app(
        FakeRevenueRepository((_) async => page([], totalItems: 0)),
        deposits: [deposit],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bank Deposits Needing Review'), findsOneWidget);
    expect(
      find.textContaining('not counted as restaurant sales'),
      findsOneWidget,
    );
    expect(find.text('Total Revenue'), findsOneWidget);
    expect(find.text('\$0'), findsNothing);
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
    expect(find.text('Square'), findsWidgets);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Dinner service'), findsWidgets);
    expect(find.byKey(const Key('edit-revenue')), findsNothing);
    expect(find.byKey(const Key('delete-revenue')), findsNothing);
  });

  testWidgets('creates manual revenue with owner-friendly sales fields', (
    tester,
  ) async {
    RevenueMutation? submitted;
    final manual = record(
      'manual',
      amount: 125.25,
      source: 'MANUAL',
      manualType: ManualRevenueType.cash,
      notes: 'Lunch sales',
    );
    final repository = FakeRevenueRepository(
      (_) async => page([], totalItems: 0),
      onCreate: (mutation) async {
        submitted = mutation;
        return manual;
      },
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-revenue')));
    await tester.pumpAndSettle();
    expect(
      find.text('Restaurant sales excluding sales tax and tips.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('revenue-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash Sales').last);
    await tester.enterText(find.byKey(const Key('revenue-amount')), '125.25');
    await tester.enterText(
      find.byKey(const Key('revenue-notes')),
      'Lunch sales',
    );
    await tester.tap(find.byKey(const Key('save-revenue')));
    await tester.pumpAndSettle();
    expect(submitted?.restaurantLocationId, downtown.id);
    expect(submitted?.manualType, ManualRevenueType.cash);
    expect(submitted?.amount, 125.25);
    expect(submitted?.notes, 'Lunch sales');
    expect(find.text('Revenue recorded'), findsOneWidget);
  });

  testWidgets('rejects invalid manual revenue amounts', (tester) async {
    var createCalls = 0;
    final repository = FakeRevenueRepository(
      (_) async => page([], totalItems: 0),
      onCreate: (mutation) async {
        createCalls++;
        return record('manual');
      },
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-revenue')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('revenue-amount')), '0');
    await tester.tap(find.byKey(const Key('save-revenue')));
    await tester.pump();
    expect(find.text('Enter a positive sales amount'), findsOneWidget);
    expect(createCalls, 0);
  });

  testWidgets('manual revenue can be edited and removed after confirmation', (
    tester,
  ) async {
    final manual = record(
      'manual',
      source: 'MANUAL',
      manualType: ManualRevenueType.online,
    );
    String? deletedId;
    final repository = FakeRevenueRepository(
      (_) async => page([manual]),
      detail: manual,
      onUpdate: (_, mutation) async => manual,
      onDelete: (id) async => deletedId = id,
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('revenue-manual')));
    await tester.pumpAndSettle();
    expect(find.text('Online Sales'), findsWidgets);
    expect(find.byKey(const Key('edit-revenue')), findsOneWidget);
    expect(find.byKey(const Key('delete-revenue')), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-revenue')));
    await tester.pumpAndSettle();
    expect(find.textContaining('audit record'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-revenue')));
    await tester.pumpAndSettle();
    expect(deletedId, 'manual');
    expect(find.text('Revenue entry removed'), findsOneWidget);
  });

  testWidgets('edits a manual revenue entry through the detail sheet', (
    tester,
  ) async {
    final manual = record(
      'manual',
      amount: 80,
      source: 'MANUAL',
      manualType: ManualRevenueType.card,
    );
    RevenueMutation? updated;
    final repository = FakeRevenueRepository(
      (_) async => page([manual]),
      detail: manual,
      onUpdate: (id, mutation) async {
        expect(id, 'manual');
        updated = mutation;
        return record(
          id,
          amount: mutation.amount,
          source: 'MANUAL',
          manualType: mutation.manualType,
          notes: mutation.notes,
        );
      },
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('revenue-manual')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-revenue')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('revenue-amount')), '90.50');
    await tester.tap(find.byKey(const Key('save-revenue')));
    await tester.pumpAndSettle();
    expect(updated?.amount, 90.5);
    expect(updated?.manualType, ManualRevenueType.card);
    expect(find.text('Revenue updated'), findsOneWidget);
  });

  testWidgets('Square overlap requires explicit additional-sales confirmation', (
    tester,
  ) async {
    final attempts = <RevenueMutation>[];
    final manual = record(
      'manual',
      source: 'MANUAL',
      manualType: ManualRevenueType.other,
    );
    final repository = FakeRevenueRepository(
      (_) async => page([], totalItems: 0),
      onCreate: (mutation) async {
        attempts.add(mutation);
        if (!mutation.additionalToPos) {
          throw const RevenueConflictException(
            'Square revenue already exists for this date. Only continue if these are additional sales not included in Square.',
            canAddToSquare: true,
          );
        }
        return manual;
      },
    );
    await pumpApp(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-revenue')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('revenue-amount')), '50');
    await tester.tap(find.byKey(const Key('save-revenue')));
    await tester.pumpAndSettle();
    expect(find.text('Square sales already recorded'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('confirm-square-additional-revenue')),
    );
    await tester.pumpAndSettle();
    expect(attempts, hasLength(2));
    expect(attempts.last.additionalToPos, isTrue);
  });

  testWidgets('public demo explains read-only mode and hides write actions', (
    tester,
  ) async {
    final manual = record(
      'manual',
      source: 'MANUAL',
      manualType: ManualRevenueType.cash,
    );
    await tester.pumpWidget(
      app(
        FakeRevenueRepository((_) async => page([manual]), detail: manual),
        demo: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Public demo is view only'), findsOneWidget);
    expect(find.byKey(const Key('add-revenue')), findsNothing);
    await tester.drag(
      find.byKey(const Key('revenue-list')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('revenue-manual')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-revenue')), findsNothing);
    expect(find.byKey(const Key('delete-revenue')), findsNothing);
  });

  testWidgets('revenue workspace renders without overflow at target widths', (
    tester,
  ) async {
    final repository = FakeRevenueRepository(
      (_) async => page([record('one')]),
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final width in [1440.0, 1280.0, 768.0, 390.0]) {
      tester.view.physicalSize = Size(width, 1200);
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });
}
