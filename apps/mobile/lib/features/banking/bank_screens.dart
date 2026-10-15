import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plaid_link_flutter/plaid_link_flutter.dart';

import '../dashboard/foundation.dart';
import '../expenses/foundation.dart';
import '../needs_attention/foundation.dart';
import '../vendors/foundation.dart';
import 'foundation.dart';

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
  PlaidLinkSession? session;

  Future<void> connect([BankConnectionData? existing]) async {
    final location = ref.read(activeLocationProvider);
    if (location == null) return;
    setState(() {
      busy = true;
      actionError = null;
    });
    try {
      final repository = ref.read(bankingRepositoryProvider);
      final setup = existing == null
          ? await repository.linkToken(location.organizationId)
          : await repository.reauthenticationLinkToken(existing.id);
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
      final completer = Completer<void>();
      session = await createPlaidLinkSession(
        LinkTokenConfiguration(
          token: setup.linkToken,
          onSuccess: (success) async {
            try {
              if (existing == null) {
                await repository.exchange(
                  location.organizationId,
                  success.publicToken,
                  location.id,
                );
              } else {
                await repository.completeReauthentication(existing.id);
              }
              await refresh();
              if (!completer.isCompleted) completer.complete();
            } catch (error, stack) {
              if (!completer.isCompleted) completer.completeError(error, stack);
            }
          },
          onExit: (exit) {
            if (completer.isCompleted) return;
            final message = exit.error?.errorMessage;
            message == null
                ? completer.complete()
                : completer.completeError(message);
          },
          onEvent: (_) {},
        ),
      );
      await session!.open(true);
      await completer.future;
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
  void dispose() {
    session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bankConnectionsProvider);
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
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
              FilledButton.icon(
                key: const Key('connect-bank'),
                onPressed: busy ? null : connect,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.account_balance),
                label: const Text('Connect bank'),
              ),
              TextButton.icon(
                key: const Key('bank-automation-rules'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MerchantRulesScreen(),
                  ),
                ),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Automatic Expense Rules'),
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
                  ),
            ],
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
      appBar: AppBar(title: const Text('Automatic Expense Rules')),
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
                    'Automatic expense tracking is optional. Turning off a rule never changes expenses already added.',
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
                            if (rule.autoConfirm &&
                                rule.minimumAmount != null &&
                                rule.maximumAmount != null)
                              '${_currency(rule.minimumAmount!)}–${_currency(rule.maximumAmount!)}',
                            rule.autoConfirm
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
  const _ConnectionCard({required this.connection, required this.onReconnect});
  final BankConnectionData connection;
  final Future<void> Function() onReconnect;
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
            _AccountTile(account: account),
          Wrap(
            spacing: 8,
            children: [
              if (widget.connection.status == 'NEEDS_ATTENTION')
                FilledButton.icon(
                  key: const Key('reconnect-bank'),
                  onPressed: busy ? null : () => run(widget.onReconnect),
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('Reconnect'),
                ),
              OutlinedButton.icon(
                onPressed:
                    busy ||
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
                onPressed: busy || widget.connection.status == 'DISCONNECTED'
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
  const _AccountTile({required this.account});
  final BankAccountData account;
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
      onTap: () async {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Bank Transactions')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
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
                  ref.read(bankTransactionFilterProvider.notifier).state =
                      value.first,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Selected period: ${_date(range.startDate)} – ${_date(range.endDate)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
          if (selected.isNotEmpty)
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
                          ),
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
                return ListView.builder(
                  itemCount: visibleItems.length,
                  itemBuilder: (context, index) {
                    final item = visibleItems[index];
                    return ListTile(
                      key: ValueKey('bank-transaction-${item.id}'),
                      leading:
                          item.status == 'NEEDS_REVIEW' &&
                              !item.pending &&
                              item.amount > 0 &&
                              item.suggestedInvoice == null
                          ? Checkbox(
                              value: selected.contains(item.id),
                              onChanged: (value) => setState(
                                () => value == true
                                    ? selected.add(item.id)
                                    : selected.remove(item.id),
                              ),
                            )
                          : CircleAvatar(
                              child: Icon(
                                item.status == 'MATCHED_INVOICE'
                                    ? Icons.link
                                    : Icons.help_outline,
                              ),
                            ),
                      title: Text(item.merchant),
                      subtitle: Text(
                        '${_date(item.postedDate)} • ${_status(item.status)}${item.categoryName == null ? '' : ' • ${item.categoryName}'}',
                      ),
                      trailing: Text(
                        _currency(item.amount),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (_) =>
                            TransactionReviewSheet(transaction: item),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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

  Future<void> save({bool ignored = false}) async {
    setState(() {
      saving = true;
      actionError = null;
    });
    try {
      await ref
          .read(bankingRepositoryProvider)
          .review(
            widget.transaction.id,
            vendorId: vendorId,
            categoryId: categoryId,
            locationId: locationId,
            ignored: ignored,
            createRule: createRule,
            autoConfirmFuture: autoConfirmFuture,
            minimumAmount: autoConfirmFuture
                ? widget.transaction.amount * .5
                : null,
            maximumAmount: autoConfirmFuture
                ? widget.transaction.amount * 2
                : null,
          );
      _invalidateBankDerivedProviders(ref);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => actionError =
              'Unable to add this transaction to Expenses. Review the selections and try again.',
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

  @override
  Widget build(BuildContext context) {
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
                if (widget.transaction.suggestedInvoice != null)
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Remember this business for future transactions',
                  ),
                  value: createRule,
                  onChanged: (value) => setState(() => createRule = value),
                ),
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
                        'This removes the expense from your financial reports. The original bank transaction remains and returns to Needs Review.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const Key('reverse-reconciliation'),
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
                                          'Unable to remove this transaction from Expenses safely.',
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => saving = false);
                                }
                              },
                        icon: const Icon(Icons.undo),
                        label: const Text('Remove from Expenses'),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!widget.transaction.pending) ...[
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
                                  : () => save(ignored: true),
                              child: const Text('Ignore'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: saving ? null : save,
                              child: Text(
                                widget.transaction.pending
                                    ? 'Save Category'
                                    : 'Add to Expenses',
                              ),
                            ),
                          ),
                        ],
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

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) => Chip(label: Text(_status(status)));
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
  'MATCHED_INVOICE' => 'Linked to Invoice',
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
