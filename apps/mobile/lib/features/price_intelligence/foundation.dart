import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show api;
import '../dashboard/foundation.dart';

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.parse(value);
  throw const FormatException('Expected numeric value');
}

double? _optionalNumber(dynamic value) => value == null ? null : _number(value);

enum PriceChangeSort {
  largestPercentIncrease('Largest % Increase', 'largestPercentIncrease'),
  largestMonthlyImpact('Largest Monthly Impact', 'largestMonthlyImpact'),
  mostRecent('Most Recent Change', 'mostRecent'),
  vendor('Vendor', 'vendor');

  const PriceChangeSort(this.label, this.apiValue);
  final String label;
  final String apiValue;
}

class PriceChangeItem {
  const PriceChangeItem({
    required this.vendorId,
    required this.vendorName,
    required this.itemKey,
    required this.displayName,
    required this.unit,
    this.currency = 'USD',
    required this.previousUnitPrice,
    required this.currentUnitPrice,
    required this.absoluteChange,
    required this.percentageChange,
    required this.firstSeenAt,
    required this.latestSeenAt,
    this.sku,
    this.packSize,
    this.typicalMonthlyQuantity,
    this.estimatedMonthlyImpact,
    this.estimatedAnnualImpact,
    this.observationCount = 0,
    this.impactExplanation,
  });

  final String vendorId, vendorName, itemKey, displayName, unit;
  final String currency;
  final String? sku, packSize;
  final double previousUnitPrice, currentUnitPrice, absoluteChange;
  final double percentageChange;
  final double? typicalMonthlyQuantity;
  final double? estimatedMonthlyImpact, estimatedAnnualImpact;
  final int observationCount;
  final String? impactExplanation;
  final DateTime firstSeenAt, latestSeenAt;

  bool get isIncrease => absoluteChange > 0;

  factory PriceChangeItem.fromJson(Map<String, dynamic> json) =>
      PriceChangeItem(
        vendorId: json['vendorId'] as String,
        vendorName: json['vendorName'] as String,
        itemKey: json['itemKey'] as String,
        displayName: json['displayName'] as String,
        sku: json['sku'] as String?,
        unit: json['unit'] as String,
        currency: json['currency'] as String? ?? 'USD',
        packSize: json['packSize'] as String?,
        previousUnitPrice: _number(json['previousUnitPrice']),
        currentUnitPrice: _number(json['currentUnitPrice']),
        absoluteChange: _number(json['absoluteChange']),
        percentageChange: _number(json['percentageChange']),
        typicalMonthlyQuantity: _optionalNumber(json['typicalMonthlyQuantity']),
        estimatedMonthlyImpact: _optionalNumber(json['estimatedMonthlyImpact']),
        estimatedAnnualImpact: _optionalNumber(json['estimatedAnnualImpact']),
        observationCount: json['observationCount'] as int? ?? 0,
        impactExplanation: json['impactExplanation'] as String?,
        firstSeenAt: DateTime.parse(json['firstSeenAt'] as String),
        latestSeenAt: DateTime.parse(json['latestSeenAt'] as String),
      );
}

class PriceChangesData {
  const PriceChangesData({
    required this.items,
    required this.lookbackDays,
    this.reviewedLines = 0,
    this.eligibleObservations = 0,
    this.excludedObservations = 0,
  });
  final List<PriceChangeItem> items;
  final int lookbackDays;
  final int reviewedLines, eligibleObservations, excludedObservations;

  factory PriceChangesData.fromJson(Map<String, dynamic> json) {
    final eligibility = json['eligibility'] is Map
        ? Map<String, dynamic>.from(json['eligibility'] as Map)
        : const <String, dynamic>{};
    return PriceChangesData(
      items: (json['items'] as List)
          .map(
            (item) => PriceChangeItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      lookbackDays: json['lookbackDays'] as int,
      reviewedLines: eligibility['reviewedLines'] as int? ?? 0,
      eligibleObservations: eligibility['eligibleObservations'] as int? ?? 0,
      excludedObservations: eligibility['excludedObservations'] as int? ?? 0,
    );
  }
}

class PriceHistoryPoint {
  const PriceHistoryPoint({
    required this.date,
    required this.invoiceId,
    required this.unitPrice,
    this.quantity,
    this.rawDescription = '',
    this.originalQuantity,
    this.packSize,
    this.purchasePrice,
    this.currency = 'USD',
  });
  final DateTime date;
  final String invoiceId;
  final double unitPrice;
  final double? quantity;
  final String rawDescription;
  final double? originalQuantity;
  final String? packSize;
  final double? purchasePrice;
  final String currency;

  factory PriceHistoryPoint.fromJson(Map<String, dynamic> json) =>
      PriceHistoryPoint(
        date: DateTime.parse(json['date'] as String),
        invoiceId: json['invoiceId'] as String,
        unitPrice: _number(json['unitPrice']),
        quantity: _optionalNumber(json['quantity']),
        rawDescription: json['rawDescription'] as String? ?? '',
        originalQuantity: _optionalNumber(json['originalQuantity']),
        packSize: json['packSize'] as String?,
        purchasePrice: _optionalNumber(json['purchasePrice']),
        currency: json['currency'] as String? ?? 'USD',
      );
}

class PriceHistoryData {
  const PriceHistoryData({required this.item, required this.history});
  final PriceChangeItem item;
  final List<PriceHistoryPoint> history;

  factory PriceHistoryData.fromJson(Map<String, dynamic> json) =>
      PriceHistoryData(
        item: PriceChangeItem.fromJson(
          Map<String, dynamic>.from(json['item'] as Map),
        ),
        history: (json['history'] as List)
            .map(
              (point) => PriceHistoryPoint.fromJson(
                Map<String, dynamic>.from(point as Map),
              ),
            )
            .toList(),
      );
}

class PriceIntelligenceRepository {
  PriceIntelligenceRepository(this.dio);
  final Dio dio;

  Future<PriceChangesData> changes({
    required String restaurantLocationId,
    required PriceChangeSort sort,
    int lookbackDays = 90,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final response = await dio.get(
      '/price-intelligence/changes',
      queryParameters: {
        'restaurantLocationId': restaurantLocationId,
        'lookbackDays': lookbackDays,
        'sort': sort.apiValue,
        if (startDate != null) 'startDate': startDate.toUtc().toIso8601String(),
        if (endDate != null) 'endDate': endDate.toUtc().toIso8601String(),
      },
    );
    return PriceChangesData.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<PriceHistoryData> history({
    required String restaurantLocationId,
    required String itemKey,
    int lookbackDays = 90,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final response = await dio.get(
      '/price-intelligence/items/$itemKey/history',
      queryParameters: {
        'restaurantLocationId': restaurantLocationId,
        'lookbackDays': lookbackDays,
        if (startDate != null) 'startDate': startDate.toUtc().toIso8601String(),
        if (endDate != null) 'endDate': endDate.toUtc().toIso8601String(),
      },
    );
    return PriceHistoryData.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}

final priceIntelligenceRepositoryProvider = Provider(
  (ref) => PriceIntelligenceRepository(ref.watch(api)),
);
final priceChangeSortProvider = StateProvider(
  (_) => PriceChangeSort.largestPercentIncrease,
);
final priceChangesProvider = FutureProvider<PriceChangesData>((ref) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) {
    return const PriceChangesData(items: [], lookbackDays: 90);
  }
  final range = ref.watch(dateRangeProvider);
  final lookbackDays = range.endDate.difference(range.startDate).inDays + 1;
  return ref
      .watch(priceIntelligenceRepositoryProvider)
      .changes(
        restaurantLocationId: location.id,
        sort: ref.watch(priceChangeSortProvider),
        lookbackDays: lookbackDays.clamp(30, 365).toInt(),
        startDate: range.startDate,
        endDate: range.endDate
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1)),
      );
});
final priceHistoryProvider = FutureProvider.family<PriceHistoryData, String>((
  ref,
  itemKey,
) async {
  final location = ref.watch(activeLocationProvider);
  final range = ref.watch(dateRangeProvider);
  if (location == null) throw StateError('No active restaurant location');
  return ref
      .watch(priceIntelligenceRepositoryProvider)
      .history(
        restaurantLocationId: location.id,
        itemKey: itemKey,
        lookbackDays: (range.endDate.difference(range.startDate).inDays + 1)
            .clamp(30, 365)
            .toInt(),
        startDate: range.startDate,
        endDate: range.endDate
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1)),
      );
});
