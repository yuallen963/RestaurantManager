import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/foundation.dart';
import 'foundation.dart';

class PosIntegrationsScreen extends ConsumerStatefulWidget {
  const PosIntegrationsScreen({super.key});
  @override
  ConsumerState<PosIntegrationsScreen> createState() =>
      _PosIntegrationsScreenState();
}

class _PosIntegrationsScreenState extends ConsumerState<PosIntegrationsScreen>
    with WidgetsBindingObserver {
  bool busy = false;
  String? message;
  String get organizationId => ref.read(activeLocationProvider)!.organizationId;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(activeLocationProvider) != null) {
      ref.invalidate(posConnectionsProvider(organizationId));
    }
  }

  Future<void> action(Future<void> Function() callback, String success) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await callback();
      ref.invalidate(posConnectionsProvider(organizationId));
      if (mounted) {
        setState(() => message = success);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Unable to complete the Square action. Try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(activeLocationProvider);
    if (location == null) {
      return const Scaffold(
        body: Center(child: Text('No restaurant locations available')),
      );
    }
    final state = ref.watch(posConnectionsProvider(location.organizationId));
    return Scaffold(
      appBar: AppBar(title: const Text('POS Integrations')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Unable to load POS integrations'),
              TextButton(
                onPressed: () => ref.invalidate(
                  posConnectionsProvider(location.organizationId),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (connections) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(message!, key: const Key('pos-message')),
              ),
            if (connections.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Square',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text('Not connected'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => action(
                                () => ref
                                    .read(posRepositoryProvider)
                                    .connect(location.organizationId),
                                'Complete authorization in Square, then return here.',
                              ),
                        child: const Text('Connect'),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...connections.map(
                (connection) => _connectionCard(context, connection),
              ),
          ],
        ),
      ),
    );
  }

  Widget _connectionCard(
    BuildContext context,
    PosConnectionData connection,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Square',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(_status(connection.status)),
          Text(connection.merchantName),
          if (connection.lastSyncAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Last synced: ${connection.lastSyncAt!.toLocal()}'),
            ),
          if (connection.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                connection.lastError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const Divider(height: 28),
          const Text(
            'Locations',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (connection.mappings.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No Square locations mapped'),
            ),
          ...connection.mappings.map((mapping) {
            final app = ref
                .watch(availableLocationsProvider)
                .where((item) => item.id == mapping.restaurantLocationId)
                .firstOrNull;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(mapping.providerLocationName),
              subtitle: Text('→ ${app?.name ?? 'Unavailable restaurant'}'),
            );
          }),
          if (connection.conflicts.isNotEmpty) ...[
            const Divider(),
            Text(
              '${connection.conflicts.length} revenue conflict${connection.conflicts.length == 1 ? '' : 's'} need review',
              key: const Key('revenue-conflict-warning'),
            ),
            ...connection.conflicts.map(
              (conflict) => Row(
                children: [
                  Expanded(
                    child: Text(
                      conflict.businessDate.toIso8601String().substring(0, 10),
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => action(
                            () => ref
                                .read(posRepositoryProvider)
                                .resolve(conflict.id, 'MANUAL'),
                            'Manual revenue kept.',
                          ),
                    child: const Text('Keep manual'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => action(
                            () => ref
                                .read(posRepositoryProvider)
                                .resolve(conflict.id, 'SQUARE'),
                            'Square revenue used.',
                          ),
                    child: const Text('Use Square'),
                  ),
                ],
              ),
            ),
          ],
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy ? null : () => _map(connection),
                child: const Text('Map location'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => action(
                        () =>
                            ref.read(posRepositoryProvider).sync(connection.id),
                        'Square sales synced.',
                      ),
                child: Text(
                  connection.status == 'SYNCING' ? 'Syncing…' : 'Sync now',
                ),
              ),
              TextButton(
                onPressed: busy ? null : () => _disconnect(connection),
                child: const Text('Disconnect'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  String _status(String status) => switch (status) {
    'CONNECTED' => 'Connected',
    'SYNCING' => 'Syncing',
    'REAUTH_REQUIRED' => 'Reconnect required',
    'ERROR' => 'Error',
    _ => status,
  };
  Future<void> _map(PosConnectionData connection) async {
    setState(() => busy = true);
    try {
      final square = await ref
          .read(posRepositoryProvider)
          .squareLocations(connection.id);
      if (!mounted) {
        return;
      }
      final selection =
          await showDialog<(SquareLocationData, RestaurantLocation)>(
            context: context,
            builder: (context) => _MappingDialog(
              squareLocations: square,
              restaurantLocations: ref.read(availableLocationsProvider),
            ),
          );
      if (selection != null) {
        await action(
          () => ref
              .read(posRepositoryProvider)
              .map(connection.id, selection.$1, selection.$2.id),
          'Location mapped and initial 90-day sync completed.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Unable to load Square locations. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _disconnect(PosConnectionData connection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Square?'),
        content: const Text(
          'Existing imported revenue will remain. Future automatic syncing will stop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await action(
        () => ref.read(posRepositoryProvider).disconnect(connection.id),
        'Square disconnected.',
      );
    }
  }
}

class _MappingDialog extends StatefulWidget {
  const _MappingDialog({
    required this.squareLocations,
    required this.restaurantLocations,
  });
  final List<SquareLocationData> squareLocations;
  final List<RestaurantLocation> restaurantLocations;
  @override
  State<_MappingDialog> createState() => _MappingDialogState();
}

class _MappingDialogState extends State<_MappingDialog> {
  SquareLocationData? square;
  RestaurantLocation? restaurant;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Map Square location'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<SquareLocationData>(
          decoration: const InputDecoration(labelText: 'Square location'),
          items: widget.squareLocations
              .map(
                (item) => DropdownMenuItem(value: item, child: Text(item.name)),
              )
              .toList(),
          onChanged: (value) => setState(() => square = value),
        ),
        DropdownButtonFormField<RestaurantLocation>(
          decoration: const InputDecoration(labelText: 'Restaurant location'),
          items: widget.restaurantLocations
              .map(
                (item) => DropdownMenuItem(value: item, child: Text(item.name)),
              )
              .toList(),
          onChanged: (value) => setState(() => restaurant = value),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: square == null || restaurant == null
            ? null
            : () => Navigator.pop(context, (square!, restaurant!)),
        child: const Text('Map'),
      ),
    ],
  );
}
