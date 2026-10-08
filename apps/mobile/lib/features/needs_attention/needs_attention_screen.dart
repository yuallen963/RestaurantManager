import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/foundation.dart';
import '../dashboard/home_screen.dart';
import '../expenses/expenses_screen.dart';
import '../expenses/foundation.dart';
import '../price_intelligence/price_changes_screen.dart';
import '../vendors/vendors_screen.dart';
import 'foundation.dart';

class NeedsAttentionPreview extends ConsumerWidget {
  const NeedsAttentionPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(needsAttentionProvider);
    return Card(
      key: const Key('needs-attention-preview'),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: data.when(
          loading: () => const SizedBox(
            height: 72,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Needs Attention',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text('Unable to load issues'),
              TextButton(
                onPressed: () => ref.invalidate(needsAttentionProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
          data: (result) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Needs Attention',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${result.summary.total} ${result.summary.total == 1 ? 'issue' : 'issues'}',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (result.items.isEmpty)
                const Text('No major cost issues detected for this period.')
              else
                for (final item in result.items.take(3))
                  _PreviewRow(item: item),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('view-all-attention'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NeedsAttentionScreen(),
                    ),
                  ),
                  child: const Text('View All'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.item});
  final AttentionItem item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SeverityBadge(item.severity),
        const SizedBox(width: 10),
        Expanded(
          child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        if (item.estimatedMonthlyImpact != null) ...[
          const SizedBox(width: 8),
          Text(
            '+${attentionCurrency(item.estimatedMonthlyImpact!)}/mo',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ],
    ),
  );
}

class NeedsAttentionScreen extends ConsumerWidget {
  const NeedsAttentionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(activeLocationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Needs Attention')),
      body: location == null
          ? ref
                .watch(activeLocationStateProvider)
                .when(
                  loading: () =>
                      const LoadingState(label: 'Loading restaurant...'),
                  error: (_, _) => ErrorState(
                    message: 'Unable to load restaurant data',
                    onRetry: () =>
                        ref.invalidate(activeLocationControllerProvider),
                  ),
                  data: (_) => const EmptyState(
                    message: 'No restaurant locations available',
                  ),
                )
          : ref
                .watch(needsAttentionProvider)
                .when(
                  loading: () => const LoadingState(label: 'Loading issues...'),
                  error: (_, _) => ErrorState(
                    message: 'Unable to load issues',
                    onRetry: () => ref.invalidate(needsAttentionProvider),
                  ),
                  data: (data) =>
                      _AttentionContent(location: location, data: data),
                ),
    );
  }
}

class _AttentionContent extends ConsumerWidget {
  const _AttentionContent({required this.location, required this.data});
  final RestaurantLocation location;
  final NeedsAttentionData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(availableLocationsProvider);
    return ListView(
      key: const Key('needs-attention-list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        LocationSelector(
          active: location,
          locations: locations.isEmpty ? [location] : locations,
          onSelected: (selected) => ref
              .read(activeLocationControllerProvider.notifier)
              .select(selected),
        ),
        const SizedBox(height: 12),
        const Align(
          alignment: Alignment.centerRight,
          child: DateRangeSelector(),
        ),
        const SizedBox(height: 16),
        Text(
          '${data.summary.total} meaningful ${data.summary.total == 1 ? 'issue' : 'issues'}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (data.summary.estimatedMonthlyImpact > 0)
          Text(
            'Known item-price impact: +${attentionCurrency(data.summary.estimatedMonthlyImpact)}/month',
          ),
        const SizedBox(height: 12),
        if (data.items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 42),
            child: EmptyState(
              message: 'No major cost issues detected for this period.',
            ),
          )
        else
          for (final item in data.items) _AttentionCard(item: item),
      ],
    );
  }
}

class _AttentionCard extends ConsumerWidget {
  const _AttentionCard({required this.item});
  final AttentionItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    key: Key('attention-${item.id}'),
    margin: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openAttentionAction(context, ref, item),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SeverityBadge(item.severity),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            if (item.subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(item.subtitle!),
              ),
            const SizedBox(height: 10),
            Text(item.message),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (item.percentageChange != null)
                  Text(
                    '${item.percentageChange! >= 0 ? '+' : ''}${item.percentageChange!.toStringAsFixed(1)}%',
                  ),
                if (item.percentagePointChange != null)
                  Text(
                    '+${item.percentagePointChange!.toStringAsFixed(1)} points',
                  ),
                if (item.estimatedMonthlyImpact != null)
                  Text(
                    'Est. +${attentionCurrency(item.estimatedMonthlyImpact!)}/month',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                Text(attentionDate(item.occurredAt)),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class SeverityBadge extends StatelessWidget {
  const SeverityBadge(this.severity, {super.key});
  final AttentionSeverity severity;

  @override
  Widget build(BuildContext context) {
    final color = switch (severity) {
      AttentionSeverity.critical => Theme.of(context).colorScheme.error,
      AttentionSeverity.high => Colors.deepOrange,
      AttentionSeverity.medium => Colors.amber.shade800,
      AttentionSeverity.low => Colors.blueGrey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        severity.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

Future<void> openAttentionAction(
  BuildContext context,
  WidgetRef ref,
  AttentionItem item,
) async {
  switch (item.action.type) {
    case AttentionActionType.openPriceHistory:
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PriceHistoryScreen(itemKey: item.action.targetId),
        ),
      );
    case AttentionActionType.openVendor:
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => VendorDetailSheet(id: item.action.targetId),
      );
    case AttentionActionType.openExpenseCategory:
      final filters = ref.read(expenseFiltersProvider);
      ref.read(expenseFiltersProvider.notifier).state = ExpenseFilters(
        categoryId: item.action.targetId,
        sort: filters.sort,
      );
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Category Expenses')),
            body: const ExpensesScreen(),
          ),
        ),
      );
    case AttentionActionType.openDashboardCost:
      Navigator.pop(context);
  }
}

String attentionCurrency(double value) {
  final text = value
      .abs()
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '\$$text';
}

String attentionDate(DateTime value) =>
    '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][value.month - 1]} ${value.day}';
