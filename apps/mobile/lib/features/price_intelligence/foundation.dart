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
  });

  final String vendorId, vendorName, itemKey, displayName, unit;
  final String? sku, packSize;
  final double previousUnitPrice, currentUnitPrice, absoluteChange;
  final double percentageChange;
  final double? typicalMonthlyQuantity;
  final double? estimatedMonthlyImpact, estimatedAnnualImpact;
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
        packSize: json['packSize'] as String?,
        previousUnitPrice: _number(json['previousUnitPrice']),
        currentUnitPrice: _number(json['currentUnitPrice']),
        absoluteChange: _number(json['absoluteChange']),
        percentageChange: _number(json['percentageChange']),
        typicalMonthlyQuantity: _optionalNumber(json['typicalMonthlyQuantity']),
        estimatedMonthlyImpact: _optionalNumber(json['estimatedMonthlyImpact']),
        estimatedAnnualImpact: _optionalNumber(json['estimatedAnnualImpact']),
        firstSeenAt: DateTime.parse(json['firstSeenAt'] as String),
        latestSeenAt: DateTime.parse(json['latestSeenAt'] as String),
      );
}

class PriceChangesData {
  const PriceChangesData({required this.items, required this.lookbackDays});
  final List<PriceChangeItem> items;
  final int lookbackDays;

  factory PriceChangesData.fromJson(
    Map<String, dynamic> json,
  ) => PriceChangesData(
    items: (json['items'] as List)
        .map(
          (item) =>
              PriceChangeItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    lookbackDays: json['lookbackDays'] as int,
  );
}

class PriceHistoryPoint {
  const PriceHistoryPoint({
    required this.date,
    required this.invoiceId,
    required this.unitPrice,
    this.quantity,
  });
  final DateTime date;
  final String invoiceId;
  final double unitPrice;
  final double? quantity;

  factory PriceHistoryPoint.fromJson(Map<String, dynamic> json) =>
      PriceHistoryPoint(
        date: DateTime.parse(json['date'] as String),
        invoiceId: json['invoiceId'] as String,
        unitPrice: _number(json['unitPrice']),
        quantity: _optionalNumber(json['quantity']),
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
  }) async {
    final response = await dio.get(
      '/price-intelligence/changes',
      queryParameters: {
        'restaurantLocationId': restaurantLocationId,
        'lookbackDays': 90,
        'sort': sort.apiValue,
      },
    );
    return PriceChangesData.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<PriceHistoryData> history({
    required String restaurantLocationId,
    required String itemKey,
  }) async {
    final response = await dio.get(
      '/price-intelligence/items/$itemKey/history',
      queryParameters: {
        'restaurantLocationId': restaurantLocationId,
        'lookbackDays': 90,
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
  return ref
      .watch(priceIntelligenceRepositoryProvider)
      .changes(
        restaurantLocationId: location.id,
        sort: ref.watch(priceChangeSortProvider),
      );
});
final priceHistoryProvider = FutureProvider.family<PriceHistoryData, String>((
  ref,
  itemKey,
) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) throw StateError('No active restaurant location');
  return ref
      .watch(priceIntelligenceRepositoryProvider)
      .history(restaurantLocationId: location.id, itemKey: itemKey);
});
