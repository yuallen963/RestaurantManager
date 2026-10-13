import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'foundation.dart';
import '../banking/foundation.dart';
import '../needs_attention/needs_attention_screen.dart';
import '../banking/bank_screens.dart';
import '../invoices/invoice_screens.dart';
import '../pos/pos_integrations_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(activeLocationProvider);
    final locations = ref.watch(availableLocationsProvider);

    if (location == null) {
      final locationState = ref.watch(activeLocationStateProvider);
      return locationState.when(
        loading: () => const LoadingState(label: 'Loading restaurant...'),
        error: (_, _) => ErrorState(
          message: 'Unable to load restaurant data',
          onRetry: () => ref.invalidate(activeLocationControllerProvider),
        ),
        data: (_) =>
            const EmptyState(message: 'No restaurant locations available'),
      );
    }

    final dashboard = ref.watch(dashboardProvider);
    final previousDashboard = ref.watch(previousDashboardProvider);
    final bankSync = ref.watch(bankSyncStatusProvider);
    ref.listen(bankSyncStatusProvider, (previous, next) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      if (before?.inProgress == true &&
          after?.state == BankImportState.complete) {
        ref.invalidate(bankTransactionsProvider);
        ref.invalidate(bankTransactionsAwaitingReviewProvider);
        ref.invalidate(allBankTransactionsProvider);
        ref.invalidate(unverifiedBankDepositsProvider);
        ref.invalidate(dashboardProvider);
        ref.invalidate(previousDashboardProvider);
      }
    });
    final dashboardBody = dashboard.when<Widget>(
      loading: () => const LoadingState(label: 'Loading dashboard...'),
      error: (_, _) => ErrorState(
        message: 'Unable to load dashboard',
        onRetry: () {
          ref.invalidate(dashboardProvider);
          ref.invalidate(previousDashboardProvider);
        },
      ),
      data: (data) {
        if (data == null) {
          return ErrorState(
            message: 'Unable to load dashboard',
            onRetry: () => ref.invalidate(dashboardProvider),
          );
        }
        return _DashboardContent(
          location: location,
          locations: locations,
          dashboard: data,
          previous: previousDashboard.valueOrNull,
        );
      },
    );
    return Column(
      children: [
        bankSync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const _BankSyncBanner(
            icon: Icons.cloud_off_outlined,
            message: 'Unable to check bank synchronization status.',
            isError: true,
          ),
          data: (status) => _BankSyncStatusBanner(status: status),
        ),
        Expanded(child: dashboardBody),
      ],
    );
  }
}

class _BankSyncStatusBanner extends StatelessWidget {
  const _BankSyncStatusBanner({required this.status});
  final BankSyncStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status.state) {
      BankImportState.pending => const _BankSyncBanner(
        icon: Icons.schedule_outlined,
        message: 'Bank connected. Transaction import is waiting to start.',
      ),
      BankImportState.importing => const _BankSyncBanner(
        icon: Icons.sync,
        message:
            'Importing bank transactions. Your dashboard will update automatically.',
        showProgress: true,
      ),
      BankImportState.partiallyComplete => _BankSyncBanner(
        icon: Icons.sync,
        message:
            '${status.transactionCount} transactions imported so far. Import is still running.',
        showProgress: true,
      ),
      BankImportState.failed => _BankSyncBanner(
        icon: Icons.error_outline,
        message:
            status.message ??
            'Bank synchronization failed. Open Bank Accounts to retry.',
        isError: true,
        showAction: status.canRetry,
      ),
      BankImportState.complete when status.transactionCount == 0 =>
        const _BankSyncBanner(
          icon: Icons.check_circle_outline,
          message:
              'Bank sync is complete. No transactions were found for this restaurant.',
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _BankSyncBanner extends StatelessWidget {
  const _BankSyncBanner({
    required this.icon,
    required this.message,
    this.showProgress = false,
    this.isError = false,
    this.showAction = false,
  });
  final IconData icon;
  final String message;
  final bool showProgress, isError, showAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const Key('bank-sync-banner'),
      color: isError ? colors.errorContainer : colors.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (showProgress)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  icon,
                  color: isError
                      ? colors.onErrorContainer
                      : colors.onSecondaryContainer,
                ),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
              if (showAction)
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BankAccountsScreen(),
                    ),
                  ),
                  child: const Text('Manage'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FirstRunActions extends StatelessWidget {
  const _FirstRunActions();
  @override
  Widget build(BuildContext context) => Column(
    children: [
      _SetupAction(
        title: 'Connect Bank',
        description: 'Track spending, vendors, and recurring expenses.',
        icon: Icons.account_balance_outlined,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BankAccountsScreen()),
        ),
      ),
      _SetupAction(
        title: 'Upload Invoices',
        description: 'Detect product price changes and purchasing trends.',
        icon: Icons.upload_file,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const InvoiceUploadScreen()),
        ),
      ),
      _SetupAction(
        title: 'Connect POS',
        description: 'Track sales and profitability when supported.',
        icon: Icons.point_of_sale_outlined,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PosIntegrationsScreen()),
        ),
      ),
    ],
  );
}

class _SetupAction extends StatelessWidget {
  const _SetupAction({
    required this.title,
    required this.description,
    required this.icon,
    required this.onPressed,
  });
  final String title, description;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(description),
      trailing: const Icon(Icons.chevron_right),
      onTap: onPressed,
    ),
  );
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.location,
    required this.locations,
    required this.dashboard,
    required this.previous,
  });

  final RestaurantLocation location;
  final List<RestaurantLocation> locations;
  final DashboardData dashboard;
  final DashboardData? previous;

  @override
  Widget build(BuildContext context) {
    final current = dashboard.summary;
    final previousSummary = previous?.summary;
    final availability = dashboard.availability;
    final breakdown = [...dashboard.breakdown]
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final noSources =
        !availability.bank &&
        !availability.reviewedInvoices &&
        !availability.revenue &&
        !availability.expenses &&
        !availability.pos;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _DashboardHeader(location: location, locations: locations),
        const SizedBox(height: 16),
        const NeedsAttentionPreview(),
        const SizedBox(height: 20),
        if (noSources) ...[
          const EmptyState(
            message: 'Connect a data source to start building your dashboard.',
          ),
          const Text(
            'FundWell only shows financial insights supported by your connected data.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          const _FirstRunActions(),
        ],
        if (availability.profitability) ...[
          Card(
            key: const Key('profit-card'),
            color: Theme.of(context).colorScheme.primaryContainer,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estimated Profit',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatCurrency(current.estimatedProfit),
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 10),
                  PercentageChange(
                    current: current.estimatedProfit,
                    previous: previousSummary?.estimatedProfit,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = math.max(
                140.0,
                (constraints.maxWidth - 12) / 2,
              );
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FinancialMetricCard(
                    key: const Key('revenue-card'),
                    width: cardWidth,
                    label: 'Revenue',
                    value: formatCurrency(current.revenue),
                    current: current.revenue,
                    previous: previousSummary?.revenue,
                  ),
                  FinancialMetricCard(
                    key: const Key('expenses-card'),
                    width: cardWidth,
                    label: 'Expenses',
                    value: formatCurrency(current.expenses),
                    current: current.expenses,
                    previous: previousSummary?.expenses,
                    favorableWhenIncrease: false,
                  ),
                  FinancialMetricCard(
                    key: const Key('margin-card'),
                    width: cardWidth,
                    label: 'Profit Margin',
                    value: formatPercent(current.profitMargin),
                    current: current.profitMargin,
                    previous: previousSummary?.profitMargin,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Estimated from recorded revenue and expenses for this period.',
          ),
        ] else if (!noSources) ...[
          Text(
            'Profit unavailable',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(_missingProfitMessage(availability)),
        ],
        if (availability.revenue && !availability.profitability) ...[
          const SizedBox(height: 20),
          _PrimaryAmountCard(
            key: const Key('revenue-only-card'),
            label: 'Recorded revenue',
            amount: current.revenue,
            note: availability.pos
                ? 'Sales recorded from your connected revenue source.'
                : 'Revenue recorded for this period.',
          ),
        ],
        if (availability.bank && dashboard.bank != null) ...[
          const SizedBox(height: 28),
          _BankSection(insights: dashboard.bank!, previous: previous?.bank),
        ],
        if (availability.reviewedInvoices && dashboard.invoices != null) ...[
          const SizedBox(height: 28),
          _InvoiceSection(insights: dashboard.invoices!),
        ],
        if (availability.bank && availability.reviewedInvoices) ...[
          const SizedBox(height: 12),
          const Text(
            'Bank outflows and invoice purchases are shown separately. Matched records represent the same purchase and are not added together.',
          ),
        ],
        if (availability.expenses && !availability.profitability) ...[
          const SizedBox(height: 28),
          _PrimaryAmountCard(
            label: 'Recorded expenses',
            amount: current.expenses,
            note: 'Expenses recorded for this period.',
          ),
        ],
        if (availability.expenses && breakdown.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text(
            'Where your recorded expenses went',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < breakdown.length; index++) ...[
                  ExpenseBreakdownRow(item: breakdown[index]),
                  if (index != breakdown.length - 1)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              ],
            ),
          ),
        ],
        if (availability.profitability) ...[
          const SizedBox(height: 28),
          Text(
            'Key Costs',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  CostMetricBar(
                    key: const Key('food-cost-bar'),
                    label: 'Food Cost',
                    percentage: current.foodCostPercentage,
                  ),
                  const SizedBox(height: 20),
                  CostMetricBar(
                    key: const Key('labor-cost-bar'),
                    label: 'Labor Cost',
                    percentage: current.laborCostPercentage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

String _missingProfitMessage(DashboardAvailability value) {
  if (!value.revenue && !value.expenses) {
    return 'Add revenue and expense data to calculate estimated profit.';
  }
  if (!value.revenue) {
    return 'Revenue data is missing, so profit and margins are not shown.';
  }
  if (!value.expenses || !value.bank || !value.reviewedInvoices) {
    return 'More complete cost data is needed before profit and margins can be estimated.';
  }
  return 'More complete financial data is needed before profit can be estimated.';
}

class _PrimaryAmountCard extends StatelessWidget {
  const _PrimaryAmountCard({
    required this.label,
    required this.amount,
    required this.note,
    super.key,
  });
  final String label, note;
  final double amount;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            formatCurrency(amount),
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(note, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class _BankSection extends ConsumerWidget {
  const _BankSection({required this.insights, required this.previous});
  final BankDashboardInsights insights;
  final BankDashboardInsights? previous;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts =
        ref
            .watch(bankConnectionsProvider)
            .valueOrNull
            ?.expand((connection) => connection.accounts)
            .where((account) => account.active)
            .length ??
        0;
    final waiting =
        ref.watch(bankTransactionsAwaitingReviewProvider).valueOrNull ??
        const [];
    final recent =
        ref.watch(allBankTransactionsProvider).valueOrNull ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bank activity',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unreviewed bank activity',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '$accounts connected ${accounts == 1 ? 'account' : 'accounts'} · ${waiting.length} ${waiting.length == 1 ? 'transaction needs' : 'transactions need'} review',
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const Key('review-transactions-home'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BankTransactionsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    waiting.isEmpty
                        ? 'View Bank Activity'
                        : 'Review Transactions (${waiting.length})',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _PrimaryAmountCard(
          key: const Key('bank-outflows-card'),
          label: 'Tracked bank outflows',
          amount: insights.trackedOutflows,
          note:
              'Tracked bank spending is not necessarily total business costs.',
        ),
        PercentageChange(
          current: insights.trackedOutflows,
          previous:
              previous?.trackedOutflows ?? insights.previousTrackedOutflows,
          favorableWhenIncrease: false,
        ),
        const SizedBox(height: 10),
        Text(
          '${insights.uncategorizedCount} uncategorized · ${insights.unmatchedCount} unmatched · ${insights.matchedInvoiceCount} matched to invoices',
        ),
        if (insights.categoryBreakdown.isNotEmpty) ...[
          const SizedBox(height: 14),
          _NamedAmountList(
            title: 'Bank spending by category',
            values: insights.categoryBreakdown,
          ),
        ],
        if (insights.topVendors.isNotEmpty) ...[
          const SizedBox(height: 14),
          _NamedAmountList(
            title: 'Top bank vendors',
            values: insights.topVendors,
          ),
        ],
        if (insights.largestExpenses.isNotEmpty) ...[
          const SizedBox(height: 14),
          _NamedAmountList(
            title: 'Largest tracked outflows',
            values: insights.largestExpenses
                .map((item) => NamedAmount(item.name, item.amount))
                .toList(),
          ),
        ],
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recently imported',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final item in recent.take(3))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(item.merchant),
                      subtitle: Text(
                        item.status == 'MATCHED_EXPENSE'
                            ? 'Confirmed restaurant expense'
                            : item.status == 'IGNORED'
                            ? 'Ignored'
                            : item.status == 'MATCHED_INVOICE'
                            ? 'Matched to invoice'
                            : 'Suggested · Needs review',
                      ),
                      trailing: Text(formatCurrency(item.amount.abs())),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InvoiceSection extends StatelessWidget {
  const _InvoiceSection({required this.insights});
  final InvoiceDashboardInsights insights;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Invoice activity',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      _PrimaryAmountCard(
        key: const Key('invoice-purchases-card'),
        label: 'Reviewed invoice purchases',
        amount: insights.reviewedPurchases,
        note: 'Purchases are not confirmed payments.',
      ),
      PercentageChange(
        current: insights.reviewedPurchases,
        previous: insights.previousReviewedPurchases,
        favorableWhenIncrease: false,
      ),
      Text(
        '${insights.reviewedCount} reviewed · ${insights.requiringReviewCount} need review · ${insights.unmatchedCount} unmatched',
      ),
      if (insights.topVendors.isNotEmpty) ...[
        const SizedBox(height: 14),
        _NamedAmountList(
          title: 'Top invoice vendors',
          values: insights.topVendors,
        ),
      ],
    ],
  );
}

class _NamedAmountList extends StatelessWidget {
  const _NamedAmountList({required this.title, required this.values});
  final String title;
  final List<NamedAmount> values;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final value in values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(value.name)),
                  Text(
                    formatCurrency(value.amount),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader({required this.location, required this.locations});

  final RestaurantLocation location;
  final List<RestaurantLocation> locations;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Restaurant performance',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const DateRangeSelector(),
        ],
      ),
      const SizedBox(height: 8),
      LocationSelector(
        active: location,
        locations: locations.isEmpty ? [location] : locations,
        onSelected: (selected) => ref
            .read(activeLocationControllerProvider.notifier)
            .select(selected),
      ),
    ],
  );
}

class LocationSelector extends StatelessWidget {
  const LocationSelector({
    required this.active,
    required this.locations,
    required this.onSelected,
    super.key,
  });

  final RestaurantLocation active;
  final List<RestaurantLocation> locations;
  final Future<void> Function(RestaurantLocation location) onSelected;

  @override
  Widget build(BuildContext context) => InkWell(
    key: const Key('location-selector'),
    borderRadius: BorderRadius.circular(12),
    onTap: () => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Choose a restaurant',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              for (final location in locations)
                ListTile(
                  leading: Icon(
                    location.id == active.id
                        ? Icons.check_circle
                        : Icons.storefront_outlined,
                  ),
                  title: Text(
                    location.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: location.id == active.id,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onSelected(location);
                  },
                ),
            ],
          ),
        ),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storefront_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              active.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down),
        ],
      ),
    ),
  );
}

class DateRangeSelector extends ConsumerWidget {
  const DateRangeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(dateRangeProvider);
    return PopupMenuButton<DatePreset>(
      key: const Key('date-range-selector'),
      tooltip: 'Choose date range',
      onSelected: (preset) async {
        if (preset != DatePreset.custom) {
          ref.read(dateRangeProvider.notifier).state = DateRangeState.resolve(
            preset,
          );
          return;
        }
        final selected = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 366)),
          initialDateRange: DateTimeRange(
            start: range.startDate,
            end: range.endDate,
          ),
        );
        if (selected != null) {
          ref.read(dateRangeProvider.notifier).state = DateRangeState.resolve(
            DatePreset.custom,
            start: selected.start,
            end: selected.end,
          );
        }
      },
      itemBuilder: (_) => DatePreset.values
          .map(
            (preset) => PopupMenuItem(
              value: preset,
              child: Text(datePresetLabel(preset)),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_outlined, size: 18),
            const SizedBox(width: 7),
            Text(datePresetLabel(range.preset), maxLines: 1),
          ],
        ),
      ),
    );
  }
}

class FinancialMetricCard extends StatelessWidget {
  const FinancialMetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.current,
    required this.previous,
    this.favorableWhenIncrease = true,
    super.key,
  });

  final double width;
  final String label;
  final String value;
  final double current;
  final double? previous;
  final bool favorableWhenIncrease;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            PercentageChange(
              current: current,
              previous: previous,
              favorableWhenIncrease: favorableWhenIncrease,
              compact: true,
            ),
          ],
        ),
      ),
    ),
  );
}

class PercentageChange extends StatelessWidget {
  const PercentageChange({
    required this.current,
    required this.previous,
    this.favorableWhenIncrease = true,
    this.compact = false,
    super.key,
  });

  final double current;
  final double? previous;
  final bool favorableWhenIncrease;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final old = previous;
    if (old == null || old == 0 || !old.isFinite || !current.isFinite) {
      return Text(
        '— vs previous period',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final change = ((current - old) / old.abs()) * 100;
    if (!change.isFinite) {
      return Text(
        '— vs previous period',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final increased = change > 0;
    final decreased = change < 0;
    final favorable =
        change == 0 || (favorableWhenIncrease ? increased : decreased);
    final color = change == 0
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : favorable
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.error;
    final icon = increased
        ? Icons.arrow_upward
        : decreased
        ? Icons.arrow_downward
        : Icons.arrow_forward;
    final direction = increased
        ? 'increase'
        : decreased
        ? 'decrease'
        : 'no change';
    final text = '${change.abs().toStringAsFixed(1)}% $direction';

    return Semantics(
      label: '$text vs previous period',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              compact ? text : '$text vs previous period',
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CostMetricBar extends StatelessWidget {
  const CostMetricBar({
    required this.label,
    required this.percentage,
    super.key,
  });

  final String label;
  final double percentage;

  @override
  Widget build(BuildContext context) {
    final progress = (percentage / 100).clamp(0.0, 1.0);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            Text(
              formatPercent(percentage),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(8),
        ),
      ],
    );
  }
}

class ExpenseBreakdownRow extends StatelessWidget {
  const ExpenseBreakdownRow({required this.item, super.key});

  final ExpenseBreakdown item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.categoryName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatCurrency(item.amount),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  formatPercent(item.percentageOfExpenses),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 9),
        LinearProgressIndicator(
          value: (item.percentageOfExpenses / 100).clamp(0.0, 1.0),
          minHeight: 6,
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.secondary,
        ),
      ],
    ),
  );
}

class LoadingState extends StatelessWidget {
  const LoadingState({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(label),
      ],
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 36),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.query_stats, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

String formatCurrency(double value) {
  final rounded = value.abs().round().toString();
  final formatted = rounded.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${value < 0 ? '-' : ''}\$$formatted';
}

String formatPercent(double value) => '${value.toStringAsFixed(1)}%';

String datePresetLabel(DatePreset preset) => switch (preset) {
  DatePreset.thisMonth => 'This Month',
  DatePreset.lastMonth => 'Last Month',
  DatePreset.last30Days => 'Last 30 Days',
  DatePreset.custom => 'Custom',
};
