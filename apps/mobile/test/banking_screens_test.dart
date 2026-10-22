import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/banking/bank_screens.dart';
import 'package:restaurant_profit_mobile/features/banking/foundation.dart';
import 'package:restaurant_profit_mobile/features/banking/plaid_link/plaid_link.dart';
import 'package:restaurant_profit_mobile/features/dashboard/foundation.dart';
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
final connection = BankConnectionData(
  id: 'connection',
  institutionName: 'Profit Lens Sandbox Bank',
  status: 'CONNECTED',
  lastSyncAt: DateTime(2026, 10, 8),
  accounts: const [
    BankAccountData(
      id: 'account',
      name: 'Business Checking',
      mask: '4242',
      active: true,
      restaurantLocationId: 'downtown',
      restaurantLocationName: 'Downtown Grill',
    ),
  ],
);
const suggested = SuggestedInvoiceData('invoice', '10492', 1446);
final reviewTransaction = BankTransactionData(
  id: 'transaction',
  merchant: 'Sysco',
  description: 'SYSCO ACH',
  amount: 1446,
  postedDate: DateTime(2026, 10, 8),
  status: 'NEEDS_REVIEW',
  categorizationSource: 'MERCHANT_RULE',
  matchConfidence: 'EXACT',
  pending: false,
  vendorId: 'sysco',
  vendorName: 'Sysco',
  restaurantLocationId: 'downtown',
  suggestedInvoice: suggested,
);
const lookups = ExpenseLookups(
  [ExpenseCategoryOption(id: 'food', name: 'Food')],
  [
    ExpenseVendorOption(id: 'sysco', name: 'Sysco'),
    ExpenseVendorOption(id: 'adp', name: 'ADP'),
  ],
);
final selectedBankLocationProvider = StateProvider<RestaurantLocation>(
  (_) => downtown,
);

class FakeBankingRepository extends BankingRepository {
  FakeBankingRepository() : super(Dio());
  int syncCalls = 0,
      retryCalls = 0,
      exchangeCalls = 0,
      disconnectCalls = 0,
      reauthenticationCalls = 0;
  bool failSync = false;
  bool failConfirm = false;
  String? assignedLocation, confirmedInvoice, reversedTransaction, bulkAnchor;
  Map<String, dynamic>? reviewData;
  List<String>? bulkIds;
  BulkReviewResult bulkResult = const BulkReviewResult(
    requestedCount: 1,
    confirmedCount: 1,
    failedIds: [],
  );
  final transactionStatuses = <String?>[];
  Map<String?, List<BankTransactionData>> transactionsByStatus = const {};
  List<BankTransactionData> similarItems = const [];
  bool demoLink = true;
  bool? requestedWebLink;
  @override
  Future<BankLinkSetup> linkToken(
    String organizationId, {
    bool web = false,
  }) async {
    requestedWebLink = web;
    return BankLinkSetup('link-token', demoLink);
  }

  @override
  Future<void> exchange(
    String organizationId,
    String publicToken,
    String? locationId,
  ) async {
    exchangeCalls++;
  }

  @override
  Future<BankLinkSetup> reauthenticationLinkToken(
    String connectionId, {
    bool web = false,
  }) async {
    requestedWebLink = web;
    return BankLinkSetup('update-link', demoLink, updateMode: true);
  }

  @override
  Future<void> completeReauthentication(String connectionId) async {
    reauthenticationCalls++;
  }

  @override
  Future<void> assignAccount(String id, String? locationId) async {
    assignedLocation = locationId;
  }

  @override
  Future<void> sync(String id) async {
    syncCalls++;
    if (failSync) throw DioException(requestOptions: RequestOptions());
  }

  @override
  Future<void> disconnect(String id) async {
    disconnectCalls++;
  }

  @override
  Future<void> confirmMatch(String id, String invoiceId) async {
    if (failConfirm) throw DioException(requestOptions: RequestOptions());
    confirmedInvoice = invoiceId;
  }

  @override
  Future<void> rejectMatch(String id) async {}
  @override
  Future<void> reverse(String id) async => reversedTransaction = id;
  @override
  Future<List<BankTransactionData>> transactions(
    String organizationId,
    String? locationId,
    String? status,
  ) async {
    transactionStatuses.add(status);
    return transactionsByStatus[status] ?? const [];
  }

  @override
  Future<List<BankTransactionData>> similarTransactions(String id) async =>
      similarItems.isNotEmpty
      ? similarItems
      : transactionsByStatus.values
            .expand((items) => items)
            .where((item) => item.id == id)
            .toList();

  @override
  Future<void> review(
    String id, {
    String? vendorId,
    String? categoryId,
    String? locationId,
    bool ignored = false,
    BankReviewDecision? decision,
    bool createRule = false,
    bool autoConfirmFuture = false,
    double? minimumAmount,
    double? maximumAmount,
  }) async {
    reviewData = {
      'vendorId': vendorId,
      'categoryId': categoryId,
      'locationId': locationId,
      'ignored': ignored,
      'decision': decision,
      'createRule': createRule,
      'autoConfirmFuture': autoConfirmFuture,
    };
  }

  @override
  Future<BulkReviewResult> bulkReview(
    List<String> ids, {
    String? vendorId,
    String? categoryId,
    required String locationId,
    bool ignored = false,
    BankReviewDecision? decision,
    bool createRule = false,
    bool autoConfirmFuture = false,
    double? minimumAmount,
    double? maximumAmount,
    String? groupAnchorId,
  }) async {
    bulkIds = ids;
    bulkAnchor = groupAnchorId;
    return bulkResult;
  }
}

class FakePlaidLinkLauncher implements PlaidLinkLauncher {
  FakePlaidLinkLauncher({this.web = true, this.nextResult, this.oauthResult});

  final bool web;
  PlaidLinkResult? nextResult;
  PlaidLinkResult? oauthResult;
  PlaidLinkRequest? request;

  @override
  bool get isWeb => web;

  @override
  Future<PlaidLinkResult> open(PlaidLinkRequest request) async {
    this.request = request;
    return nextResult ?? PlaidLinkResult.cancelled(request.context);
  }

  @override
  Future<PlaidLinkResult?> resumeOAuth() async => oauthResult;

  @override
  void dispose() {}
}

class DeferredBankingRepository extends BankingRepository {
  DeferredBankingRepository() : super(Dio());
  final requests = <String, Completer<List<BankTransactionData>>>{};

  @override
  Future<List<BankTransactionData>> transactions(
    String organizationId,
    String? locationId,
    String? status,
  ) {
    return (requests[locationId!] ??= Completer<List<BankTransactionData>>())
        .future;
  }
}

Widget accountsApp(
  FakeBankingRepository repository,
  Future<List<BankConnectionData>> Function() load, {
  PlaidLinkLauncher? launcher,
}) => ProviderScope(
  overrides: [
    activeLocationProvider.overrideWithValue(downtown),
    availableLocationsProvider.overrideWithValue(const [downtown, lakeside]),
    bankingRepositoryProvider.overrideWithValue(repository),
    if (launcher != null) plaidLinkLauncherProvider.overrideWithValue(launcher),
    bankConnectionsProvider.overrideWith((_) => load()),
  ],
  child: const MaterialApp(home: BankAccountsScreen()),
);
Widget transactionsApp(
  FakeBankingRepository repository,
  List<BankTransactionData> items,
) => ProviderScope(
  overrides: [
    activeLocationProvider.overrideWithValue(downtown),
    availableLocationsProvider.overrideWithValue(const [downtown, lakeside]),
    bankingRepositoryProvider.overrideWithValue(repository),
    bankTransactionsProvider.overrideWith((_) async => items),
    bankConnectionsProvider.overrideWith((_) async => [connection]),
    bankSyncStatusProvider.overrideWith(
      (_) => Stream.value(
        BankSyncStatus(
          state: BankImportState.complete,
          connectionCount: 1,
          transactionCount: items.length,
          canRetry: false,
        ),
      ),
    ),
    expenseLookupsProvider.overrideWith((_) async => lookups),
  ],
  child: const MaterialApp(home: BankTransactionsScreen()),
);

void main() {
  testWidgets('disconnected state shows a working connect CTA', (tester) async {
    final repository = FakeBankingRepository();
    await tester.pumpWidget(accountsApp(repository, () async => []));
    await tester.pumpAndSettle();
    expect(find.text('No bank accounts connected.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('connect-bank')));
    await tester.pumpAndSettle();
    expect(repository.exchangeCalls, 1);
  });

  testWidgets(
    'browser Link exchanges the public token and refreshes accounts',
    (tester) async {
      final repository = FakeBankingRepository()..demoLink = false;
      final context = const PlaidLinkContext(
        organizationId: 'org',
        locationId: 'downtown',
      );
      final launcher = FakePlaidLinkLauncher(
        nextResult: PlaidLinkResult.success('public-token', context),
      );
      await tester.pumpWidget(
        accountsApp(repository, () async => [], launcher: launcher),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connect-bank')));
      await tester.pumpAndSettle();
      expect(repository.requestedWebLink, isTrue);
      expect(launcher.request?.linkToken, 'link-token');
      expect(repository.exchangeCalls, 1);
      expect(
        find.text('Unable to connect the bank account. Try again.'),
        findsNothing,
      );
    },
  );

  testWidgets('browser Link cancellation does not exchange a token', (
    tester,
  ) async {
    final repository = FakeBankingRepository()..demoLink = false;
    final launcher = FakePlaidLinkLauncher();
    await tester.pumpWidget(
      accountsApp(repository, () async => [], launcher: launcher),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connect-bank')));
    await tester.pumpAndSettle();
    expect(repository.exchangeCalls, 0);
    expect(
      find.text('Unable to connect the bank account. Try again.'),
      findsNothing,
    );
  });

  testWidgets('browser OAuth return exchanges once and refreshes connections', (
    tester,
  ) async {
    final repository = FakeBankingRepository()..demoLink = false;
    final launcher = FakePlaidLinkLauncher(
      oauthResult: PlaidLinkResult.success(
        'oauth-public-token',
        const PlaidLinkContext(organizationId: 'org', locationId: 'downtown'),
      ),
    );
    var loads = 0;
    await tester.pumpWidget(
      accountsApp(repository, () async {
        loads++;
        return [];
      }, launcher: launcher),
    );
    await tester.pumpAndSettle();
    expect(repository.exchangeCalls, 1);
    expect(loads, greaterThanOrEqualTo(2));
  });

  testWidgets(
    'bank accounts shows loading, masked success state, and sync action',
    (tester) async {
      final pending = Completer<List<BankConnectionData>>();
      final repository = FakeBankingRepository();
      await tester.pumpWidget(accountsApp(repository, () => pending.future));
      await tester.pump();
      expect(find.text('Loading bank accounts...'), findsOneWidget);
      pending.complete([connection]);
      await tester.pumpAndSettle();
      expect(find.text('Profit Lens Sandbox Bank'), findsOneWidget);
      expect(find.textContaining('•••• 4242'), findsOneWidget);
      expect(find.textContaining('Downtown Grill'), findsOneWidget);
      await tester.tap(find.text('Sync now'));
      await tester.pump();
      expect(repository.syncCalls, 1);
    },
  );

  testWidgets('bank accounts error provides retry', (tester) async {
    var calls = 0;
    final repository = FakeBankingRepository();
    await tester.pumpWidget(
      accountsApp(repository, () {
        calls++;
        return Future.error('network');
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to load bank accounts'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(calls, greaterThanOrEqualTo(2));
  });

  testWidgets('account location assignment uses available restaurants', (
    tester,
  ) async {
    final repository = FakeBankingRepository();
    await tester.pumpWidget(accountsApp(repository, () async => [connection]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Business Checking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lakeside Grill'));
    await tester.pumpAndSettle();
    expect(repository.assignedLocation, 'lakeside');
  });

  testWidgets(
    'sync failure is contained and shown as a safe connection error',
    (tester) async {
      final repository = FakeBankingRepository()..failSync = true;
      await tester.pumpWidget(
        accountsApp(repository, () async => [connection]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to update this bank connection. Try again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'reauth state exposes update-mode reconnect without duplicating a connection',
    (tester) async {
      final repository = FakeBankingRepository();
      final needsAttention = BankConnectionData(
        id: connection.id,
        institutionName: connection.institutionName,
        status: 'NEEDS_ATTENTION',
        accounts: connection.accounts,
        lastError: 'Reconnect your bank to continue syncing.',
      );
      await tester.pumpWidget(
        accountsApp(repository, () async => [needsAttention]),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reconnect-bank')), findsOneWidget);
      await tester.tap(find.byKey(const Key('reconnect-bank')));
      await tester.pumpAndSettle();
      expect(repository.reauthenticationCalls, 1);
      expect(repository.exchangeCalls, 0);
    },
  );

  testWidgets('disconnect confirmation preserves an explicit user decision', (
    tester,
  ) async {
    final repository = FakeBankingRepository();
    await tester.pumpWidget(accountsApp(repository, () async => [connection]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Imported transaction history will remain, but future syncing will stop.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await tester.pumpAndSettle();
    expect(repository.disconnectCalls, 1);
  });

  testWidgets('transaction queue renders review and matched filters', (
    tester,
  ) async {
    final repository = FakeBankingRepository();
    await tester.pumpWidget(transactionsApp(repository, [reviewTransaction]));
    await tester.pumpAndSettle();
    expect(find.text('Needs Review'), findsWidgets);
    expect(find.text('Sysco'), findsOneWidget);
    expect(find.text(r'$1446.00'), findsOneWidget);
    await tester.tap(find.text('Added / Linked'));
    await tester.pumpAndSettle();
    expect(find.text('Added / Linked'), findsOneWidget);
  });

  test(
    'matched filter combines invoice and expense reconciliation statuses',
    () async {
      final matchedInvoice = BankTransactionData(
        id: 'matched-invoice',
        merchant: 'Atlas',
        description: 'ATLAS ACH',
        amount: 100,
        postedDate: DateTime(2026, 10, 8),
        status: 'MATCHED_INVOICE',
        categorizationSource: 'INVOICE_MATCH',
        matchConfidence: 'EXACT',
        pending: false,
        restaurantLocationId: downtown.id,
      );
      final matchedExpense = BankTransactionData(
        id: 'matched-expense',
        merchant: 'ADP',
        description: 'ADP PAYROLL',
        amount: 200,
        postedDate: DateTime(2026, 10, 9),
        status: 'MATCHED_EXPENSE',
        categorizationSource: 'USER_REVIEWED',
        matchConfidence: 'NO_MATCH',
        pending: false,
        restaurantLocationId: downtown.id,
      );
      final repository = FakeBankingRepository()
        ..transactionsByStatus = {
          'MATCHED_INVOICE': [matchedInvoice],
          'MATCHED_EXPENSE': [matchedExpense],
        };
      final container = ProviderContainer(
        overrides: [
          activeLocationProvider.overrideWithValue(downtown),
          bankingRepositoryProvider.overrideWithValue(repository),
          bankTransactionFilterProvider.overrideWith(
            (_) => BankTransactionFilter.matched,
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(bankTransactionsProvider.future);

      expect(repository.transactionStatuses, [
        'MATCHED_INVOICE',
        'MATCHED_EXPENSE',
      ]);
      expect(result.map((item) => item.id), [
        'matched-expense',
        'matched-invoice',
      ]);
    },
  );

  test(
    'transaction lists and review counts share the selected date range',
    () async {
      final inRange = BankTransactionData(
        id: 'in-range',
        merchant: 'Current Merchant',
        description: 'CURRENT',
        amount: 20,
        postedDate: DateTime(2026, 10, 8),
        status: 'NEEDS_REVIEW',
        categorizationSource: 'PROVIDER',
        matchConfidence: 'NO_MATCH',
        pending: false,
        restaurantLocationId: downtown.id,
      );
      final outOfRange = BankTransactionData(
        id: 'out-of-range',
        merchant: 'Old Merchant',
        description: 'OLD',
        amount: 30,
        postedDate: DateTime(2026, 9, 30),
        status: 'NEEDS_REVIEW',
        categorizationSource: 'PROVIDER',
        matchConfidence: 'NO_MATCH',
        pending: false,
        restaurantLocationId: downtown.id,
      );
      final repository = FakeBankingRepository()
        ..transactionsByStatus = {
          'NEEDS_REVIEW': [inRange, outOfRange],
          null: [inRange, outOfRange],
        };
      final container = ProviderContainer(
        overrides: [
          activeLocationProvider.overrideWithValue(downtown),
          bankingRepositoryProvider.overrideWithValue(repository),
          dateRangeProvider.overrideWith(
            (_) => DateRangeState(
              DatePreset.custom,
              DateTime(2026, 10, 1),
              DateTime(2026, 10, 31),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final visible = await container.read(bankTransactionsProvider.future);
      final awaiting = await container.read(
        bankTransactionsAwaitingReviewProvider.future,
      );
      final all = await container.read(allBankTransactionsProvider.future);

      expect(visible.map((item) => item.id), ['in-range']);
      expect(awaiting.map((item) => item.id), ['in-range']);
      expect(all.map((item) => item.id), ['in-range']);
    },
  );

  testWidgets('expense actions use owner-friendly language', (tester) async {
    final repository = FakeBankingRepository();
    final matchedExpense = BankTransactionData(
      id: 'matched-expense-copy',
      merchant: 'Consumers Energy',
      description: 'UTILITY PAYMENT',
      amount: 29.44,
      postedDate: DateTime(2026, 10, 8),
      status: 'MATCHED_EXPENSE',
      categorizationSource: 'MANUAL',
      matchConfidence: 'NO_MATCH',
      pending: false,
      categoryId: 'food',
      categoryName: 'Food',
      restaurantLocationId: downtown.id,
    );
    await tester.pumpWidget(transactionsApp(repository, [matchedExpense]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consumers Energy'));
    await tester.pumpAndSettle();

    expect(find.text('Remove from Expenses'), findsOneWidget);
    expect(
      find.textContaining('original bank transaction remains'),
      findsOneWidget,
    );
    expect(find.text('Reverse Reconciliation'), findsNothing);
  });

  testWidgets('ignored transactions can return to Needs Review', (
    tester,
  ) async {
    final repository = FakeBankingRepository();
    final ignored = BankTransactionData(
      id: 'ignored-transfer',
      merchant: 'Broker Transfer',
      description: 'TRANSFER',
      amount: 94,
      postedDate: DateTime(2026, 10, 8),
      status: 'IGNORED',
      categorizationSource: 'MANUAL',
      matchConfidence: 'NO_MATCH',
      pending: false,
      restaurantLocationId: downtown.id,
    );
    await tester.pumpWidget(transactionsApp(repository, [ignored]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Broker Transfer'));
    await tester.pumpAndSettle();
    expect(find.text('Return to Needs Review'), findsOneWidget);
    await tester.ensureVisible(find.text('Return to Needs Review'));
    await tester.tap(find.text('Return to Needs Review'));
    await tester.pumpAndSettle();
    expect(repository.reversedTransaction, 'ignored-transfer');
  });

  test(
    'late response from a previous restaurant cannot replace current data',
    () async {
      final repository = DeferredBankingRepository();
      final container = ProviderContainer(
        overrides: [
          activeLocationProvider.overrideWith(
            (ref) => ref.watch(selectedBankLocationProvider),
          ),
          bankingRepositoryProvider.overrideWithValue(repository),
          bankTransactionFilterProvider.overrideWith(
            (_) => BankTransactionFilter.all,
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        bankTransactionsProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await Future<void>.delayed(Duration.zero);

      container.read(selectedBankLocationProvider.notifier).state = lakeside;
      await Future<void>.delayed(Duration.zero);
      final lakesideItem = BankTransactionData(
        id: 'lakeside-item',
        merchant: 'Lakeside Supplier',
        description: 'LAKESIDE',
        amount: 20,
        postedDate: DateTime(2026, 10, 8),
        status: 'NEEDS_REVIEW',
        categorizationSource: 'PROVIDER',
        matchConfidence: 'NO_MATCH',
        pending: false,
        restaurantLocationId: lakeside.id,
      );
      repository.requests[lakeside.id]!.complete([lakesideItem]);
      await container.read(bankTransactionsProvider.future);
      repository.requests[downtown.id]!.complete([reviewTransaction]);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(bankTransactionsProvider).valueOrNull, [
        lakesideItem,
      ]);
    },
  );

  testWidgets(
    'transaction empty state distinguishes synchronization progress',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeLocationProvider.overrideWithValue(downtown),
            bankTransactionsProvider.overrideWith((_) async => []),
            bankConnectionsProvider.overrideWith((_) async => [connection]),
            bankSyncStatusProvider.overrideWith(
              (_) => Stream.value(
                const BankSyncStatus(
                  state: BankImportState.importing,
                  connectionCount: 1,
                  transactionCount: 0,
                  canRetry: false,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: BankTransactionsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('synchronization is still in progress'),
        findsWidgets,
      );
    },
  );

  testWidgets('transaction empty state distinguishes completed empty history', (
    tester,
  ) async {
    await tester.pumpWidget(transactionsApp(FakeBankingRepository(), const []));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('no bank transactions were found'),
      findsOneWidget,
    );
  });

  testWidgets('transaction empty state explains account assigned elsewhere', (
    tester,
  ) async {
    final elsewhere = BankConnectionData(
      id: 'elsewhere',
      institutionName: 'Bank',
      status: 'CONNECTED',
      accounts: const [
        BankAccountData(
          id: 'elsewhere-account',
          name: 'Checking',
          active: true,
          restaurantLocationId: 'lakeside',
          restaurantLocationName: 'Lakeside Grill',
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLocationProvider.overrideWithValue(downtown),
          bankTransactionsProvider.overrideWith((_) async => []),
          bankConnectionsProvider.overrideWith((_) async => [elsewhere]),
          bankSyncStatusProvider.overrideWith(
            (_) => Stream.value(
              const BankSyncStatus(
                state: BankImportState.complete,
                connectionCount: 1,
                transactionCount: 0,
                canRetry: false,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: BankTransactionsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('assigned to another restaurant'),
      findsOneWidget,
    );
  });

  testWidgets(
    'exact invoice suggestion can be confirmed without creating an expense',
    (tester) async {
      final repository = FakeBankingRepository();
      await tester.pumpWidget(transactionsApp(repository, [reviewTransaction]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sysco'));
      await tester.pumpAndSettle();
      expect(find.text('EXACT invoice match'), findsOneWidget);
      expect(find.text('Raw description: SYSCO ACH'), findsOneWidget);
      expect(find.textContaining('10492'), findsOneWidget);
      await tester.tap(find.text('Confirm Match'));
      await tester.pumpAndSettle();
      expect(repository.confirmedInvoice, 'invoice');
    },
  );

  testWidgets('failed invoice confirmation stays open and reports no change', (
    tester,
  ) async {
    final repository = FakeBankingRepository()..failConfirm = true;
    await tester.pumpWidget(transactionsApp(repository, [reviewTransaction]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sysco'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Match'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No review status was changed'), findsOneWidget);
    expect(find.text('Confirm Match'), findsOneWidget);
    expect(repository.confirmedInvoice, isNull);
  });

  testWidgets('manual corrections can opt into a future merchant rule', (
    tester,
  ) async {
    final repository = FakeBankingRepository();
    await tester.pumpWidget(transactionsApp(repository, [reviewTransaction]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sysco'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-vendor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ADP').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.ensureVisible(find.text('Add to Expenses'));
    await tester.tap(find.text('Add to Expenses'));
    await tester.pumpAndSettle();
    expect(repository.reviewData, containsPair('vendorId', 'adp'));
    expect(repository.reviewData, containsPair('categoryId', 'food'));
    expect(repository.reviewData, containsPair('createRule', true));
  });

  testWidgets('explicit auto-confirm opt-in is sent with the approved rule', (
    tester,
  ) async {
    final repository = FakeBankingRepository();
    await tester.pumpWidget(transactionsApp(repository, [reviewTransaction]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sysco'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('auto-confirm-future')));
    await tester.tap(find.byKey(const Key('auto-confirm-future')));
    await tester.ensureVisible(find.text('Add to Expenses'));
    await tester.tap(find.text('Add to Expenses'));
    await tester.pumpAndSettle();
    expect(repository.reviewData, containsPair('createRule', true));
    expect(repository.reviewData, containsPair('autoConfirmFuture', true));
  });

  testWidgets('eligible transactions support bulk confirmation', (
    tester,
  ) async {
    final repository = FakeBankingRepository();
    final eligible = BankTransactionData(
      id: 'eligible',
      merchant: 'Restaurant Depot',
      description: 'RESTAURANT DEPOT',
      amount: 250,
      postedDate: DateTime(2026, 10, 8),
      status: 'NEEDS_REVIEW',
      categorizationSource: 'PROVIDER',
      matchConfidence: 'NO_MATCH',
      pending: false,
      restaurantLocationId: downtown.id,
    );
    await tester.pumpWidget(transactionsApp(repository, [eligible]));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Add Selected to Expenses').first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Add Selected to Expenses').last,
    );
    await tester.pumpAndSettle();
    expect(repository.bulkIds, ['eligible']);
  });

  testWidgets(
    'partial bulk success keeps failed rows selected and reports it',
    (tester) async {
      final repository = FakeBankingRepository()
        ..bulkResult = const BulkReviewResult(
          requestedCount: 2,
          confirmedCount: 1,
          failedIds: ['second'],
        );
      final items = [
        BankTransactionData(
          id: 'first',
          merchant: 'First Merchant',
          description: 'FIRST',
          amount: 25,
          postedDate: DateTime(2026, 10, 8),
          status: 'NEEDS_REVIEW',
          categorizationSource: 'PROVIDER',
          matchConfidence: 'NO_MATCH',
          pending: false,
          restaurantLocationId: downtown.id,
        ),
        BankTransactionData(
          id: 'second',
          merchant: 'Second Merchant',
          description: 'SECOND',
          amount: 35,
          postedDate: DateTime(2026, 10, 9),
          status: 'NEEDS_REVIEW',
          categorizationSource: 'PROVIDER',
          matchConfidence: 'NO_MATCH',
          pending: false,
          restaurantLocationId: downtown.id,
        ),
      ];
      await tester.pumpWidget(transactionsApp(repository, items));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Add Selected to Expenses').first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Add Selected to Expenses').last,
      );
      await tester.pump();

      expect(
        find.textContaining('1 completed; 1 could not be completed'),
        findsOneWidget,
      );
      final checkboxes = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .toList();
      expect(checkboxes.map((checkbox) => checkbox.value), [false, true]);
    },
  );

  testWidgets('similar review selects only the opened transaction by default', (
    tester,
  ) async {
    BankTransactionData transaction(String id, int day, double amount) =>
        BankTransactionData(
          id: id,
          merchant: 'Robinhood',
          description: 'ROBINHOOD',
          amount: amount,
          postedDate: DateTime(2026, 10, day),
          status: 'NEEDS_REVIEW',
          categorizationSource: 'PROVIDER',
          matchConfidence: 'NO_MATCH',
          pending: false,
          restaurantLocationId: downtown.id,
          bankAccountId: 'account',
          providerCategoryId: 'TRANSFER',
          direction: 'OUTFLOW',
        );
    final opened = transaction('opened', 14, 43);
    final second = transaction('second', 12, 85);
    final third = transaction('third', 10, 150);
    final repository = FakeBankingRepository()
      ..similarItems = [opened, second, third];

    await tester.pumpWidget(transactionsApp(repository, [opened]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Robinhood').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Personal / Transfer'));
    await tester.tap(find.text('Personal / Transfer'));
    await tester.pumpAndSettle();

    expect(find.text('Outgoing — Money leaving your bank'), findsOneWidget);
    expect(find.text('Decision: Personal / Transfer'), findsOneWidget);
    expect(find.textContaining('Selected: 1 of 3'), findsOneWidget);
    expect(find.text('Apply to 1 Transaction'), findsOneWidget);

    await tester.tap(find.byKey(const Key('similar-transaction-second')));
    await tester.pump();
    expect(find.textContaining('Selected: 2 of 3'), findsOneWidget);
    expect(find.text('Apply to 2 Transactions'), findsOneWidget);

    await tester.tap(find.byKey(const Key('similar-transaction-opened')));
    await tester.pump();
    expect(find.textContaining('Selected: 1 of 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('select-all-similar')));
    await tester.pump();
    expect(find.textContaining('Selected: 3 of 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('deselect-all-similar')));
    await tester.pump();
    expect(find.textContaining('Selected: 0 of 3'), findsOneWidget);
    final emptyButton = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-similar-selection')),
    );
    expect(emptyButton.onPressed, isNull);

    await tester.tap(find.byKey(const Key('similar-transaction-opened')));
    await tester.tap(find.byKey(const Key('similar-transaction-second')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-similar-selection')));
    await tester.pumpAndSettle();
    expect(repository.bulkIds, containsAllInOrder(['opened', 'second']));
    expect(repository.bulkIds, isNot(contains('third')));
    expect(repository.bulkAnchor, 'opened');
  });

  testWidgets('group selection supports more than one hundred transactions', (
    tester,
  ) async {
    final items = List.generate(
      101,
      (index) => BankTransactionData(
        id: 'row-$index',
        merchant: 'Robinhood',
        description: 'ROBINHOOD',
        amount: 10 + index.toDouble(),
        postedDate: DateTime(2026, 10, 14).subtract(Duration(days: index)),
        status: 'NEEDS_REVIEW',
        categorizationSource: 'PROVIDER',
        matchConfidence: 'NO_MATCH',
        pending: false,
        restaurantLocationId: downtown.id,
        direction: 'OUTFLOW',
      ),
    );
    final repository = FakeBankingRepository()..similarItems = items;
    await tester.pumpWidget(transactionsApp(repository, [items.first]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Robinhood').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Personal / Transfer'));
    await tester.tap(find.text('Personal / Transfer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Selected: 1 of 101'), findsOneWidget);
    await tester.tap(find.byKey(const Key('select-all-similar')));
    await tester.pump();
    expect(find.text('Apply to 101 Transactions'), findsOneWidget);
  });

  testWidgets('complete grouped failure stays open without false success', (
    tester,
  ) async {
    BankTransactionData transaction(String id, int day) => BankTransactionData(
      id: id,
      merchant: 'Robinhood',
      description: 'ROBINHOOD',
      amount: 50,
      postedDate: DateTime(2026, 10, day),
      status: 'NEEDS_REVIEW',
      categorizationSource: 'PROVIDER',
      matchConfidence: 'NO_MATCH',
      pending: false,
      restaurantLocationId: downtown.id,
      direction: 'OUTFLOW',
    );
    final opened = transaction('opened', 14);
    final second = transaction('second', 12);
    final repository = FakeBankingRepository()
      ..similarItems = [opened, second]
      ..bulkResult = const BulkReviewResult(
        requestedCount: 2,
        confirmedCount: 0,
        failedIds: ['opened', 'second'],
      );
    await tester.pumpWidget(transactionsApp(repository, [opened]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Robinhood').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Personal / Transfer'));
    await tester.tap(find.text('Personal / Transfer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('select-all-similar')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-similar-selection')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'None of the selected transactions could be completed',
      ),
      findsOneWidget,
    );
    expect(find.text('Personal / Transfer'), findsOneWidget);
  });

  testWidgets('incoming transactions never offer expense actions', (
    tester,
  ) async {
    final incoming = BankTransactionData(
      id: 'incoming',
      merchant: 'Robinhood',
      description: 'ROBINHOOD CREDIT',
      amount: -50,
      postedDate: DateTime(2026, 10, 14),
      status: 'NEEDS_REVIEW',
      categorizationSource: 'PROVIDER',
      matchConfidence: 'NO_MATCH',
      pending: false,
      restaurantLocationId: downtown.id,
      direction: 'INFLOW',
    );
    await tester.pumpWidget(
      transactionsApp(FakeBankingRepository(), [incoming]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Robinhood').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('incoming-review-guidance')), findsOneWidget);
    expect(find.text('Add to Expenses'), findsNothing);
    expect(find.byKey(const Key('auto-confirm-future')), findsNothing);
    expect(find.byKey(const Key('review-vendor')), findsNothing);
    expect(find.byKey(const Key('review-category')), findsNothing);
    expect(find.text('Personal / Transfer'), findsOneWidget);
    expect(find.text('Review Later'), findsOneWidget);
  });
}
