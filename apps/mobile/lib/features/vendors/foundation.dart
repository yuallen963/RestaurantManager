// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart' show api;
import '../dashboard/foundation.dart';

double _number(dynamic value) =>
    value is num ? value.toDouble() : double.parse(value as String);

enum VendorSort {
  highestSpend,
  lowestSpend,
  largestIncrease,
  mostTransactions,
  alphabetical,
}

extension VendorSortLabel on VendorSort {
  String get label => switch (this) {
    VendorSort.highestSpend => 'Highest Spend',
    VendorSort.lowestSpend => 'Lowest Spend',
    VendorSort.largestIncrease => 'Largest Increase',
    VendorSort.mostTransactions => 'Most Transactions',
    VendorSort.alphabetical => 'Alphabetical',
  };
}

class VendorSummary {
  const VendorSummary({
    required this.id,
    required this.name,
    required this.currentSpend,
    required this.previousSpend,
    required this.transactionCount,
    this.percentageChange,
    this.lastPurchaseDate,
  });
  final String id, name;
  final double currentSpend, previousSpend;
  final double? percentageChange;
  final int transactionCount;
  final DateTime? lastPurchaseDate;
  factory VendorSummary.fromJson(Map<String, dynamic> json) => VendorSummary(
    id: json['id'] as String,
    name: json['name'] as String,
    currentSpend: _number(json['currentSpend']),
    previousSpend: _number(json['previousSpend']),
    percentageChange: json['percentageChange'] == null
        ? null
        : _number(json['percentageChange']),
    transactionCount: json['transactionCount'] as int,
    lastPurchaseDate: json['lastPurchaseDate'] == null
        ? null
        : DateTime.parse(json['lastPurchaseDate'] as String),
  );
}

class VendorPagination {
  const VendorPagination(this.page, this.totalItems, this.hasMore);
  final int page, totalItems;
  final bool hasMore;
  factory VendorPagination.fromJson(Map<String, dynamic> json) =>
      VendorPagination(
        json['page'] as int,
        json['totalItems'] as int,
        json['hasMore'] as bool,
      );
}

class VendorPage {
  const VendorPage(this.items, this.pagination);
  final List<VendorSummary> items;
  final VendorPagination pagination;
  factory VendorPage.fromJson(Map<String, dynamic> json) => VendorPage(
    (json['items'] as List)
        .map(
          (item) =>
              VendorSummary.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    VendorPagination.fromJson(
      Map<String, dynamic>.from(json['pagination'] as Map),
    ),
  );
}

class VendorFilters {
  const VendorFilters({this.search = '', this.sort = VendorSort.highestSpend});
  final String search;
  final VendorSort sort;
  VendorFilters copyWith({String? search, VendorSort? sort}) =>
      VendorFilters(search: search ?? this.search, sort: sort ?? this.sort);
}

class VendorListState {
  const VendorListState(
    this.items,
    this.pagination, {
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
  });
  final List<VendorSummary> items;
  final VendorPagination pagination;
  final bool isLoadingMore, loadMoreFailed;
  VendorListState copyWith({
    List<VendorSummary>? items,
    VendorPagination? pagination,
    bool? isLoadingMore,
    bool? loadMoreFailed,
  }) => VendorListState(
    items ?? this.items,
    pagination ?? this.pagination,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );
}

class VendorExpense {
  const VendorExpense(
    this.id,
    this.date,
    this.description,
    this.category,
    this.amount,
  );
  final String id, category;
  final DateTime date;
  final String? description;
  final double amount;
  factory VendorExpense.fromJson(Map<String, dynamic> json) => VendorExpense(
    json['id'] as String,
    DateTime.parse(json['date'] as String),
    json['description'] as String?,
    json['categoryName'] as String,
    _number(json['amount']),
  );
}

class VendorTrendPoint {
  const VendorTrendPoint(this.date, this.amount);
  final DateTime date;
  final double amount;
  factory VendorTrendPoint.fromJson(Map<String, dynamic> json) =>
      VendorTrendPoint(
        DateTime.parse(json['date'] as String),
        _number(json['amount']),
      );
}

class VendorDetail {
  const VendorDetail({
    required this.vendor,
    required this.averageTransaction,
    required this.trend,
    required this.recentExpenses,
  });
  final VendorSummary vendor;
  final double averageTransaction;
  final List<VendorTrendPoint> trend;
  final List<VendorExpense> recentExpenses;
  factory VendorDetail.fromJson(Map<String, dynamic> json) {
    final vendor = Map<String, dynamic>.from(json['vendor'] as Map),
        summary = Map<String, dynamic>.from(json['summary'] as Map);
    return VendorDetail(
      vendor: VendorSummary(
        id: vendor['id'] as String,
        name: vendor['name'] as String,
        currentSpend: _number(summary['currentSpend']),
        previousSpend: _number(summary['previousSpend']),
        percentageChange: summary['percentageChange'] == null
            ? null
            : _number(summary['percentageChange']),
        transactionCount: summary['transactionCount'] as int,
        lastPurchaseDate: summary['lastPurchaseDate'] == null
            ? null
            : DateTime.parse(summary['lastPurchaseDate'] as String),
      ),
      averageTransaction: _number(summary['averageTransaction']),
      trend: (json['trend'] as List)
          .map(
            (item) => VendorTrendPoint.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      recentExpenses: (json['recentExpenses'] as List)
          .map(
            (item) =>
                VendorExpense.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }
}

class VendorRepository {
  VendorRepository(this.dio);
  final Dio dio;
  Future<VendorPage> list({
    required String locationId,
    required DateRangeState range,
    required VendorFilters filters,
    required int page,
    int limit = 25,
  }) async {
    final response = await dio.get(
      '/vendor-summaries',
      queryParameters: {
        'restaurantLocationId': locationId,
        'startDate': range.startDate.toIso8601String(),
        'endDate': range.endDate.toIso8601String(),
        'page': page,
        'limit': limit,
        'sort': filters.sort.name,
        if (filters.search.trim().isNotEmpty) 'search': filters.search.trim(),
      },
    );
    return VendorPage.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<VendorDetail> detail(
    String id,
    String locationId,
    DateRangeState range,
  ) async {
    final response = await dio.get(
      '/vendor-summaries/$id',
      queryParameters: {
        'restaurantLocationId': locationId,
        'startDate': range.startDate.toIso8601String(),
        'endDate': range.endDate.toIso8601String(),
      },
    );
    return VendorDetail.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}

final vendorRepositoryProvider = Provider(
  (ref) => VendorRepository(ref.watch(api)),
);
final vendorFiltersProvider = StateProvider((_) => const VendorFilters());
final vendorDetailProvider = FutureProvider.family<VendorDetail, String>((
  ref,
  id,
) {
  final location = ref.watch(activeLocationProvider);
  if (location == null) throw StateError('No active restaurant location');
  return ref
      .watch(vendorRepositoryProvider)
      .detail(id, location.id, ref.watch(dateRangeProvider));
});

class VendorListController extends AsyncNotifier<VendorListState> {
  late RestaurantLocation _location;
  late DateRangeState _range;
  late VendorFilters _filters;
  @override
  Future<VendorListState> build() async {
    final location = ref.watch(activeLocationProvider);
    if (location == null) throw StateError('No active restaurant location');
    _location = location;
    _range = ref.watch(dateRangeProvider);
    _filters = ref.watch(vendorFiltersProvider);
    final page = await ref
        .watch(vendorRepositoryProvider)
        .list(
          locationId: _location.id,
          range: _range,
          filters: _filters,
          page: 1,
        );
    return VendorListState(page.items, page.pagination);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.isLoadingMore || !current.pagination.hasMore)
      return;
    state = AsyncData(
      current.copyWith(isLoadingMore: true, loadMoreFailed: false),
    );
    try {
      final page = await ref
          .read(vendorRepositoryProvider)
          .list(
            locationId: _location.id,
            range: _range,
            filters: _filters,
            page: current.pagination.page + 1,
          );
      final ids = current.items.map((item) => item.id).toSet();
      state = AsyncData(
        VendorListState([
          ...current.items,
          ...page.items.where((item) => ids.add(item.id)),
        ], page.pagination),
      );
    } catch (_) {
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }
}

final vendorListProvider =
    AsyncNotifierProvider<VendorListController, VendorListState>(
      VendorListController.new,
    );
