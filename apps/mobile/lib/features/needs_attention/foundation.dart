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
  openInvoice,
  openBankTransaction,
}

enum AttentionStatus { active, reviewed, resolved, dismissed }

AttentionSeverity _severity(String value) => AttentionSeverity.values
    .firstWhere((item) => item.name.toUpperCase() == value);

AttentionActionType _action(String value) => switch (value) {
  'OPEN_PRICE_HISTORY' => AttentionActionType.openPriceHistory,
  'OPEN_DASHBOARD_COST' => AttentionActionType.openDashboardCost,
  'OPEN_VENDOR' => AttentionActionType.openVendor,
  'OPEN_EXPENSE_CATEGORY' => AttentionActionType.openExpenseCategory,
  'OPEN_INVOICE' => AttentionActionType.openInvoice,
  'OPEN_BANK_TRANSACTION' => AttentionActionType.openBankTransaction,
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
    this.whyItMatters,
    this.nextStep,
    this.evidence = const [],
    this.status = AttentionStatus.active,
  });

  final String id, type, title, message;
  final String? subtitle;
  final AttentionSeverity severity;
  final double currentValue, previousValue;
  final double? percentageChange, percentagePointChange;
  final double? estimatedMonthlyImpact;
  final String? whyItMatters, nextStep;
  final List<AttentionEvidence> evidence;
  final AttentionStatus status;
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
    whyItMatters: json['whyItMatters'] as String?,
    nextStep: json['nextStep'] as String?,
    evidence: (json['evidence'] as List? ?? const [])
        .map(
          (value) =>
              AttentionEvidence.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList(),
    status: AttentionStatus.values.firstWhere(
      (status) =>
          status.name.toUpperCase() == (json['status'] as String? ?? 'ACTIVE'),
    ),
    message: json['message'] as String,
    occurredAt: DateTime.parse(json['occurredAt'] as String),
    action: AttentionAction.fromJson(
      Map<String, dynamic>.from(json['action'] as Map),
    ),
  );
}

class AttentionEvidence {
  const AttentionEvidence({
    required this.label,
    required this.value,
    this.recordId,
  });
  final String label, value;
  final String? recordId;
  factory AttentionEvidence.fromJson(Map<String, dynamic> json) =>
      AttentionEvidence(
        label: json['label'] as String,
        value: json['value'] as String,
        recordId: json['recordId'] as String?,
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

  Future<void> updateStatus(String id, AttentionStatus status) async {
    await dio.patch(
      '/needs-attention/$id/status',
      data: {'status': status.name.toUpperCase()},
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
