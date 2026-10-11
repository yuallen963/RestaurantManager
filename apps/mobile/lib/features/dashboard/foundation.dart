// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../main.dart' show api;

enum DatePreset { thisMonth, lastMonth, last30Days, custom }

class DateRangeState {
  const DateRangeState(this.preset, this.startDate, this.endDate);
  final DatePreset preset;
  final DateTime startDate, endDate;
  static DateRangeState resolve(
    DatePreset preset, {
    DateTime? now,
    DateTime? start,
    DateTime? end,
  }) {
    final d = now ?? DateTime.now();
    final today = DateTime(d.year, d.month, d.day);
    if (preset == DatePreset.thisMonth)
      return DateRangeState(preset, DateTime(d.year, d.month), today);
    if (preset == DatePreset.lastMonth)
      return DateRangeState(
        preset,
        DateTime(d.year, d.month - 1),
        DateTime(d.year, d.month).subtract(const Duration(days: 1)),
      );
    if (preset == DatePreset.last30Days)
      return DateRangeState(
        preset,
        today.subtract(const Duration(days: 29)),
        today,
      );
    return DateRangeState(preset, start!, end!);
  }

  DateRangeState previous() => DateRangeState(
    DatePreset.custom,
    startDate.subtract(
      Duration(days: endDate.difference(startDate).inDays + 1),
    ),
    startDate.subtract(const Duration(days: 1)),
  );
}

class RestaurantLocation {
  const RestaurantLocation({
    required this.id,
    required this.name,
    required this.organizationId,
  });
  final String id, name, organizationId;
  factory RestaurantLocation.fromJson(Map<String, dynamic> j) =>
      RestaurantLocation(
        id: j['id'] as String,
        name: j['name'] as String,
        organizationId: j['organizationId'] as String,
      );
}

double _number(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.parse(value);
  throw FormatException('Missing numeric $key');
}

double _optionalNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

class DashboardSummary {
  const DashboardSummary(
    this.revenue,
    this.expenses,
    this.estimatedProfit,
    this.profitMargin,
    this.foodCost,
    this.foodCostPercentage,
    this.laborCost,
    this.laborCostPercentage,
  );
  final double revenue,
      expenses,
      estimatedProfit,
      profitMargin,
      foodCost,
      foodCostPercentage,
      laborCost,
      laborCostPercentage;
  factory DashboardSummary.fromJson(Map<String, dynamic> j) => DashboardSummary(
    _number(j, 'revenue'),
    _number(j, 'expenses'),
    _number(j, 'estimatedProfit'),
    _number(j, 'profitMargin'),
    _number(j, 'foodCost'),
    _number(j, 'foodCostPercentage'),
    _number(j, 'laborCost'),
    _number(j, 'laborCostPercentage'),
  );
}

class ExpenseBreakdown {
  const ExpenseBreakdown(
    this.categoryId,
    this.categoryName,
    this.amount,
    this.percentageOfExpenses,
  );
  final String categoryId, categoryName;
  final double amount, percentageOfExpenses;
  factory ExpenseBreakdown.fromJson(Map<String, dynamic> j) => ExpenseBreakdown(
    j['categoryId'] as String,
    j['categoryName'] as String,
    _number(j, 'amount'),
    _number(j, 'percentageOfExpenses'),
  );
}

class DashboardAvailability {
  const DashboardAvailability({
    required this.bank,
    required this.reviewedInvoices,
    required this.revenue,
    required this.pos,
    required this.expenses,
    required this.profitability,
  });
  final bool bank, reviewedInvoices, revenue, pos, expenses, profitability;

  factory DashboardAvailability.fromJson(Map<String, dynamic> j) =>
      DashboardAvailability(
        bank: j['bank'] == true,
        reviewedInvoices: j['reviewedInvoices'] == true,
        revenue: j['revenue'] == true,
        pos: j['pos'] == true,
        expenses: j['expenses'] == true,
        profitability: j['profitability'] == true,
      );
}

class NamedAmount {
  const NamedAmount(this.name, this.amount);
  final String name;
  final double amount;
  factory NamedAmount.fromJson(Map<String, dynamic> j) =>
      NamedAmount(j['name'] as String, _number(j, 'amount'));
}

class LargestExpense {
  const LargestExpense(this.id, this.name, this.amount);
  final String id, name;
  final double amount;
  factory LargestExpense.fromJson(Map<String, dynamic> j) => LargestExpense(
    j['id'] as String,
    j['name'] as String,
    _number(j, 'amount'),
  );
}

class BankDashboardInsights {
  const BankDashboardInsights({
    required this.trackedOutflows,
    required this.previousTrackedOutflows,
    required this.uncategorizedCount,
    required this.unmatchedCount,
    required this.matchedInvoiceCount,
    required this.categoryBreakdown,
    required this.topVendors,
    required this.largestExpenses,
  });
  final double trackedOutflows, previousTrackedOutflows;
  final int uncategorizedCount, unmatchedCount, matchedInvoiceCount;
  final List<NamedAmount> categoryBreakdown, topVendors;
  final List<LargestExpense> largestExpenses;

  factory BankDashboardInsights.fromJson(Map<String, dynamic> j) =>
      BankDashboardInsights(
        trackedOutflows: _number(j, 'trackedOutflows'),
        previousTrackedOutflows: _number(j, 'previousTrackedOutflows'),
        uncategorizedCount: j['uncategorizedCount'] as int,
        unmatchedCount: j['unmatchedCount'] as int,
        matchedInvoiceCount: j['matchedInvoiceCount'] as int,
        categoryBreakdown: _namedAmounts(j['categoryBreakdown']),
        topVendors: _namedAmounts(j['topVendors']),
        largestExpenses: (j['largestExpenses'] as List)
            .map((e) => LargestExpense.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class InvoiceDashboardInsights {
  const InvoiceDashboardInsights({
    required this.reviewedPurchases,
    this.previousReviewedPurchases = 0,
    required this.reviewedCount,
    required this.requiringReviewCount,
    required this.unmatchedCount,
    required this.topVendors,
  });
  final double reviewedPurchases, previousReviewedPurchases;
  final int reviewedCount, requiringReviewCount, unmatchedCount;
  final List<NamedAmount> topVendors;

  factory InvoiceDashboardInsights.fromJson(Map<String, dynamic> j) =>
      InvoiceDashboardInsights(
        reviewedPurchases: _number(j, 'reviewedPurchases'),
        previousReviewedPurchases: _optionalNumber(
          j,
          'previousReviewedPurchases',
        ),
        reviewedCount: j['reviewedCount'] as int,
        requiringReviewCount: j['requiringReviewCount'] as int,
        unmatchedCount: j['unmatchedCount'] as int,
        topVendors: _namedAmounts(j['topVendors']),
      );
}

List<NamedAmount> _namedAmounts(dynamic value) => (value as List)
    .map((e) => NamedAmount.fromJson(Map<String, dynamic>.from(e)))
    .toList();

class DashboardData {
  const DashboardData(
    this.summary,
    this.breakdown, {
    this.availability = const DashboardAvailability(
      bank: true,
      reviewedInvoices: true,
      revenue: true,
      pos: true,
      expenses: true,
      profitability: true,
    ),
    this.bank,
    this.invoices,
  });
  final DashboardSummary summary;
  final List<ExpenseBreakdown> breakdown;
  final DashboardAvailability availability;
  final BankDashboardInsights? bank;
  final InvoiceDashboardInsights? invoices;
  factory DashboardData.fromJson(Map<String, dynamic> j) => DashboardData(
    DashboardSummary.fromJson(Map<String, dynamic>.from(j['summary'])),
    (j['expenseBreakdown'] as List)
        .map((e) => ExpenseBreakdown.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    availability: j['availability'] == null
        ? const DashboardAvailability(
            bank: true,
            reviewedInvoices: true,
            revenue: true,
            pos: true,
            expenses: true,
            profitability: true,
          )
        : DashboardAvailability.fromJson(
            Map<String, dynamic>.from(j['availability']),
          ),
    bank: j['bank'] == null
        ? null
        : BankDashboardInsights.fromJson(Map<String, dynamic>.from(j['bank'])),
    invoices: j['invoices'] == null
        ? null
        : InvoiceDashboardInsights.fromJson(
            Map<String, dynamic>.from(j['invoices']),
          ),
  );
}

class LocationsRepository {
  LocationsRepository(this.dio);
  final Dio dio;
  Future<List<RestaurantLocation>> list(String organizationId) async =>
      (await dio.get('/organizations/$organizationId/locations')).data
          .map<RestaurantLocation>(
            (e) => RestaurantLocation.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
}

class DashboardRepository {
  DashboardRepository(this.dio);
  final Dio dio;
  Future<DashboardData> get(String locationId, DateRangeState range) async {
    const path = '/dashboard';
    final query = <String, dynamic>{
      'restaurantLocationId': locationId,
      'startDate': range.startDate.toIso8601String(),
      'endDate': range.endDate.toIso8601String(),
    };
    final baseUri = Uri.parse(dio.options.baseUrl);
    final requestUri = baseUri.replace(
      path: '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
      queryParameters: query.map((key, value) => MapEntry(key, '$value')),
    );

    if (kDebugMode) {
      debugPrint('[DEV] Loading dashboard');
      debugPrint('[DEV] Dashboard URL: $requestUri');
      debugPrint('[DEV] Dashboard restaurantLocationId: $locationId');
      debugPrint('[DEV] Dashboard startDate: ${query['startDate']}');
      debugPrint('[DEV] Dashboard endDate: ${query['endDate']}');
    }

    try {
      final r = await dio.get(path, queryParameters: query);
      if (kDebugMode) {
        debugPrint('[DEV] Dashboard HTTP status: ${r.statusCode}');
        final body = r.data;
        debugPrint(
          '[DEV] Dashboard response shape: ${body is Map ? 'object keys: ${body.keys.join(', ')}' : body.runtimeType}',
        );
      }
      final body = Map<String, dynamic>.from(r.data as Map);
      final dashboard = DashboardData.fromJson(body);
      if (kDebugMode) debugPrint('[DEV] Dashboard loaded');
      return dashboard;
    } on DioException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[DEV] Dashboard DioException status: ${error.response?.statusCode}',
        );
        debugPrint(
          '[DEV] Dashboard DioException body: ${error.response?.data}',
        );
        debugPrint('[DEV] Dashboard DioException: ${error.message}');
      }
      rethrow;
    } on FormatException catch (error) {
      if (kDebugMode) debugPrint('[DEV] Dashboard parsing error: $error');
      rethrow;
    }
  }
}

final dateRangeProvider = StateProvider<DateRangeState>(
  (_) => DateRangeState.resolve(DatePreset.thisMonth),
);
final locationsRepositoryProvider = Provider(
  (ref) => LocationsRepository(ref.watch(api)),
);
final dashboardRepositoryProvider = Provider(
  (ref) => DashboardRepository(ref.watch(api)),
);
const _locationKey = 'activeRestaurantLocationId';
final locationStorageProvider = Provider((_) => const FlutterSecureStorage());

class ActiveLocationState {
  const ActiveLocationState(this.locations, this.active);
  final List<RestaurantLocation> locations;
  final RestaurantLocation? active;
}

class ActiveLocationController extends AsyncNotifier<ActiveLocationState> {
  @override
  Future<ActiveLocationState> build() async {
    final dio = ref.read(api);
    if (kDebugMode)
      debugPrint(
        '[DEV] Loading organizations; Authorization header present: ${dio.options.headers['Authorization'] != null}',
      );
    final organizations = await dio.get('/organizations');
    final orgs = organizations.data as List;
    if (kDebugMode) debugPrint('[DEV] Organizations loaded: ${orgs.length}');
    if (orgs.isEmpty) return const ActiveLocationState([], null);
    if (kDebugMode) debugPrint('[DEV] Loading locations');
    final locations = await ref
        .read(locationsRepositoryProvider)
        .list(orgs.first['id'] as String);
    if (kDebugMode) debugPrint('[DEV] Locations loaded: ${locations.length}');
    final saved = await ref
        .read(locationStorageProvider)
        .read(key: _locationKey);
    final active =
        locations.where((l) => l.id == saved).firstOrNull ??
        (locations.isEmpty ? null : locations.first);
    if (active != null)
      await ref
          .read(locationStorageProvider)
          .write(key: _locationKey, value: active.id);
    if (kDebugMode)
      debugPrint('[DEV] Active location: ${active?.name ?? 'none'}');
    return ActiveLocationState(locations, active);
  }

  Future<void> select(RestaurantLocation location) async {
    final current = state.valueOrNull;
    if (current == null || !current.locations.any((l) => l.id == location.id))
      throw StateError('Location is not accessible');
    await ref
        .read(locationStorageProvider)
        .write(key: _locationKey, value: location.id);
    state = AsyncData(ActiveLocationState(current.locations, location));
  }

  void clear() {
    state = const AsyncData(ActiveLocationState([], null));
  }
}

final activeLocationControllerProvider =
    AsyncNotifierProvider<ActiveLocationController, ActiveLocationState>(
      ActiveLocationController.new,
    );
final activeLocationStateProvider = Provider<AsyncValue<ActiveLocationState>>(
  (ref) => ref.watch(activeLocationControllerProvider),
);
final activeLocationProvider = Provider<RestaurantLocation?>(
  (ref) => ref.watch(activeLocationStateProvider).valueOrNull?.active,
);
final availableLocationsProvider = Provider<List<RestaurantLocation>>(
  (ref) => ref.watch(activeLocationStateProvider).valueOrNull?.locations ?? [],
);
final dashboardProvider = FutureProvider<DashboardData?>((ref) async {
  final l = ref.watch(activeLocationProvider);
  if (l == null) return null;
  return ref
      .watch(dashboardRepositoryProvider)
      .get(l.id, ref.watch(dateRangeProvider));
});
final previousDashboardProvider = FutureProvider<DashboardData?>((ref) async {
  final l = ref.watch(activeLocationProvider);
  if (l == null) return null;
  final range = ref.watch(dateRangeProvider).previous();
  return ref.watch(dashboardRepositoryProvider).get(l.id, range);
});
