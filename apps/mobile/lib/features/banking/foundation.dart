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
    this.categoryId,
    this.categoryName,
    this.vendorId,
    this.vendorName,
    this.restaurantLocationId,
    this.invoiceNumber,
    this.suggestedInvoice,
  });
  final String id,
      merchant,
      description,
      status,
      categorizationSource,
      matchConfidence;
  final double amount;
  final DateTime postedDate;
  final String? categoryId,
      categoryName,
      vendorId,
      vendorName,
      restaurantLocationId,
      invoiceNumber;
  final SuggestedInvoiceData? suggestedInvoice;
  factory BankTransactionData.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map?;
    final vendor = json['vendor'] as Map?;
    final invoice = json['invoice'] as Map?;
    final suggested = json['suggestedInvoice'] as Map?;
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

class BankLinkSetup {
  const BankLinkSetup(this.linkToken, this.demo);
  final String linkToken;
  final bool demo;
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
    bool createRule = false,
  }) => dio.patch(
    '/bank-transactions/$id/review',
    data: {
      'vendorId': vendorId,
      'categoryId': categoryId,
      'restaurantLocationId': locationId,
      'ignored': ignored,
      'createMerchantRule': createRule,
    },
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
final bankTransactionsProvider = FutureProvider<List<BankTransactionData>>((
  ref,
) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) return [];
  final filter = ref.watch(bankTransactionFilterProvider);
  final status = switch (filter) {
    BankTransactionFilter.needsReview => 'NEEDS_REVIEW',
    BankTransactionFilter.matched => 'MATCHED_INVOICE',
    BankTransactionFilter.all => null,
  };
  return ref
      .watch(bankingRepositoryProvider)
      .transactions(location.organizationId, location.id, status);
});
