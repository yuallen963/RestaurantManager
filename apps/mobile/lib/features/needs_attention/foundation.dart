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

enum AttentionSeverity { low, medium, high, critical }

enum AttentionActionType {
  openPriceHistory,
  openDashboardCost,
  openVendor,
  openExpenseCategory,
}

AttentionSeverity _severity(String value) => AttentionSeverity.values
    .firstWhere((item) => item.name.toUpperCase() == value);

AttentionActionType _action(String value) => switch (value) {
  'OPEN_PRICE_HISTORY' => AttentionActionType.openPriceHistory,
  'OPEN_DASHBOARD_COST' => AttentionActionType.openDashboardCost,
  'OPEN_VENDOR' => AttentionActionType.openVendor,
  'OPEN_EXPENSE_CATEGORY' => AttentionActionType.openExpenseCategory,
  _ => throw FormatException('Unknown attention action $value'),
};

class AttentionAction {
  const AttentionAction({required this.type, required this.targetId});
  final AttentionActionType type;
  final String targetId;

  factory AttentionAction.fromJson(Map<String, dynamic> json) =>
      AttentionAction(
        type: _action(json['type'] as String),
        targetId: json['targetId'] as String,
      );
}

class AttentionItem {
  const AttentionItem({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.currentValue,
    required this.previousValue,
    required this.message,
    required this.occurredAt,
    required this.action,
    this.subtitle,
    this.percentageChange,
    this.percentagePointChange,
    this.estimatedMonthlyImpact,
  });

  final String id, type, title, message;
  final String? subtitle;
  final AttentionSeverity severity;
  final double currentValue, previousValue;
  final double? percentageChange, percentagePointChange;
  final double? estimatedMonthlyImpact;
  final DateTime occurredAt;
  final AttentionAction action;

  factory AttentionItem.fromJson(Map<String, dynamic> json) => AttentionItem(
    id: json['id'] as String,
    type: json['type'] as String,
    severity: _severity(json['severity'] as String),
    title: json['title'] as String,
    subtitle: json['subtitle'] as String?,
    currentValue: _number(json['currentValue']),
    previousValue: _number(json['previousValue']),
    percentageChange: _optionalNumber(json['percentageChange']),
    percentagePointChange: _optionalNumber(json['percentagePointChange']),
    estimatedMonthlyImpact: _optionalNumber(json['estimatedMonthlyImpact']),
    message: json['message'] as String,
    occurredAt: DateTime.parse(json['occurredAt'] as String),
    action: AttentionAction.fromJson(
      Map<String, dynamic>.from(json['action'] as Map),
    ),
  );
}

class AttentionSummary {
  const AttentionSummary({
    required this.critical,
    required this.high,
    required this.medium,
    required this.low,
    required this.estimatedMonthlyImpact,
  });
  final int critical, high, medium, low;
  final double estimatedMonthlyImpact;
  int get total => critical + high + medium + low;

  factory AttentionSummary.fromJson(Map<String, dynamic> json) =>
      AttentionSummary(
        critical: json['critical'] as int,
        high: json['high'] as int,
        medium: json['medium'] as int,
        low: json['low'] as int,
        estimatedMonthlyImpact: _number(json['estimatedMonthlyImpact']),
      );
}

class NeedsAttentionData {
  const NeedsAttentionData({required this.summary, required this.items});
  final AttentionSummary summary;
  final List<AttentionItem> items;

  factory NeedsAttentionData.fromJson(Map<String, dynamic> json) =>
      NeedsAttentionData(
        summary: AttentionSummary.fromJson(
          Map<String, dynamic>.from(json['summary'] as Map),
        ),
        items: (json['items'] as List)
            .map(
              (item) => AttentionItem.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
      );
}

class NeedsAttentionRepository {
  NeedsAttentionRepository(this.dio);
  final Dio dio;

  Future<NeedsAttentionData> get(
    String locationId,
    DateRangeState range,
  ) async {
    final response = await dio.get(
      '/needs-attention',
      queryParameters: {
        'restaurantLocationId': locationId,
        'startDate': range.startDate.toIso8601String(),
        'endDate': range.endDate.toIso8601String(),
      },
    );
    return NeedsAttentionData.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}

final needsAttentionRepositoryProvider = Provider(
  (ref) => NeedsAttentionRepository(ref.watch(api)),
);
final needsAttentionProvider = FutureProvider<NeedsAttentionData>((ref) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) {
    return const NeedsAttentionData(
      summary: AttentionSummary(
        critical: 0,
        high: 0,
        medium: 0,
        low: 0,
        estimatedMonthlyImpact: 0,
      ),
      items: [],
    );
  }
  return ref
      .watch(needsAttentionRepositoryProvider)
      .get(location.id, ref.watch(dateRangeProvider));
});
