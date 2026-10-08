import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart';
import '../invoices/invoice_screens.dart';
import '../price_intelligence/price_changes_screen.dart';
import 'foundation.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  final searchController = TextEditingController();
  final scrollController = ScrollController();
  Timer? searchDebounce;

  @override
  void initState() {
    super.initState();
    searchController.text = ref.read(expenseFiltersProvider).search;
    scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (scrollController.position.extentAfter < 400) {
      ref.read(expenseListProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    searchDebounce?.cancel();
    searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final filters = ref.read(expenseFiltersProvider);
      ref.read(expenseFiltersProvider.notifier).state = filters.copyWith(
        search: value,
      );
    });
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(activeLocationProvider);
    if (location == null) {
      return ref
          .watch(activeLocationStateProvider)
          .when(
            loading: () => const LoadingState(label: 'Loading restaurant...'),
            error: (_, _) => ErrorState(
              message: 'Unable to load restaurant data',
              onRetry: () => ref.invalidate(activeLocationControllerProvider),
            ),
            data: (_) =>
                const EmptyState(message: 'No restaurant locations available'),
          );
    }

    final lookups = ref.watch(expenseLookupsProvider);
    final expenses = ref.watch(expenseListProvider);
    if (lookups.isLoading || expenses.isLoading) {
      return const LoadingState(label: 'Loading expenses...');
    }
    if (lookups.hasError || expenses.hasError) {
      return ErrorState(
        message: 'Unable to load expenses',
        onRetry: () {
          ref.invalidate(expenseLookupsProvider);
          ref.invalidate(expenseListProvider);
        },
      );
    }

    final lookupData = lookups.requireValue;
    final expenseData = expenses.requireValue;
    final filters = ref.watch(expenseFiltersProvider);
    return ListView.builder(
      key: const Key('expenses-list'),
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: expenseData.items.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ExpenseHeader(
            location: location,
            lookups: lookupData,
            filters: filters,
            totalAmount: expenseData.totalAmount,
            totalItems: expenseData.pagination.totalItems,
            searchController: searchController,
            onSearchChanged: _onSearchChanged,
          );
        }
        if (index == expenseData.items.length + 1) {
          if (expenseData.items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 36),
              child: EmptyState(
                message: filters.isFiltered
                    ? 'No expenses match your filters.'
                    : 'No expenses found for this period.',
              ),
            );
          }
          if (expenseData.isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (expenseData.loadMoreFailed) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(expenseListProvider.notifier).loadMore(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry loading more'),
                ),
              ),
            );
          }
          return expenseData.pagination.hasMore
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Center(
                    child: TextButton(
                      onPressed: () =>
                          ref.read(expenseListProvider.notifier).loadMore(),
                      child: const Text('Load more'),
                    ),
                  ),
                )
              : const SizedBox(height: 12);
        }
        final expense = expenseData.items[index - 1];
        return ExpenseListItem(
          expense: expense,
          lookups: lookupData,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => ExpenseDetailSheet(expenseId: expense.id),
          ),
        );
      },
    );
  }
}

class _ExpenseHeader extends ConsumerWidget {
  const _ExpenseHeader({
    required this.location,
    required this.lookups,
    required this.filters,
    required this.totalAmount,
    required this.totalItems,
    required this.searchController,
    required this.onSearchChanged,
  });

  final RestaurantLocation location;
  final ExpenseLookups lookups;
  final ExpenseFilters filters;
  final double totalAmount;
  final int totalItems;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(availableLocationsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Expenses',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const DateRangeSelector(),
          ],
        ),
        const SizedBox(height: 12),
        LocationSelector(
          active: location,
          locations: locations.isEmpty ? [location] : locations,
          onSelected: (selected) => ref
              .read(activeLocationControllerProvider.notifier)
              .select(selected),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('open-price-changes'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PriceChangesScreen()),
                ),
                icon: const Icon(Icons.trending_up),
                label: const Text('Price Changes'),
              ),
              OutlinedButton.icon(
                key: const Key('open-invoices'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InvoiceListScreen()),
                ),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Invoices'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          key: const Key('expense-total-card'),
          color: Theme.of(context).colorScheme.primaryContainer,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Expenses',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatCurrency(totalAmount),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$totalItems ${totalItems == 1 ? 'expense' : 'expenses'}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('expense-search'),
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search expenses or vendors',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                    icon: const Icon(Icons.close),
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _LookupFilter<ExpenseCategoryOption>(
                key: const Key('category-filter'),
                label: filters.categoryId == null
                    ? 'All Categories'
                    : lookups.categoryName(filters.categoryId!),
                allLabel: 'All Categories',
                selectedId: filters.categoryId,
                options: lookups.categories,
                idOf: (option) => option.id,
                nameOf: (option) => option.name,
                onSelected: (id) {
                  ref.read(expenseFiltersProvider.notifier).state = filters
                      .copyWith(categoryId: id);
                },
              ),
              const SizedBox(width: 8),
              _LookupFilter<ExpenseVendorOption>(
                key: const Key('vendor-filter'),
                label: filters.vendorId == null
                    ? 'All Vendors'
                    : lookups.vendorName(filters.vendorId!) ?? 'All Vendors',
                allLabel: 'All Vendors',
                selectedId: filters.vendorId,
                options: lookups.vendors,
                idOf: (option) => option.id,
                nameOf: (option) => option.name,
                onSelected: (id) {
                  ref.read(expenseFiltersProvider.notifier).state = filters
                      .copyWith(vendorId: id);
                },
              ),
              const SizedBox(width: 8),
              PopupMenuButton<ExpenseSort>(
                key: const Key('expense-sort'),
                tooltip: 'Sort expenses',
                initialValue: filters.sort,
                onSelected: (sort) {
                  ref.read(expenseFiltersProvider.notifier).state = filters
                      .copyWith(sort: sort);
                },
                itemBuilder: (_) => ExpenseSort.values
                    .map(
                      (sort) =>
                          PopupMenuItem(value: sort, child: Text(sort.label)),
                    )
                    .toList(),
                child: Chip(
                  avatar: const Icon(Icons.swap_vert, size: 18),
                  label: Text(filters.sort.label),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _LookupFilter<T> extends StatelessWidget {
  const _LookupFilter({
    required this.label,
    required this.allLabel,
    required this.selectedId,
    required this.options,
    required this.idOf,
    required this.nameOf,
    required this.onSelected,
    super.key,
  });

  final String label;
  final String allLabel;
  final String? selectedId;
  final List<T> options;
  final String Function(T value) idOf;
  final String Function(T value) nameOf;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String?>(
    initialValue: selectedId,
    onSelected: onSelected,
    itemBuilder: (_) => [
      PopupMenuItem<String?>(value: null, child: Text(allLabel)),
      ...options.map(
        (option) => PopupMenuItem<String?>(
          value: idOf(option),
          child: Text(nameOf(option)),
        ),
      ),
    ],
    child: Chip(
      avatar: const Icon(Icons.filter_list, size: 18),
      label: Text(label),
    ),
  );
}

class ExpenseListItem extends StatelessWidget {
  const ExpenseListItem({
    required this.expense,
    required this.lookups,
    required this.onTap,
    super.key,
  });

  final ExpenseRecord expense;
  final ExpenseLookups lookups;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vendor = lookups.vendorName(expense.vendorId);
    final description = expense.description?.trim();
    final primary =
        vendor ??
        (description?.isNotEmpty == true
            ? description!
            : lookups.categoryName(expense.expenseCategoryId));
    return Card(
      key: Key('expense-${expense.id}'),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (vendor != null && description?.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 7),
                    Text(
                      '${lookups.categoryName(expense.expenseCategoryId)} • ${formatExpenseDate(expense.date)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formatCurrency(expense.amount),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExpenseDetailSheet extends ConsumerWidget {
  const ExpenseDetailSheet({required this.expenseId, super.key});
  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(expenseDetailProvider(expenseId));
    final lookups = ref.watch(expenseLookupsProvider);
    return SafeArea(
      child: detail.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => ErrorState(
          message: 'Unable to load expense details',
          onRetry: () => ref.invalidate(expenseDetailProvider(expenseId)),
        ),
        data: (expense) {
          final lookupData =
              lookups.valueOrNull ?? const ExpenseLookups([], []);
          final vendor = lookupData.vendorName(expense.vendorId);
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              4,
              24,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Expense Details',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 18),
                Text(
                  formatCurrency(expense.amount),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                if (vendor != null) _DetailRow(label: 'Vendor', value: vendor),
                _DetailRow(
                  label: 'Category',
                  value: lookupData.categoryName(expense.expenseCategoryId),
                ),
                _DetailRow(
                  label: 'Date',
                  value: formatExpenseDate(expense.date),
                ),
                if (expense.description?.trim().isNotEmpty == true)
                  _DetailRow(
                    label: 'Description',
                    value: expense.description!.trim(),
                  ),
                if (expense.notes?.trim().isNotEmpty == true)
                  _DetailRow(label: 'Notes', value: expense.notes!.trim()),
                _DetailRow(
                  label: 'Source',
                  value: _sourceLabel(expense.source),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

String formatExpenseDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}

String _sourceLabel(String source) => source
    .toLowerCase()
    .split('_')
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
