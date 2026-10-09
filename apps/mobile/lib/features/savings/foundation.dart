import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show api;
import '../dashboard/foundation.dart';

double _number(dynamic value) =>
    value is num ? value.toDouble() : double.parse(value as String);

class SavingsVendor {
  const SavingsVendor({
    required this.id,
    required this.name,
    required this.unitPrice,
  });
  final String id, name;
  final double unitPrice;
  factory SavingsVendor.fromJson(Map<String, dynamic> json) => SavingsVendor(
    id: json['id'] as String,
    name: json['name'] as String,
    unitPrice: _number(json['unitPrice']),
  );
}

class SavingsEvidence {
  const SavingsEvidence({
    required this.invoiceId,
    required this.vendorName,
    required this.date,
    required this.unitPrice,
    required this.quantity,
  });
  final String invoiceId, vendorName;
  final DateTime date;
  final double unitPrice, quantity;
  factory SavingsEvidence.fromJson(Map<String, dynamic> json) =>
      SavingsEvidence(
        invoiceId: json['invoiceId'] as String,
        vendorName: json['vendorName'] as String,
        date: DateTime.parse(json['date'] as String),
        unitPrice: _number(json['unitPrice']),
        quantity: _number(json['quantity']),
      );
}

class SavingsOpportunity {
  const SavingsOpportunity({
    required this.productGroupId,
    required this.productName,
    required this.currentVendor,
    required this.lowerCostVendor,
    required this.unit,
    required this.packSize,
    required this.absoluteDifference,
    required this.percentageDifference,
    required this.typicalMonthlyQuantity,
    required this.estimatedMonthlySavings,
    required this.estimatedAnnualSavings,
    required this.latestHigherPriceDate,
    required this.latestLowerPriceDate,
    required this.evidence,
  });
  final String productGroupId, productName, unit, packSize;
  final SavingsVendor currentVendor, lowerCostVendor;
  final double absoluteDifference,
      percentageDifference,
      typicalMonthlyQuantity,
      estimatedMonthlySavings,
      estimatedAnnualSavings;
  final DateTime latestHigherPriceDate, latestLowerPriceDate;
  final List<SavingsEvidence> evidence;
  factory SavingsOpportunity.fromJson(Map<String, dynamic> json) =>
      SavingsOpportunity(
        productGroupId: json['productGroupId'] as String,
        productName: json['productName'] as String,
        currentVendor: SavingsVendor.fromJson(
          Map<String, dynamic>.from(json['currentVendor'] as Map),
        ),
        lowerCostVendor: SavingsVendor.fromJson(
          Map<String, dynamic>.from(json['lowerCostVendor'] as Map),
        ),
        unit: json['unit'] as String,
        packSize: json['packSize'] as String,
        absoluteDifference: _number(json['absoluteDifference']),
        percentageDifference: _number(json['percentageDifference']),
        typicalMonthlyQuantity: _number(json['typicalMonthlyQuantity']),
        estimatedMonthlySavings: _number(json['estimatedMonthlySavings']),
        estimatedAnnualSavings: _number(json['estimatedAnnualSavings']),
        latestHigherPriceDate: DateTime.parse(
          json['latestHigherPriceDate'] as String,
        ),
        latestLowerPriceDate: DateTime.parse(
          json['latestLowerPriceDate'] as String,
        ),
        evidence: (json['evidence'] as List)
            .map(
              (row) => SavingsEvidence.fromJson(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList(),
      );
}

class SavingsData {
  const SavingsData({
    required this.opportunityCount,
    required this.estimatedMonthlySavings,
    required this.estimatedAnnualSavings,
    required this.items,
    required this.lookbackDays,
  });
  final int opportunityCount, lookbackDays;
  final double estimatedMonthlySavings, estimatedAnnualSavings;
  final List<SavingsOpportunity> items;
  factory SavingsData.fromJson(Map<String, dynamic> json) {
    final summary = Map<String, dynamic>.from(json['summary'] as Map);
    return SavingsData(
      opportunityCount: summary['opportunityCount'] as int,
      estimatedMonthlySavings: _number(summary['estimatedMonthlySavings']),
      estimatedAnnualSavings: _number(summary['estimatedAnnualSavings']),
      items: (json['items'] as List)
          .map(
            (item) => SavingsOpportunity.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      lookbackDays: json['lookbackDays'] as int,
    );
  }
}

class SavingsRepository {
  SavingsRepository(this.dio);
  final Dio dio;
  Future<SavingsData> get(String restaurantLocationId) async {
    final response = await dio.get(
      '/savings-opportunities',
      queryParameters: {
        'restaurantLocationId': restaurantLocationId,
        'lookbackDays': 90,
      },
    );
    return SavingsData.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}

final savingsRepositoryProvider = Provider(
  (ref) => SavingsRepository(ref.watch(api)),
);
final savingsOpportunitiesProvider = FutureProvider<SavingsData>((ref) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) {
    return const SavingsData(
      opportunityCount: 0,
      estimatedMonthlySavings: 0,
      estimatedAnnualSavings: 0,
      items: [],
      lookbackDays: 90,
    );
  }
  return ref.watch(savingsRepositoryProvider).get(location.id);
});
