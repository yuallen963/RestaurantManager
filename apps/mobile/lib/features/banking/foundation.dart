import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show api;
import '../dashboard/foundation.dart';

double _money(dynamic value) =>
    value is num ? value.toDouble() : double.parse(value as String);

class BankAccountData {
  const BankAccountData({
    required this.id,
    required this.name,
    required this.active,
    this.mask,
    this.restaurantLocationId,
    this.restaurantLocationName,
  });
  final String id, name;
  final String? mask, restaurantLocationId, restaurantLocationName;
  final bool active;
  factory BankAccountData.fromJson(Map<String, dynamic> json) {
    final location = json['restaurantLocation'] as Map?;
    return BankAccountData(
      id: json['id'] as String,
      name: json['name'] as String,
      mask: json['mask'] as String?,
      active: json['active'] as bool? ?? true,
      restaurantLocationId: json['restaurantLocationId'] as String?,
      restaurantLocationName: location?['name'] as String?,
    );
  }
}

class BankConnectionData {
  const BankConnectionData({
    required this.id,
    required this.institutionName,
    required this.status,
    required this.accounts,
    this.lastSyncAt,
    this.lastError,
  });
  final String id, institutionName, status;
  final DateTime? lastSyncAt;
  final String? lastError;
  final List<BankAccountData> accounts;
  factory BankConnectionData.fromJson(
    Map<String, dynamic> json,
  ) => BankConnectionData(
    id: json['id'] as String,
    institutionName:
        json['institutionName'] as String? ?? 'Connected institution',
    status: json['status'] as String,
    lastSyncAt: json['lastSyncAt'] == null
        ? null
        : DateTime.parse(json['lastSyncAt'] as String),
    lastError: json['lastError'] as String?,
    accounts: (json['accounts'] as List? ?? const [])
        .map(
          (item) =>
              BankAccountData.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );
}

enum BankImportState {
  none,
  pending,
  importing,
  partiallyComplete,
  complete,
  failed,
}

class BankSyncStatus {
  const BankSyncStatus({
    required this.state,
    required this.connectionCount,
    required this.transactionCount,
    required this.canRetry,
    this.lastSyncAt,
    this.message,
  });

  final BankImportState state;
  final int connectionCount, transactionCount;
  final bool canRetry;
  final DateTime? lastSyncAt;
  final String? message;

  bool get inProgress =>
      state == BankImportState.pending ||
      state == BankImportState.importing ||
      state == BankImportState.partiallyComplete;

  factory BankSyncStatus.fromJson(Map<String, dynamic> json) => BankSyncStatus(
    state: switch (json['state'] as String) {
      'PENDING' => BankImportState.pending,
      'IMPORTING' => BankImportState.importing,
      'PARTIALLY_COMPLETE' => BankImportState.partiallyComplete,
      'COMPLETE' => BankImportState.complete,
      'FAILED' => BankImportState.failed,
      _ => BankImportState.none,
    },
    connectionCount: json['connectionCount'] as int? ?? 0,
    transactionCount: json['transactionCount'] as int? ?? 0,
    canRetry: json['canRetry'] as bool? ?? false,
    lastSyncAt: json['lastSyncAt'] == null
        ? null
        : DateTime.parse(json['lastSyncAt'] as String),
    message: json['message'] as String?,
  );
}

class SuggestedInvoiceData {
  const SuggestedInvoiceData(this.id, this.number, this.total);
  final String id;
  final String? number;
  final double total;
  factory SuggestedInvoiceData.fromJson(Map<String, dynamic> json) =>
      SuggestedInvoiceData(
        json['id'] as String,
        json['invoiceNumber'] as String?,
        _money(json['total']),
      );
}

class BankTransactionData {
  const BankTransactionData({
    required this.id,
    required this.merchant,
    required this.description,
    required this.amount,
    required this.postedDate,
    required this.status,
    required this.categorizationSource,
    required this.matchConfidence,
    required this.pending,
    this.categoryId,
    this.categoryName,
    this.vendorId,
    this.vendorName,
    this.restaurantLocationId,
    this.invoiceNumber,
    this.suggestedInvoice,
    this.bankAccountId,
    this.bankAccountName,
    this.providerCategoryId,
  });
  final String id,
      merchant,
      description,
      status,
      categorizationSource,
      matchConfidence;
  final double amount;
  final bool pending;
  final DateTime postedDate;
  final String? categoryId,
      categoryName,
      vendorId,
      vendorName,
      restaurantLocationId,
      invoiceNumber;
  final String? bankAccountId, bankAccountName, providerCategoryId;
  final SuggestedInvoiceData? suggestedInvoice;
  factory BankTransactionData.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map?;
    final vendor = json['vendor'] as Map?;
    final invoice = json['invoice'] as Map?;
    final suggested = json['suggestedInvoice'] as Map?;
    final account = json['bankAccount'] as Map?;
    return BankTransactionData(
      id: json['id'] as String,
      merchant:
          json['merchantNameNormalized'] as String? ??
          json['description'] as String,
      description: json['description'] as String,
      amount: _money(json['amount']),
      postedDate: DateTime.parse(json['postedDate'] as String),
      status: json['reconciliationStatus'] as String,
      categorizationSource: json['categorizationSource'] as String,
      matchConfidence: json['matchConfidence'] as String? ?? 'NO_MATCH',
      pending: json['pending'] as bool? ?? false,
      bankAccountId: json['bankAccountId'] as String?,
      bankAccountName: account?['name'] as String?,
      providerCategoryId: json['providerCategoryId'] as String?,
      categoryId: json['categoryId'] as String?,
      categoryName: category?['name'] as String?,
      vendorId: json['vendorId'] as String?,
      vendorName: vendor?['name'] as String?,
      restaurantLocationId: json['restaurantLocationId'] as String?,
      invoiceNumber: invoice?['invoiceNumber'] as String?,
      suggestedInvoice: suggested == null
          ? null
          : SuggestedInvoiceData.fromJson(Map<String, dynamic>.from(suggested)),
    );
  }
}

enum BankReviewDecision { expense, personalTransfer, reviewLater }

String _reviewDecisionName(BankReviewDecision decision) => switch (decision) {
  BankReviewDecision.expense => 'EXPENSE',
  BankReviewDecision.personalTransfer => 'PERSONAL_TRANSFER',
  BankReviewDecision.reviewLater => 'REVIEW_LATER',
};

class BankLinkSetup {
  const BankLinkSetup(this.linkToken, this.demo, {this.updateMode = false});
  final String linkToken;
  final bool demo;
  final bool updateMode;
}

class MerchantRuleData {
  const MerchantRuleData({
    required this.id,
    required this.merchant,
    required this.active,
    required this.autoConfirm,
    this.vendorName,
    this.categoryName,
    this.vendorId,
    this.categoryId,
    this.minimumAmount,
    this.maximumAmount,
    this.decision = 'EXPENSE',
    this.direction,
    this.bankAccountId,
  });
  final String id, merchant;
  final String decision;
  final bool active, autoConfirm;
  final String? vendorName, categoryName, vendorId, categoryId;
  final String? direction, bankAccountId;
  final double? minimumAmount, maximumAmount;

  factory MerchantRuleData.fromJson(Map<String, dynamic> json) =>
      MerchantRuleData(
        id: json['id'] as String,
        merchant: json['normalizedMerchantName'] as String,
        active: json['active'] as bool? ?? true,
        autoConfirm: json['autoConfirm'] as bool? ?? false,
        decision: json['decision'] as String? ?? 'EXPENSE',
        direction: json['direction'] as String?,
        bankAccountId: json['bankAccountId'] as String?,
        vendorName: (json['vendor'] as Map?)?['name'] as String?,
        categoryName: (json['expenseCategory'] as Map?)?['name'] as String?,
        vendorId: (json['vendor'] as Map?)?['id'] as String?,
        categoryId: (json['expenseCategory'] as Map?)?['id'] as String?,
        minimumAmount: json['minimumAmount'] == null
            ? null
            : _money(json['minimumAmount']),
        maximumAmount: json['maximumAmount'] == null
            ? null
            : _money(json['maximumAmount']),
      );
}

class BulkReviewResult {
  const BulkReviewResult({
    required this.requestedCount,
    required this.confirmedCount,
    required this.failedIds,
  });

  final int requestedCount, confirmedCount;
  final List<String> failedIds;

  factory BulkReviewResult.fromJson(Map<String, dynamic> json) =>
      BulkReviewResult(
        requestedCount: json['requestedCount'] as int? ?? 0,
        confirmedCount: json['count'] as int? ?? 0,
        failedIds: (json['failures'] as List? ?? const [])
            .map((failure) => (failure as Map)['id'] as String)
            .toList(),
      );
}

class BankingRepository {
  BankingRepository(this.dio);
  final Dio dio;
  Future<BankLinkSetup> linkToken(String organizationId) async {
    final response = await dio.post(
      '/bank/link-token',
      data: {'organizationId': organizationId},
    );
    return BankLinkSetup(
      response.data['linkToken'] as String,
      response.data['demo'] as bool? ?? false,
    );
  }

  Future<BankLinkSetup> reauthenticationLinkToken(String connectionId) async {
    final response = await dio.post(
      '/bank/connections/$connectionId/link-token',
    );
    return BankLinkSetup(
      response.data['linkToken'] as String,
      response.data['demo'] as bool? ?? false,
      updateMode: response.data['updateMode'] as bool? ?? true,
    );
  }

  Future<void> completeReauthentication(String connectionId) =>
      dio.post('/bank/connections/$connectionId/reauthenticated');

  Future<void> exchange(
    String organizationId,
    String publicToken,
    String? locationId,
  ) {
    final data = <String, dynamic>{
      'organizationId': organizationId,
      'publicToken': publicToken,
      'restaurantLocationId': locationId,
    }..removeWhere((_, value) => value == null);
    return dio.post('/bank/exchange-token', data: data);
  }

  Future<List<BankConnectionData>> connections(String organizationId) async =>
      (await dio.get(
            '/bank/connections',
            queryParameters: {'organizationId': organizationId},
          )).data
          .map<BankConnectionData>(
            (item) =>
                BankConnectionData.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
  Future<BankSyncStatus> syncStatus(
    String organizationId,
    String locationId,
  ) async {
    final response = await dio.get(
      '/bank/sync-status',
      queryParameters: {
        'organizationId': organizationId,
        'restaurantLocationId': locationId,
      },
    );
    return BankSyncStatus.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<void> assignAccount(String id, String? locationId) => dio.patch(
    '/bank/accounts/$id',
    data: {'restaurantLocationId': locationId},
  );
  Future<void> sync(String id) => dio.post('/bank/connections/$id/sync');
  Future<void> disconnect(String id) => dio.delete('/bank/connections/$id');
  Future<List<BankTransactionData>> transactions(
    String organizationId,
    String? locationId,
    String? status,
  ) async {
    final query = <String, dynamic>{
      'organizationId': organizationId,
      'restaurantLocationId': locationId,
      'status': status,
    }..removeWhere((_, value) => value == null);
    return (await dio.get('/bank-transactions', queryParameters: query)).data
        .map<BankTransactionData>(
          (item) =>
              BankTransactionData.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

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
  }) => dio.patch(
    '/bank-transactions/$id/review',
    data: {
      'vendorId': vendorId,
      'categoryId': categoryId,
      'restaurantLocationId': locationId,
      'ignored': ignored,
      'decision': decision == null ? null : _reviewDecisionName(decision),
      'createMerchantRule': createRule,
      'autoConfirmFuture': autoConfirmFuture,
      'minimumAmount': minimumAmount,
      'maximumAmount': maximumAmount,
    },
  );
  Future<List<BankTransactionData>> similarTransactions(String id) async =>
      (await dio.get('/bank-transactions/$id/similar')).data
          .map<BankTransactionData>(
            (item) =>
                BankTransactionData.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
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
  }) async {
    final response = await dio.post(
      '/bank-transactions/bulk-review',
      data: {
        'ids': ids,
        'vendorId': vendorId,
        'categoryId': categoryId,
        'restaurantLocationId': locationId,
        'ignored': ignored,
        'decision': decision == null ? null : _reviewDecisionName(decision),
        'createMerchantRule': createRule,
        'autoConfirmFuture': autoConfirmFuture,
        'minimumAmount': minimumAmount,
        'maximumAmount': maximumAmount,
      },
    );
    return BulkReviewResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<void> reverse(String id) => dio.post('/bank-transactions/$id/reverse');
  Future<List<MerchantRuleData>> merchantRules(
    String organizationId,
    String locationId,
  ) async =>
      (await dio.get(
            '/bank/merchant-rules',
            queryParameters: {
              'organizationId': organizationId,
              'restaurantLocationId': locationId,
            },
          )).data
          .map<MerchantRuleData>(
            (item) =>
                MerchantRuleData.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
  Future<void> updateMerchantRule(
    String id, {
    bool? active,
    bool? autoConfirm,
    String? vendorId,
    String? categoryId,
    double? minimumAmount,
    double? maximumAmount,
  }) => dio.patch(
    '/bank/merchant-rules/$id',
    data: <String, dynamic>{
      'active': active,
      'autoConfirm': autoConfirm,
      'vendorId': vendorId,
      'categoryId': categoryId,
      'minimumAmount': minimumAmount,
      'maximumAmount': maximumAmount,
    }..removeWhere((_, value) => value == null),
  );
  Future<void> confirmMatch(String id, String invoiceId) => dio.post(
    '/bank-transactions/$id/confirm-match',
    data: {'invoiceId': invoiceId},
  );
  Future<void> rejectMatch(String id) =>
      dio.post('/bank-transactions/$id/reject-match');
}

enum BankTransactionFilter { needsReview, matched, all }

final bankingRepositoryProvider = Provider(
  (ref) => BankingRepository(ref.watch(api)),
);
final bankTransactionFilterProvider = StateProvider<BankTransactionFilter>(
  (_) => BankTransactionFilter.needsReview,
);
final bankConnectionsProvider = FutureProvider<List<BankConnectionData>>((
  ref,
) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) return [];
  return ref
      .watch(bankingRepositoryProvider)
      .connections(location.organizationId);
});
final bankSyncPollIntervalProvider = Provider<Duration>(
  (_) => const Duration(seconds: 5),
);
final bankSyncStatusProvider = StreamProvider.autoDispose<BankSyncStatus>((
  ref,
) async* {
  final location = ref.watch(activeLocationProvider);
  if (location == null) {
    yield const BankSyncStatus(
      state: BankImportState.none,
      connectionCount: 0,
      transactionCount: 0,
      canRetry: false,
    );
    return;
  }
  var disposed = false;
  ref.onDispose(() => disposed = true);
  while (!disposed) {
    final status = await ref
        .read(bankingRepositoryProvider)
        .syncStatus(location.organizationId, location.id);
    yield status;
    if (!status.inProgress) return;
    await Future<void>.delayed(ref.read(bankSyncPollIntervalProvider));
  }
});
final bankTransactionsProvider = FutureProvider<List<BankTransactionData>>((
  ref,
) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) return [];
  final range = ref.watch(dateRangeProvider);
  final filter = ref.watch(bankTransactionFilterProvider);
  final repository = ref.watch(bankingRepositoryProvider);
  if (filter == BankTransactionFilter.matched) {
    final results = await Future.wait([
      repository.transactions(
        location.organizationId,
        location.id,
        'MATCHED_INVOICE',
      ),
      repository.transactions(
        location.organizationId,
        location.id,
        'MATCHED_EXPENSE',
      ),
    ]);
    final ids = <String>{};
    return [
        ...results.expand((items) => items).where((item) => ids.add(item.id)),
      ].where((item) => _isInRange(item, range)).toList()
      ..sort((a, b) => b.postedDate.compareTo(a.postedDate));
  }
  return (await repository.transactions(
    location.organizationId,
    location.id,
    filter == BankTransactionFilter.needsReview ? 'NEEDS_REVIEW' : null,
  )).where((item) => _isInRange(item, range)).toList();
});

/// Independent of the visible Bank Transactions filter so Expenses and Vendors
/// can explain why imported activity is not yet authoritative financial data.
final bankTransactionsAwaitingReviewProvider =
    FutureProvider<List<BankTransactionData>>((ref) async {
      final location = ref.watch(activeLocationProvider);
      if (location == null) return [];
      final range = ref.watch(dateRangeProvider);
      return (await ref
              .watch(bankingRepositoryProvider)
              .transactions(
                location.organizationId,
                location.id,
                'NEEDS_REVIEW',
              ))
          .where((item) => _isInRange(item, range))
          .toList();
    });

final allBankTransactionsProvider = FutureProvider<List<BankTransactionData>>((
  ref,
) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) return [];
  final range = ref.watch(dateRangeProvider);
  return (await ref
          .watch(bankingRepositoryProvider)
          .transactions(location.organizationId, location.id, null))
      .where((item) => _isInRange(item, range))
      .toList();
});

bool _isInRange(BankTransactionData item, DateRangeState range) =>
    !item.postedDate.isBefore(range.startDate) &&
    item.postedDate.isBefore(range.endDate.add(const Duration(days: 1)));

final unverifiedBankDepositsProvider =
    FutureProvider<List<BankTransactionData>>(
      (ref) async => (await ref.watch(
        allBankTransactionsProvider.future,
      )).where((item) => item.amount < 0 && item.status != 'IGNORED').toList(),
    );

final merchantRulesProvider = FutureProvider<List<MerchantRuleData>>((
  ref,
) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) return [];
  return ref
      .watch(bankingRepositoryProvider)
      .merchantRules(location.organizationId, location.id);
});
