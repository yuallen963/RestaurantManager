import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show demoModeProvider;
import '../dashboard/foundation.dart';
import '../design/fundwell_theme.dart';
import '../expenses/foundation.dart';
import '../needs_attention/foundation.dart';
import '../vendors/foundation.dart';
import '../responsive.dart';
import 'foundation.dart';
import 'plaid_link/plaid_link.dart';

final plaidLinkLauncherProvider = Provider.autoDispose<PlaidLinkLauncher>((
  ref,
) {
  final launcher = createPlaidLinkLauncher();
  ref.onDispose(launcher.dispose);
  return launcher;
});

void _invalidateBankDerivedProviders(WidgetRef ref) {
  ref.invalidate(bankTransactionsProvider);
  ref.invalidate(bankTransactionsAwaitingReviewProvider);
  ref.invalidate(allBankTransactionsProvider);
  ref.invalidate(unverifiedBankDepositsProvider);
  ref.invalidate(expenseListProvider);
  ref.invalidate(vendorListProvider);
  ref.invalidate(dashboardProvider);
  ref.invalidate(previousDashboardProvider);
  ref.invalidate(needsAttentionProvider);
}

class BankAccountsScreen extends ConsumerStatefulWidget {
  const BankAccountsScreen({super.key});
  @override
  ConsumerState<BankAccountsScreen> createState() => _BankAccountsScreenState();
}

class _BankAccountsScreenState extends ConsumerState<BankAccountsScreen> {
  bool busy = false;
  String? actionError;
  bool oauthResumeAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumePlaidOAuth());
  }

  Future<void> _resumePlaidOAuth() async {
    if (oauthResumeAttempted) return;
    final location = ref.read(activeLocationProvider);
    if (location == null) return;
    final launcher = ref.read(plaidLinkLauncherProvider);
    if (!launcher.isWeb) return;
    oauthResumeAttempted = true;
    setState(() {
      busy = true;
      actionError = null;
    });
    try {
      final result = await launcher.resumeOAuth();
      if (result != null) await _completePlaidLink(result);
    } catch (_) {
      if (mounted) {
        setState(
          () => actionError =
              'Unable to resume the secure bank connection. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> connect([BankConnectionData? existing]) async {
    final location = ref.read(activeLocationProvider);
    if (location == null) return;
    setState(() {
      busy = true;
      actionError = null;
    });
    try {
      final repository = ref.read(bankingRepositoryProvider);
      final launcher = ref.read(plaidLinkLauncherProvider);
      final setup = existing == null
          ? await repository.linkToken(
              location.organizationId,
              web: launcher.isWeb,
            )
          : await repository.reauthenticationLinkToken(
              existing.id,
              web: launcher.isWeb,
            );
      if (setup.demo) {
        if (existing == null) {
          await repository.exchange(
            location.organizationId,
            'demo-public-${location.organizationId}',
            location.id,
          );
        } else {
          await repository.completeReauthentication(existing.id);
        }
        await refresh();
        return;
      }
      final result = await launcher.open(
        PlaidLinkRequest(
          linkToken: setup.linkToken,
          context: PlaidLinkContext(
            organizationId: location.organizationId,
            locationId: location.id,
            connectionId: existing?.id,
          ),
        ),
      );
      await _completePlaidLink(result);
    } catch (_) {
      if (mounted) {
        setState(
          () => actionError = 'Unable to connect the bank account. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _completePlaidLink(PlaidLinkResult result) async {
    if (result.outcome == PlaidLinkOutcome.cancelled) return;
    if (result.outcome == PlaidLinkOutcome.error) {
      throw StateError(result.message ?? 'Plaid Link failed');
    }
    final location = ref.read(activeLocationProvider);
    if (location == null ||
        location.organizationId != result.context.organizationId ||
        location.id != result.context.locationId) {
      throw StateError('The active restaurant changed during bank connection.');
    }
    final repository = ref.read(bankingRepositoryProvider);
    if (result.context.connectionId == null) {
      await repository.exchange(
        location.organizationId,
        result.publicToken!,
        location.id,
      );
    } else {
      await repository.completeReauthentication(result.context.connectionId!);
    }
    await refresh();
  }

  Future<void> refresh() async {
    ref.invalidate(bankConnectionsProvider);
    ref.invalidate(bankTransactionsProvider);
    ref.invalidate(bankTransactionsAwaitingReviewProvider);
    ref.invalidate(bankSyncStatusProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(previousDashboardProvider);
    try {
      await ref.read(bankConnectionsProvider.future);
    } catch (_) {
      // The provider's AsyncError is rendered by the screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RestaurantLocation?>(activeLocationProvider, (_, location) {
      if (location != null && !oauthResumeAttempted) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _resumePlaidOAuth(),
        );
      }
    });
    final state = ref.watch(bankConnectionsProvider);
    final readOnly = ref.watch(demoModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bank Accounts')),
      body: state.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Loading bank accounts...'),
            ],
          ),
        ),
        error: (_, _) =>
            _BankError(message: 'Unable to load bank accounts', retry: refresh),
        data: (connections) => RefreshIndicator(
          onRefresh: refresh,
          child: ResponsiveContent(
            maxWidth: 1120,
            child: ListView(
              padding: const EdgeInsets.all(FundWellTokens.space6),
              children: [
                Text(
                  'Connected accounts',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: FundWellTokens.space1),
                Text(
                  'Manage bank connections and restaurant assignments.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (readOnly) ...[
                  const SizedBox(height: FundWellTokens.space4),
                  const _DemoBankingNotice(),
                ],
                if (actionError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      actionError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: FundWellTokens.space4),
                Wrap(
                  spacing: FundWellTokens.space2,
                  runSpacing: FundWellTokens.space2,
                  children: [
                    FilledButton.icon(
                      key: const Key('connect-bank'),
                      onPressed: busy || readOnly ? null : connect,
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: const Text('Connect bank'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('bank-automation-rules'),
                      onPressed: readOnly
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MerchantRulesScreen(),
                              ),
                            ),
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Automatic rules'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (connections.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No bank accounts connected.'),
                    ),
                  )
                else
                  for (final connection in connections)
                    _ConnectionCard(
                      connection: connection,
                      onReconnect: () => connect(connection),
                      readOnly: readOnly,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MerchantRulesScreen extends ConsumerWidget {
  const MerchantRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(merchantRulesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Automatic Bank Rules')),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _BankError(
          message: 'Unable to load automatic expense rules',
          retry: () => ref.invalidate(merchantRulesProvider),
        ),
        data: (items) => items.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No automatic expense rules yet. You can create one while reviewing a bank transaction.',
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Remembered decisions are scoped to this restaurant, bank account, merchant, direction, and transaction type. Turning off a rule never changes completed records.',
                  ),
                  const SizedBox(height: 12),
                  for (final rule in items)
                    Card(
                      child: SwitchListTile(
                        key: ValueKey('merchant-rule-${rule.id}'),
                        title: Text(rule.merchant),
                        subtitle: Text(
                          [
                            if (rule.vendorName != null) rule.vendorName!,
                            if (rule.categoryName != null) rule.categoryName!,
                            rule.decision == 'PERSONAL_TRANSFER'
                                ? 'Personal / Transfer'
                                : 'Business expense',
                            if (rule.direction != null)
                              _status(rule.direction!),
                            if (rule.autoConfirm &&
                                rule.minimumAmount != null &&
                                rule.maximumAmount != null)
                              '${_currency(rule.minimumAmount!)}–${_currency(rule.maximumAmount!)}',
                            rule.decision == 'PERSONAL_TRANSFER'
                                ? 'Automatically excluded when eligible'
                                : rule.autoConfirm
                                ? 'Automatically added when eligible'
                                : 'Suggestions only',
                          ].join(' · '),
                        ),
                        value: rule.active,
                        onChanged: (active) async {
                          await ref
                              .read(bankingRepositoryProvider)
                              .updateMerchantRule(rule.id, active: active);
                          ref.invalidate(merchantRulesProvider);
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ConnectionCard extends ConsumerStatefulWidget {
  const _ConnectionCard({
    required this.connection,
    required this.onReconnect,
    required this.readOnly,
  });
  final BankConnectionData connection;
  final Future<void> Function() onReconnect;
  final bool readOnly;
  @override
  ConsumerState<_ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends ConsumerState<_ConnectionCard> {
  bool busy = false;
  String? error;

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      ref.invalidate(bankConnectionsProvider);
      ref.invalidate(bankTransactionsProvider);
      ref.invalidate(bankTransactionsAwaitingReviewProvider);
      ref.invalidate(bankSyncStatusProvider);
      ref.invalidate(dashboardProvider);
      ref.invalidate(previousDashboardProvider);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to update this bank connection. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.connection.institutionName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _StatusChip(widget.connection.status),
            ],
          ),
          if (widget.connection.lastSyncAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Last synced ${_date(widget.connection.lastSyncAt!)}',
              ),
            ),
          if (widget.connection.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(widget.connection.lastError!),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const Divider(),
          for (final account in widget.connection.accounts)
            _AccountTile(account: account, readOnly: widget.readOnly),
          Wrap(
            spacing: 8,
            children: [
              if (widget.connection.status == 'NEEDS_ATTENTION')
                FilledButton.icon(
                  key: const Key('reconnect-bank'),
                  onPressed: busy || widget.readOnly
                      ? null
                      : () => run(widget.onReconnect),
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('Reconnect'),
                ),
              OutlinedButton.icon(
                onPressed:
                    busy ||
                        widget.readOnly ||
                        widget.connection.status == 'SYNCING' ||
                        widget.connection.status == 'DISCONNECTED'
                    ? null
                    : () => run(
                        () => ref
                            .read(bankingRepositoryProvider)
                            .sync(widget.connection.id),
                      ),
                icon: const Icon(Icons.sync),
                label: const Text('Sync now'),
              ),
              TextButton(
                onPressed:
                    busy ||
                        widget.readOnly ||
                        widget.connection.status == 'DISCONNECTED'
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Disconnect bank?'),
                            content: const Text(
                              'Imported transaction history will remain, but future syncing will stop.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Disconnect'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await run(
                            () => ref
                                .read(bankingRepositoryProvider)
                                .disconnect(widget.connection.id),
                          );
                        }
                      },
                child: const Text('Disconnect'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account, required this.readOnly});
  final BankAccountData account;
  final bool readOnly;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(availableLocationsProvider);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(account.name),
      subtitle: Text(
        '${account.mask == null ? '' : '•••• ${account.mask} • '}${account.restaurantLocationName ?? 'Needs location assignment'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: readOnly
          ? null
          : () async {
              final selected = await showModalBottomSheet<RestaurantLocation>(
                context: context,
                showDragHandle: true,
                builder: (sheetContext) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ListTile(title: Text('Assign restaurant location')),
                      for (final location in locations)
                        ListTile(
                          title: Text(location.name),
                          onTap: () => Navigator.pop(sheetContext, location),
                        ),
                    ],
                  ),
                ),
              );
              if (selected != null) {
                await ref
                    .read(bankingRepositoryProvider)
                    .assignAccount(account.id, selected.id);
                ref.invalidate(bankConnectionsProvider);
                ref.invalidate(bankTransactionsProvider);
                ref.invalidate(bankTransactionsAwaitingReviewProvider);
              }
            },
    );
  }
}

class BankTransactionsScreen extends ConsumerStatefulWidget {
  const BankTransactionsScreen({super.key});
  @override
  ConsumerState<BankTransactionsScreen> createState() =>
      _BankTransactionsScreenState();
}

class _BankTransactionsScreenState
    extends ConsumerState<BankTransactionsScreen> {
  final selected = <String>{};
  final searchController = TextEditingController();
  String search = '';
  String? accountFilter;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> bulkReview({required bool ignored}) async {
    final location = ref.read(activeLocationProvider);
    if (location == null || selected.isEmpty) return;
    String? vendorId;
    String? categoryId;
    if (!ignored) {
      final lookups = await ref.read(expenseLookupsProvider.future);
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Add ${selected.length} transactions to Expenses'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: lookups.categories
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => categoryId = value),
                ),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Vendor (optional)',
                  ),
                  items: lookups.vendors
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => vendorId = value),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This counts the selected purchases as business expenses in your financial reports. It will not affect your bank account. Only posted, eligible transactions can be added.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: categoryId == null
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('Add Selected to Expenses'),
              ),
            ],
          ),
        ),
      );
      if (proceed != true) return;
    }
    BulkReviewResult result;
    try {
      result = await ref
          .read(bankingRepositoryProvider)
          .bulkReview(
            selected.toList(),
            vendorId: vendorId,
            categoryId: categoryId,
            locationId: location.id,
            ignored: ignored,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ignored
                  ? 'Unable to ignore the selected transactions. Nothing was removed from the review list.'
                  : 'Unable to add the selected transactions to Expenses. Nothing was removed from the review list.',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      selected
        ..clear()
        ..addAll(result.failedIds);
    });
    if (result.confirmedCount > 0) _invalidateBankDerivedProviders(ref);
    if (result.failedIds.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.confirmedCount} completed; ${result.failedIds.length} could not be completed. The remaining transactions are still selected.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(bankTransactionFilterProvider);
    final state = ref.watch(bankTransactionsProvider);
    final sync = ref.watch(bankSyncStatusProvider);
    final connections = ref.watch(bankConnectionsProvider);
    final range = ref.watch(dateRangeProvider);
    final readOnly = ref.watch(demoModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bank Transactions')),
      body: ResponsiveContent(
        maxWidth: 1240,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Transaction activity',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text(
                              '${_date(range.startDate)} – ${_date(range.endDate)}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (readOnly)
                        const Chip(
                          avatar: Icon(Icons.visibility_outlined, size: 17),
                          label: Text('Demo · View only'),
                        ),
                    ],
                  ),
                  const SizedBox(height: FundWellTokens.space4),
                  TextField(
                    key: const Key('bank-transaction-search'),
                    controller: searchController,
                    onChanged: (value) =>
                        setState(() => search = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search merchant or description',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: search.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                searchController.clear();
                                setState(() => search = '');
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: FundWellTokens.space3),
                  LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: FundWellTokens.space2,
                      runSpacing: FundWellTokens.space2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: constraints.maxWidth < 620
                              ? constraints.maxWidth
                              : 430,
                          child: SegmentedButton<BankTransactionFilter>(
                            segments: const [
                              ButtonSegment(
                                value: BankTransactionFilter.needsReview,
                                label: Text('Needs Review'),
                              ),
                              ButtonSegment(
                                value: BankTransactionFilter.matched,
                                label: Text('Added / Linked'),
                              ),
                              ButtonSegment(
                                value: BankTransactionFilter.all,
                                label: Text('All'),
                              ),
                            ],
                            selected: {filter},
                            onSelectionChanged: (value) =>
                                ref
                                    .read(
                                      bankTransactionFilterProvider.notifier,
                                    )
                                    .state = value
                                    .first,
                          ),
                        ),
                        _AccountFilter(
                          value: accountFilter,
                          accounts:
                              connections.valueOrNull
                                  ?.expand((connection) => connection.accounts)
                                  .toList() ??
                              const [],
                          onChanged: (value) =>
                              setState(() => accountFilter = value),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (sync.valueOrNull?.inProgress == true)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Card(
                  child: ListTile(
                    leading: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    title: Text('Bank synchronization is still in progress.'),
                    subtitle: Text(
                      'Imported transactions will appear automatically when they are available.',
                    ),
                  ),
                ),
              ),
            if (selected.isNotEmpty && !readOnly)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Card(
                  child: ListTile(
                    title: Text('${selected.length} selected'),
                    subtitle: const Text(
                      'Bulk actions never include pending, matched, or deposit transactions.',
                    ),
                    trailing: Wrap(
                      children: [
                        TextButton(
                          onPressed: () => bulkReview(ignored: true),
                          child: const Text('Ignore'),
                        ),
                        FilledButton(
                          onPressed: () => bulkReview(ignored: false),
                          child: const Text('Add Selected to Expenses'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: state.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => _BankError(
                  message: 'Unable to load bank transactions',
                  retry: () => ref.refresh(bankTransactionsProvider.future),
                ),
                data: (items) {
                  final visibleItems = items
                      .where(
                        (item) =>
                            !item.postedDate.isBefore(range.startDate) &&
                            item.postedDate.isBefore(
                              range.endDate.add(const Duration(days: 1)),
                            ) &&
                            (accountFilter == null ||
                                item.bankAccountId == accountFilter) &&
                            (search.isEmpty ||
                                item.merchant.toLowerCase().contains(search) ||
                                item.description.toLowerCase().contains(
                                  search,
                                )),
                      )
                      .toList();
                  if (visibleItems.isEmpty) {
                    return _BankTransactionsEmptyState(
                      filter: filter,
                      allFilteredItems: items,
                      sync: sync.valueOrNull,
                      connections: connections.valueOrNull ?? const [],
                    );
                  }
                  return LayoutBuilder(
                    builder: (context, constraints) => ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      itemCount: visibleItems.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _TransactionRow(
                        item: visibleItems[index],
                        desktop: constraints.maxWidth >= 900,
                        readOnly: readOnly,
                        selected: selected.contains(visibleItems[index].id),
                        onSelected: (value) => setState(
                          () => value
                              ? selected.add(visibleItems[index].id)
                              : selected.remove(visibleItems[index].id),
                        ),
                        onOpen: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          constraints: constraints.maxWidth >= 900
                              ? const BoxConstraints(maxWidth: 720)
                              : null,
                          builder: (_) => TransactionReviewSheet(
                            transaction: visibleItems[index],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoBankingNotice extends StatelessWidget {
  const _DemoBankingNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(FundWellTokens.space4),
    decoration: BoxDecoration(
      color: FundWellTokens.surfaceSubtle,
      borderRadius: BorderRadius.circular(FundWellTokens.radius),
      border: Border.all(color: FundWellTokens.outline),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.visibility_outlined, size: 20),
        SizedBox(width: FundWellTokens.space3),
        Expanded(
          child: Text(
            'Public demo is view only. Explore accounts and transactions; changes are disabled.',
          ),
        ),
      ],
    ),
  );
}

class _AccountFilter extends StatelessWidget {
  const _AccountFilter({
    required this.value,
    required this.accounts,
    required this.onChanged,
  });

  final String? value;
  final List<BankAccountData> accounts;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final matches = accounts.where((account) => account.id == value);
    final label = matches.isEmpty ? 'All accounts' : matches.first.name;
    return PopupMenuButton<String?>(
      tooltip: 'Filter by account',
      onSelected: onChanged,
      itemBuilder: (_) => [
        const PopupMenuItem(value: null, child: Text('All accounts')),
        for (final account in accounts)
          PopupMenuItem(value: account.id, child: Text(account.name)),
      ],
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: FundWellTokens.surface,
          borderRadius: BorderRadius.circular(FundWellTokens.radiusSmall),
          border: Border.all(color: FundWellTokens.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_outlined, size: 18),
            const SizedBox(width: 8),
            Text(label),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.item,
    required this.desktop,
    required this.readOnly,
    required this.selected,
    required this.onSelected,
    required this.onOpen,
  });

  final BankTransactionData item;
  final bool desktop, readOnly, selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onOpen;

  bool get selectable =>
      !readOnly &&
      item.status == 'NEEDS_REVIEW' &&
      !item.pending &&
      item.isOutgoing &&
      item.suggestedInvoice == null;

  String get amount => _currency(item.amount.abs());

  @override
  Widget build(BuildContext context) {
    final amountColor = item.isOutgoing
        ? Theme.of(context).colorScheme.onSurface
        : FundWellTokens.positive;
    final description = item.description == item.merchant
        ? null
        : item.description;
    final details = [
      _date(item.postedDate),
      if (item.bankAccountName != null) item.bankAccountName!,
    ].join(' · ');
    final category = item.invoiceNumber != null
        ? 'Invoice ${item.invoiceNumber}'
        : item.categoryName;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(FundWellTokens.radius),
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? 16 : 14,
            vertical: desktop ? 14 : 16,
          ),
          child: desktop
              ? Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: selectable
                          ? Checkbox(
                              value: selected,
                              onChanged: (value) => onSelected(value ?? false),
                            )
                          : const Icon(Icons.receipt_long_outlined, size: 19),
                    ),
                    Expanded(
                      flex: 4,
                      child: _TransactionIdentity(
                        merchant: item.merchant,
                        description: description,
                      ),
                    ),
                    Expanded(flex: 2, child: Text(details)),
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _StatusChip(item.pending ? 'PENDING' : item.status),
                            if (category != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  category,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 132,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            amount,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: amountColor),
                          ),
                          Text(
                            item.isOutgoing ? 'Money out' : 'Money in',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (selectable)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Checkbox(
                              value: selected,
                              onChanged: (value) => onSelected(value ?? false),
                            ),
                          ),
                        Expanded(
                          child: _TransactionIdentity(
                            merchant: item.merchant,
                            description: description,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              amount,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: amountColor),
                            ),
                            Text(
                              item.isOutgoing ? 'Money out' : 'Money in',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusChip(item.pending ? 'PENDING' : item.status),
                        Text(
                          details,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (category != null)
                          Text(
                            category,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _TransactionIdentity extends StatelessWidget {
  const _TransactionIdentity({required this.merchant, this.description});
  final String merchant;
  final String? description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        merchant,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (description != null)
        Text(
          description!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
    ],
  );
}

class _BankTransactionsEmptyState extends ConsumerWidget {
  const _BankTransactionsEmptyState({
    required this.filter,
    required this.allFilteredItems,
    required this.sync,
    required this.connections,
  });

  final BankTransactionFilter filter;
  final List<BankTransactionData> allFilteredItems;
  final BankSyncStatus? sync;
  final List<BankConnectionData> connections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeLocationId = ref.watch(activeLocationProvider)?.id;
    final assignedElsewhere = connections
        .expand((connection) => connection.accounts)
        .any(
          (account) =>
              account.active &&
              account.restaurantLocationId != null &&
              account.restaurantLocationId != activeLocationId,
        );
    final assignedHere = connections
        .expand((connection) => connection.accounts)
        .any(
          (account) =>
              account.active &&
              account.restaurantLocationId == activeLocationId,
        );
    final message = switch (sync?.state) {
      BankImportState.pending ||
      BankImportState.importing ||
      BankImportState.partiallyComplete =>
        'Bank synchronization is still in progress. Transactions will appear automatically.',
      _ when assignedElsewhere && !assignedHere =>
        'Connected bank accounts are assigned to another restaurant. Switch restaurants or update the account assignment.',
      BankImportState.complete when sync?.transactionCount == 0 =>
        'Synchronization completed, but no bank transactions were found for this restaurant.',
      _ when allFilteredItems.isNotEmpty =>
        'No bank transactions were found within the selected date range.',
      _ when filter == BankTransactionFilter.needsReview =>
        'No transactions need review for this restaurant and period.',
      _ when filter == BankTransactionFilter.matched =>
        'No transactions were added to Expenses or linked to invoices for this period.',
      _ => 'No bank transactions were found for this restaurant and period.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class TransactionReviewSheet extends ConsumerStatefulWidget {
  const TransactionReviewSheet({required this.transaction, super.key});
  final BankTransactionData transaction;
  @override
  ConsumerState<TransactionReviewSheet> createState() =>
      _TransactionReviewSheetState();
}

class _SimilarTransactionSelectionDialog extends StatefulWidget {
  const _SimilarTransactionSelectionDialog({
    required this.transactions,
    required this.openedTransactionId,
    required this.decision,
  });

  final List<BankTransactionData> transactions;
  final String openedTransactionId;
  final BankReviewDecision decision;

  @override
  State<_SimilarTransactionSelectionDialog> createState() =>
      _SimilarTransactionSelectionDialogState();
}

class _SimilarTransactionSelectionDialogState
    extends State<_SimilarTransactionSelectionDialog> {
  late final Set<String> selectedIds = {widget.openedTransactionId};

  String get decisionLabel => switch (widget.decision) {
    BankReviewDecision.expense => 'Add to Expenses',
    BankReviewDecision.personalTransfer => 'Personal / Transfer',
    BankReviewDecision.reviewLater => 'Review Later',
  };

  @override
  Widget build(BuildContext context) {
    final transactions = widget.transactions;
    final selected = transactions
        .where((transaction) => selectedIds.contains(transaction.id))
        .toList();
    final selectedTotal = selected.fold<double>(
      0,
      (sum, transaction) => sum + transaction.amount,
    );
    final allTotal = transactions.fold<double>(
      0,
      (sum, transaction) => sum + transaction.amount,
    );
    final dates = transactions.map((item) => item.postedDate).toList()..sort();
    final direction = transactions.first.isOutgoing ? 'Outgoing' : 'Incoming';
    final directionHelp = transactions.first.isOutgoing
        ? 'Money leaving your bank'
        : 'Money entering your bank';
    final count = selectedIds.length;
    final actionLabel =
        'Apply to $count ${count == 1 ? 'Transaction' : 'Transactions'}';

    return AlertDialog(
      title: Text(transactions.first.merchant),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$direction — $directionHelp',
              key: const Key('group-direction'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text('${transactions.length} matching transactions'),
            Text(
              '${_currency(allTotal)} total • ${_date(dates.first)}–${_date(dates.last)}',
            ),
            Text('Decision: $decisionLabel'),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  key: const Key('select-all-similar'),
                  onPressed: () => setState(
                    () => selectedIds.addAll(
                      transactions.map((transaction) => transaction.id),
                    ),
                  ),
                  child: const Text('Select All'),
                ),
                TextButton(
                  key: const Key('deselect-all-similar'),
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () => setState(selectedIds.clear),
                  child: const Text('Deselect All'),
                ),
              ],
            ),
            Text(
              'Selected: $count of ${transactions.length} • ${_currency(selectedTotal)}',
              key: const Key('group-selection-summary'),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final item = transactions[index];
                  return CheckboxListTile(
                    key: Key('similar-transaction-${item.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: selectedIds.contains(item.id),
                    onChanged: (checked) => setState(() {
                      checked == true
                          ? selectedIds.add(item.id)
                          : selectedIds.remove(item.id);
                    }),
                    title: Text(_date(item.postedDate)),
                    subtitle: Text(
                      '${item.merchant} • ${item.pending ? 'Waiting to Post' : 'Needs Review'}',
                    ),
                    secondary: Text(_currency(item.amount)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm-similar-selection'),
          onPressed: selectedIds.isEmpty
              ? null
              : () => Navigator.pop(context, Set<String>.of(selectedIds)),
          child: Text(actionLabel),
        ),
      ],
    );
  }
}

class _TransactionReviewSheetState
    extends ConsumerState<TransactionReviewSheet> {
  String? vendorId, categoryId, locationId;
  String? actionError;
  bool createRule = false, autoConfirmFuture = false, saving = false;
  @override
  void initState() {
    super.initState();
    vendorId = widget.transaction.vendorId;
    categoryId = widget.transaction.categoryId;
    locationId = widget.transaction.restaurantLocationId;
  }

  Future<void> save(BankReviewDecision decision) async {
    setState(() {
      saving = true;
      actionError = null;
    });
    try {
      final repository = ref.read(bankingRepositoryProvider);
      var ids = <String>[widget.transaction.id];
      var groupedSelection = false;
      if (decision != BankReviewDecision.reviewLater) {
        final similar = await repository.similarTransactions(
          widget.transaction.id,
        );
        if (similar.length > 1 && mounted) {
          final selectedIds = await showDialog<Set<String>>(
            context: context,
            builder: (_) => _SimilarTransactionSelectionDialog(
              transactions: similar,
              openedTransactionId: widget.transaction.id,
              decision: decision,
            ),
          );
          if (selectedIds == null) return;
          ids = selectedIds.toList();
          groupedSelection = true;
        }
      }
      if (ids.length == 1 && !groupedSelection) {
        await repository.review(
          ids.single,
          vendorId: vendorId,
          categoryId: categoryId,
          locationId: locationId,
          decision: decision,
          createRule: createRule,
          autoConfirmFuture: autoConfirmFuture,
          minimumAmount: autoConfirmFuture
              ? widget.transaction.amount * .5
              : null,
          maximumAmount: autoConfirmFuture
              ? widget.transaction.amount * 2
              : null,
        );
      } else {
        final result = await repository.bulkReview(
          ids,
          vendorId: vendorId,
          categoryId: categoryId,
          locationId: locationId!,
          decision: decision,
          createRule: createRule,
          autoConfirmFuture: autoConfirmFuture,
          minimumAmount: autoConfirmFuture
              ? widget.transaction.amount * .5
              : null,
          maximumAmount: autoConfirmFuture
              ? widget.transaction.amount * 2
              : null,
          groupAnchorId: groupedSelection ? widget.transaction.id : null,
        );
        if (result.confirmedCount == 0) {
          if (mounted) {
            setState(
              () => actionError =
                  'None of the selected transactions could be completed. They still need review.',
            );
          }
          return;
        }
        if (result.failedIds.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${result.confirmedCount} completed; ${result.failedIds.length} still need review.',
              ),
            ),
          );
        }
      }
      _invalidateBankDerivedProviders(ref);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => actionError =
              'Unable to complete this review. No unsuccessful transaction was removed from review.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> confirm() async {
    setState(() {
      saving = true;
      actionError = null;
    });
    try {
      await ref
          .read(bankingRepositoryProvider)
          .confirmMatch(
            widget.transaction.id,
            widget.transaction.suggestedInvoice!.id,
          );
      _invalidateBankDerivedProviders(ref);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => actionError =
              'Unable to link this transaction to the invoice. No review status was changed.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> reject() async {
    setState(() {
      saving = true;
      actionError = null;
    });
    try {
      await ref
          .read(bankingRepositoryProvider)
          .rejectMatch(widget.transaction.id);
      _invalidateBankDerivedProviders(ref);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => actionError =
              'Unable to reject this invoice match. No review status was changed.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> reverseMatch({required bool invoicePayment}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          invoicePayment
              ? 'Remove invoice payment link?'
              : 'Remove from Expenses?',
        ),
        content: Text(
          invoicePayment
              ? 'The invoice will be preserved. This bank transaction will return to Needs Review.'
              : 'A bank-created expense will be removed. An expense entered separately will be preserved, and this transaction will return to Needs Review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Match'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              invoicePayment ? 'Remove Payment Link' : 'Remove from Expenses',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      saving = true;
      actionError = null;
    });
    try {
      await ref.read(bankingRepositoryProvider).reverse(widget.transaction.id);
      _invalidateBankDerivedProviders(ref);
      if (mounted) {
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              invoicePayment
                  ? 'Invoice payment link removed. Transaction returned to Needs Review.'
                  : 'Expense match removed. Transaction returned to Needs Review.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => actionError = invoicePayment
              ? 'Unable to remove this invoice payment link safely.'
              : 'Unable to remove this transaction from Expenses safely.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(demoModeProvider)) {
      return _ReadOnlyTransactionDetails(transaction: widget.transaction);
    }
    final lookups = ref.watch(expenseLookupsProvider);
    final locations = ref.watch(availableLocationsProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: lookups.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Text('Unable to load review options'),
          data: (options) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.transaction.merchant,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  '${_currency(widget.transaction.amount)} • ${_date(widget.transaction.postedDate)}',
                ),
                const SizedBox(height: 8),
                Text('Raw description: ${widget.transaction.description}'),
                Text(
                  'Categorization: ${_status(widget.transaction.categorizationSource)}',
                ),
                if (widget.transaction.pending)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Pending transaction — it can be categorized now, but no expense will be created until it posts.',
                    ),
                  ),
                if (actionError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      actionError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (widget.transaction.suggestedInvoice != null &&
                    widget.transaction.status != 'MATCHED_INVOICE')
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.transaction.matchConfidence} invoice match',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Invoice ${widget.transaction.suggestedInvoice!.number ?? widget.transaction.suggestedInvoice!.id} • ${_currency(widget.transaction.suggestedInvoice!.total)}',
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton(
                                onPressed: saving || widget.transaction.pending
                                    ? null
                                    : confirm,
                                child: const Text('Confirm Match'),
                              ),
                              TextButton(
                                onPressed: saving ? null : reject,
                                child: const Text('Reject'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  key: const Key('review-location'),
                  initialValue: locationId,
                  decoration: const InputDecoration(
                    labelText: 'Restaurant location',
                  ),
                  items: locations
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => locationId = value),
                ),
                if (widget.transaction.isOutgoing) ...[
                  DropdownButtonFormField<String>(
                    key: const Key('review-vendor'),
                    initialValue: vendorId,
                    decoration: const InputDecoration(labelText: 'Vendor'),
                    items: options.vendors
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => vendorId = value),
                  ),
                  DropdownButtonFormField<String>(
                    key: const Key('review-category'),
                    initialValue: categoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: options.categories
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => categoryId = value),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Remember this business for future transactions',
                  ),
                  value: createRule,
                  onChanged: (value) => setState(() => createRule = value),
                ),
                if (widget.transaction.isOutgoing)
                  SwitchListTile(
                    key: const Key('auto-confirm-future'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Automatically Track Future Expenses'),
                    subtitle: const Text(
                      'Optional and off by default. FundWell can automatically add future purchases from this approved business to Expenses. Unusual or uncertain purchases still require review.',
                    ),
                    value: autoConfirmFuture,
                    onChanged: (value) => setState(() {
                      autoConfirmFuture = value;
                      if (value) createRule = true;
                    }),
                  ),
                if (widget.transaction.status == 'MATCHED_EXPENSE')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'This removes the bank transaction\'s expense match and returns it to Needs Review. FundWell removes a bank-created expense, but preserves an expense that was entered separately.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const Key('reverse-reconciliation'),
                        onPressed: saving
                            ? null
                            : () => reverseMatch(invoicePayment: false),
                        icon: const Icon(Icons.undo),
                        label: const Text('Remove from Expenses'),
                      ),
                    ],
                  )
                else if (widget.transaction.status == 'MATCHED_INVOICE')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'This removes the payment link from the invoice. The bank transaction remains and returns to Needs Review.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const Key('reverse-invoice-match'),
                        onPressed: saving
                            ? null
                            : () => reverseMatch(invoicePayment: true),
                        icon: const Icon(Icons.link_off),
                        label: const Text('Remove Invoice Payment Link'),
                      ),
                    ],
                  )
                else if (widget.transaction.status == 'IGNORED')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'This transaction is excluded from Expenses and Revenue. Return it to Needs Review if that decision was incorrect.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const Key('restore-ignored-transaction'),
                        onPressed: saving
                            ? null
                            : () async {
                                setState(() => saving = true);
                                try {
                                  await ref
                                      .read(bankingRepositoryProvider)
                                      .reverse(widget.transaction.id);
                                  _invalidateBankDerivedProviders(ref);
                                  if (mounted) Navigator.pop(this.context);
                                } catch (_) {
                                  if (mounted) {
                                    setState(
                                      () => actionError =
                                          'Unable to return this transaction to Needs Review safely.',
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => saving = false);
                                }
                              },
                        icon: const Icon(Icons.undo),
                        label: const Text('Return to Needs Review'),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.transaction.isIncoming) ...[
                        const Text(
                          'Incoming — Money entering your bank. You can mark this as Personal / Transfer or review it later. It will not be counted as restaurant revenue automatically.',
                          key: Key('incoming-review-guidance'),
                        ),
                        const SizedBox(height: 10),
                      ] else if (!widget.transaction.pending) ...[
                        const Text(
                          'Adding this counts the transaction as a business expense in your financial reports. It will not affect your bank account.',
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving
                                  ? null
                                  : () => save(
                                      BankReviewDecision.personalTransfer,
                                    ),
                              child: const Text('Personal / Transfer'),
                            ),
                          ),
                          if (widget.transaction.isOutgoing) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: saving
                                    ? null
                                    : () => save(BankReviewDecision.expense),
                                child: Text(
                                  widget.transaction.pending
                                      ? 'Save — Waiting to Post'
                                      : 'Add to Expenses',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      TextButton(
                        onPressed: saving
                            ? null
                            : () => save(BankReviewDecision.reviewLater),
                        child: const Text('Review Later'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyTransactionDetails extends StatelessWidget {
  const _ReadOnlyTransactionDetails({required this.transaction});
  final BankTransactionData transaction;

  @override
  Widget build(BuildContext context) {
    final linkedRecord = transaction.invoiceNumber != null
        ? 'Invoice ${transaction.invoiceNumber}'
        : transaction.categoryName ?? 'Not yet classified';
    final signedAmount = _currency(transaction.amount.abs());
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              transaction.merchant,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              signedAmount,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(transaction.isOutgoing ? 'Money out' : 'Money in'),
            const SizedBox(height: 20),
            _DetailLine(label: 'Date', value: _date(transaction.postedDate)),
            _DetailLine(
              label: 'Bank account',
              value: transaction.bankAccountName ?? 'Bank account',
            ),
            _DetailLine(
              label: 'Status',
              value: _status(
                transaction.pending ? 'PENDING' : transaction.status,
              ),
            ),
            _DetailLine(label: 'Category or link', value: linkedRecord),
            _DetailLine(
              label: 'Bank description',
              value: transaction.description,
            ),
            const SizedBox(height: 16),
            const _DemoBankingNotice(),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.titleSmall),
        ),
      ],
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final (foreground, background) = switch (status) {
      'NEEDS_REVIEW' ||
      'PENDING' => (FundWellTokens.warning, const Color(0xFFFFF4DF)),
      'MATCHED_EXPENSE' ||
      'MATCHED_INVOICE' ||
      'CONNECTED' => (FundWellTokens.positive, const Color(0xFFEAF6F0)),
      'NEEDS_ATTENTION' ||
      'ERROR' => (FundWellTokens.danger, const Color(0xFFFCEDEA)),
      _ => (FundWellTokens.mutedInk, FundWellTokens.surfaceSubtle),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _status(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BankError extends StatelessWidget {
  const _BankError({required this.message, required this.retry});
  final String message;
  final FutureOr<void> Function() retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

String _status(String value) => switch (value) {
  'MATCHED_EXPENSE' => 'Added to Expenses',
  'MATCHED_INVOICE' => 'Matched to Invoice',
  'NEEDS_REVIEW' => 'Needs Review',
  'IGNORED' => 'Personal / Transfer',
  _ =>
    value
        .toLowerCase()
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' '),
};
String _date(DateTime value) => '${value.month}/${value.day}/${value.year}';
String _currency(double value) =>
    '${value < 0 ? '-' : ''}\$${value.abs().toStringAsFixed(2)}';
