import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/banking/bank_screens.dart';
import 'package:restaurant_profit_mobile/features/banking/foundation.dart';
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

class FakeBankingRepository extends BankingRepository {
  FakeBankingRepository() : super(Dio());
  int syncCalls = 0, retryCalls = 0;
  String? assignedLocation, confirmedInvoice;
  Map<String, dynamic>? reviewData;
  @override
  Future<BankLinkSetup> linkToken(String organizationId) async =>
      const BankLinkSetup('demo-link', true);
  @override
  Future<void> exchange(
    String organizationId,
    String publicToken,
    String? locationId,
  ) async {}
  @override
  Future<void> assignAccount(String id, String? locationId) async {
    assignedLocation = locationId;
  }

  @override
  Future<void> sync(String id) async {
    syncCalls++;
  }

  @override
  Future<void> disconnect(String id) async {}
  @override
  Future<void> confirmMatch(String id, String invoiceId) async {
    confirmedInvoice = invoiceId;
  }

  @override
  Future<void> rejectMatch(String id) async {}
  @override
  Future<void> review(
    String id, {
    String? vendorId,
    String? categoryId,
    String? locationId,
    bool ignored = false,
    bool createRule = false,
  }) async {
    reviewData = {
      'vendorId': vendorId,
      'categoryId': categoryId,
      'locationId': locationId,
      'ignored': ignored,
      'createRule': createRule,
    };
  }
}

Widget accountsApp(
  FakeBankingRepository repository,
  Future<List<BankConnectionData>> Function() load,
) => ProviderScope(
  overrides: [
    activeLocationProvider.overrideWithValue(downtown),
    availableLocationsProvider.overrideWithValue(const [downtown, lakeside]),
    bankingRepositoryProvider.overrideWithValue(repository),
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
    expenseLookupsProvider.overrideWith((_) async => lookups),
  ],
  child: const MaterialApp(home: BankTransactionsScreen()),
);

void main() {
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

  testWidgets('transaction queue renders review and matched filters', (
    tester,
  ) async {
    final repository = FakeBankingRepository();
    await tester.pumpWidget(transactionsApp(repository, [reviewTransaction]));
    await tester.pumpAndSettle();
    expect(find.text('Needs Review'), findsWidgets);
    expect(find.text('Sysco'), findsOneWidget);
    expect(find.text(r'$1446.00'), findsOneWidget);
    await tester.tap(find.text('Matched'));
    await tester.pumpAndSettle();
    expect(find.text('Matched'), findsOneWidget);
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
      expect(find.textContaining('10492'), findsOneWidget);
      await tester.tap(find.text('Confirm Match'));
      await tester.pumpAndSettle();
      expect(repository.confirmedInvoice, 'invoice');
    },
  );

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
    await tester.tap(find.byType(Switch));
    await tester.tap(find.text('Save Review'));
    await tester.pumpAndSettle();
    expect(repository.reviewData, containsPair('vendorId', 'adp'));
    expect(repository.reviewData, containsPair('categoryId', 'food'));
    expect(repository.reviewData, containsPair('createRule', true));
  });
}
