import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show api;
import '../dashboard/foundation.dart';

enum ExpenseSort { newest, oldest, highestAmount, lowestAmount }

extension ExpenseSortLabel on ExpenseSort {
  String get label => switch (this) {
    ExpenseSort.newest => 'Newest',
    ExpenseSort.oldest => 'Oldest',
    ExpenseSort.highestAmount => 'Highest Amount',
    ExpenseSort.lowestAmount => 'Lowest Amount',
  };

  String get apiValue => switch (this) {
    ExpenseSort.newest => 'newest',
    ExpenseSort.oldest => 'oldest',
    ExpenseSort.highestAmount => 'highestAmount',
    ExpenseSort.lowestAmount => 'lowestAmount',
  };
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.parse(value);
  throw const FormatException('Expected numeric value');
}

class ExpenseRecord {
  const ExpenseRecord({
    required this.id,
    required this.restaurantLocationId,
    required this.expenseCategoryId,
    required this.date,
    required this.amount,
    required this.source,
    this.vendorId,
    this.description,
    this.notes,
  });

  final String id;
  final String restaurantLocationId;
  final String expenseCategoryId;
  final String? vendorId;
  final DateTime date;
  final double amount;
  final String? description;
  final String? notes;
  final String source;

  factory ExpenseRecord.fromJson(Map<String, dynamic> json) => ExpenseRecord(
    id: json['id'] as String,
    restaurantLocationId: json['restaurantLocationId'] as String,
    expenseCategoryId: json['expenseCategoryId'] as String,
    vendorId: json['vendorId'] as String?,
    date: DateTime.parse(json['date'] as String),
    amount: _number(json['amount']),
    description: json['description'] as String?,
    notes: json['notes'] as String?,
    source: json['source'] as String? ?? 'UNKNOWN',
  );
}

class ExpenseCategoryOption {
  const ExpenseCategoryOption({required this.id, required this.name});
  final String id;
  final String name;
  factory ExpenseCategoryOption.fromJson(Map<String, dynamic> json) =>
      ExpenseCategoryOption(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

class ExpenseVendorOption {
  const ExpenseVendorOption({required this.id, required this.name});
  final String id;
  final String name;
  factory ExpenseVendorOption.fromJson(Map<String, dynamic> json) =>
      ExpenseVendorOption(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

class ExpenseLookups {
  const ExpenseLookups(this.categories, this.vendors);
  final List<ExpenseCategoryOption> categories;
  final List<ExpenseVendorOption> vendors;

  String categoryName(String id) =>
      categories
          .where((category) => category.id == id)
          .map((category) => category.name)
          .firstOrNull ??
      'Unknown category';

  String? vendorName(String? id) => id == null
      ? null
      : vendors
            .where((vendor) => vendor.id == id)
            .map((vendor) => vendor.name)
            .firstOrNull;
}

class ExpenseFilters {
  const ExpenseFilters({
    this.search = '',
    this.categoryId,
    this.vendorId,
    this.sort = ExpenseSort.newest,
  });

  static const _unchanged = Object();
  final String search;
  final String? categoryId;
  final String? vendorId;
  final ExpenseSort sort;

  bool get isFiltered =>
      search.trim().isNotEmpty || categoryId != null || vendorId != null;

  ExpenseFilters copyWith({
    String? search,
    Object? categoryId = _unchanged,
    Object? vendorId = _unchanged,
    ExpenseSort? sort,
  }) => ExpenseFilters(
    search: search ?? this.search,
    categoryId: identical(categoryId, _unchanged)
        ? this.categoryId
        : categoryId as String?,
    vendorId: identical(vendorId, _unchanged)
        ? this.vendorId
        : vendorId as String?,
    sort: sort ?? this.sort,
  );
}

class ExpensePagination {
  const ExpensePagination({
    required this.page,
    required this.limit,
    required this.totalItems,
    required this.totalPages,
    required this.hasMore,
  });

  final int page;
  final int limit;
  final int totalItems;
  final int totalPages;
  final bool hasMore;

  factory ExpensePagination.fromJson(Map<String, dynamic> json) =>
      ExpensePagination(
        page: json['page'] as int,
        limit: json['limit'] as int,
        totalItems: json['totalItems'] as int,
        totalPages: json['totalPages'] as int,
        hasMore: json['hasMore'] as bool,
      );
}

class ExpensePage {
  const ExpensePage({
    required this.items,
    required this.pagination,
    required this.totalAmount,
  });

  final List<ExpenseRecord> items;
  final ExpensePagination pagination;
  final double totalAmount;

  factory ExpensePage.fromJson(Map<String, dynamic> json) => ExpensePage(
    items: (json['items'] as List)
        .map(
          (item) =>
              ExpenseRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    pagination: ExpensePagination.fromJson(
      Map<String, dynamic>.from(json['pagination'] as Map),
    ),
    totalAmount: _number(
      Map<String, dynamic>.from(json['summary'] as Map)['totalAmount'],
    ),
  );
}

class ExpenseListState {
  const ExpenseListState({
    required this.items,
    required this.pagination,
    required this.totalAmount,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<ExpenseRecord> items;
  final ExpensePagination pagination;
  final double totalAmount;
  final bool isLoadingMore;
  final bool loadMoreFailed;

  ExpenseListState copyWith({
    List<ExpenseRecord>? items,
    ExpensePagination? pagination,
    double? totalAmount,
    bool? isLoadingMore,
    bool? loadMoreFailed,
  }) => ExpenseListState(
    items: items ?? this.items,
    pagination: pagination ?? this.pagination,
    totalAmount: totalAmount ?? this.totalAmount,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );

  factory ExpenseListState.fromPage(ExpensePage page) => ExpenseListState(
    items: page.items,
    pagination: page.pagination,
    totalAmount: page.totalAmount,
  );
}

class ExpenseRepository {
  ExpenseRepository(this.dio);
  final Dio dio;

  Future<ExpensePage> list({
    required String restaurantLocationId,
    required DateRangeState dateRange,
    required ExpenseFilters filters,
    required int page,
    int limit = 25,
  }) async {
    final response = await dio.get(
      '/expenses',
      queryParameters: {
        'restaurantLocationId': restaurantLocationId,
        'startDate': dateRange.startDate.toIso8601String(),
        'endDate': dateRange.endDate.toIso8601String(),
        'page': page,
        'limit': limit,
        'sort': filters.sort.apiValue,
        if (filters.search.trim().isNotEmpty) 'search': filters.search.trim(),
        if (filters.categoryId != null) 'categoryId': filters.categoryId,
        if (filters.vendorId != null) 'vendorId': filters.vendorId,
      },
    );
    return ExpensePage.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<ExpenseRecord> detail(String id) async {
    final response = await dio.get('/expenses/$id');
    return ExpenseRecord.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<ExpenseLookups> lookups(String organizationId) async {
    final responses = await Future.wait([
      dio.get(
        '/expense-categories',
        queryParameters: {'organizationId': organizationId},
      ),
      dio.get('/vendors', queryParameters: {'organizationId': organizationId}),
    ]);
    return ExpenseLookups(
      (responses[0].data as List)
          .map(
            (item) => ExpenseCategoryOption.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      (responses[1].data as List)
          .map(
            (item) => ExpenseVendorOption.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}

final expenseRepositoryProvider = Provider(
  (ref) => ExpenseRepository(ref.watch(api)),
);
final expenseFiltersProvider = StateProvider((_) => const ExpenseFilters());
final expenseLookupsProvider = FutureProvider<ExpenseLookups>((ref) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) return const ExpenseLookups([], []);
  return ref.watch(expenseRepositoryProvider).lookups(location.organizationId);
});
final expenseDetailProvider = FutureProvider.family<ExpenseRecord, String>(
  (ref, id) => ref.watch(expenseRepositoryProvider).detail(id),
);

class ExpenseListController extends AsyncNotifier<ExpenseListState> {
  late RestaurantLocation _location;
  late DateRangeState _dateRange;
  late ExpenseFilters _filters;

  @override
  Future<ExpenseListState> build() async {
    final location = ref.watch(activeLocationProvider);
    if (location == null) {
      throw StateError('No active restaurant location');
    }
    _location = location;
    _dateRange = ref.watch(dateRangeProvider);
    _filters = ref.watch(expenseFiltersProvider);
    final page = await ref
        .watch(expenseRepositoryProvider)
        .list(
          restaurantLocationId: _location.id,
          dateRange: _dateRange,
          filters: _filters,
          page: 1,
        );
    return ExpenseListState.fromPage(page);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null ||
        current.isLoadingMore ||
        !current.pagination.hasMore) {
      return;
    }
    state = AsyncData(
      current.copyWith(isLoadingMore: true, loadMoreFailed: false),
    );
    try {
      final nextPage = await ref
          .read(expenseRepositoryProvider)
          .list(
            restaurantLocationId: _location.id,
            dateRange: _dateRange,
            filters: _filters,
            page: current.pagination.page + 1,
          );
      final existingIds = current.items.map((item) => item.id).toSet();
      final merged = [
        ...current.items,
        ...nextPage.items.where((item) => existingIds.add(item.id)),
      ];
      state = AsyncData(
        ExpenseListState(
          items: merged,
          pagination: nextPage.pagination,
          totalAmount: nextPage.totalAmount,
        ),
      );
    } catch (_) {
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }
}

final expenseListProvider =
    AsyncNotifierProvider<ExpenseListController, ExpenseListState>(
      ExpenseListController.new,
    );
