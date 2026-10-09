import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show AuthScreen, demoModeProvider;
import '../dashboard/foundation.dart';
import '../banking/bank_screens.dart';
import '../invoice_email/invoice_email_screen.dart';
import '../pos/pos_integrations_screen.dart';
import '../notifications/notification_screen.dart';
import 'foundation.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  bool _signingOut = false;

  Future<void> _selectLocation() async {
    final locations = ref.read(availableLocationsProvider);
    final active = ref.read(activeLocationProvider);
    final selected = await showModalBottomSheet<RestaurantLocation>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select restaurant',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            for (final location in locations)
              ListTile(
                key: ValueKey('location-${location.id}'),
                leading: Icon(
                  location.id == active?.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(location.name),
                onTap: () => Navigator.pop(context, location),
              ),
          ],
        ),
      ),
    );
    if (selected != null && selected.id != active?.id) {
      await ref
          .read(activeLocationControllerProvider.notifier)
          .select(selected);
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    await ref.read(moreRepositoryProvider).signOut();
    ref.invalidate(moreAccountProvider);
    ref.read(activeLocationControllerProvider.notifier).clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(activeLocationStateProvider);
    final account = ref.watch(moreAccountProvider);
    final metadata = ref.watch(appMetadataProvider);
    final demoMode = ref.watch(demoModeProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'More',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (demoMode) const Chip(label: Text('Demo Mode')),
          ],
        ),
        const SizedBox(height: 20),
        _Section(
          title: 'Integrations',
          child: _InfoTile(
            icon: Icons.point_of_sale_outlined,
            label: 'POS Integrations',
            value: 'Connect and sync Square sales',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PosIntegrationsScreen()),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Section(
          title: 'Alerts',
          child: _InfoTile(
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            value: 'Preferences and weekly digest',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationSettingsScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Section(
          title: 'Invoices',
          child: _InfoTile(
            icon: Icons.forward_to_inbox_outlined,
            label: 'Invoice Email',
            value: 'Forward vendor invoice attachments',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InvoiceEmailScreen()),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Section(
          title: 'Banking',
          child: _InfoTile(
            icon: Icons.account_balance_outlined,
            label: 'Bank Accounts',
            value: 'Connections, assignments, and sync',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BankAccountsScreen()),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Section(
          title: 'Restaurant',
          child: account.when(
            loading: () => const _LoadingRow(label: 'Loading restaurant...'),
            error: (_, _) => _ErrorContent(
              message: 'Unable to load restaurant information',
              onRetry: () {
                ref.invalidate(moreAccountProvider);
                ref.invalidate(activeLocationControllerProvider);
              },
            ),
            data: (value) => Column(
              children: [
                _InfoTile(
                  icon: Icons.business_outlined,
                  label: 'Organization',
                  value: value.organizationName,
                ),
                const Divider(height: 1),
                locationState.when(
                  loading: () =>
                      const _LoadingRow(label: 'Loading location...'),
                  error: (_, _) => _ErrorContent(
                    message: 'Unable to load restaurant locations',
                    onRetry: () =>
                        ref.invalidate(activeLocationControllerProvider),
                  ),
                  data: (state) => _InfoTile(
                    icon: Icons.storefront_outlined,
                    label: 'Location',
                    value: state.active?.name ?? 'No location available',
                    trailing: state.locations.length > 1
                        ? const Icon(Icons.chevron_right)
                        : null,
                    onTap: state.locations.length > 1 ? _selectLocation : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Section(
          title: 'Account',
          child: account.when(
            loading: () => const _LoadingRow(label: 'Loading account...'),
            error: (_, _) => _ErrorContent(
              message: 'Unable to load account information',
              onRetry: () => ref.invalidate(moreAccountProvider),
            ),
            data: (value) => Column(
              children: [
                _InfoTile(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: value.email,
                ),
                if (value.role != null) ...[
                  const Divider(height: 1),
                  _InfoTile(
                    icon: Icons.badge_outlined,
                    label: 'Role',
                    value: _formatRole(value.role!),
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign Out'),
                  textColor: Theme.of(context).colorScheme.error,
                  iconColor: Theme.of(context).colorScheme.error,
                  trailing: _signingOut
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  enabled: !_signingOut,
                  onTap: _signingOut ? null : _signOut,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Section(
          title: 'App',
          child: metadata.when(
            loading: () =>
                const _LoadingRow(label: 'Loading app information...'),
            error: (_, _) => _ErrorContent(
              message: 'Unable to load app information',
              onRetry: () => ref.invalidate(appMetadataProvider),
            ),
            data: (value) => Column(
              children: [
                _InfoTile(
                  icon: Icons.info_outline,
                  label: 'Version',
                  value: value.version,
                ),
                const Divider(height: 1),
                _InfoTile(
                  icon: Icons.numbers,
                  label: 'Build',
                  value: value.buildNumber,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _formatRole(String role) {
  if (role.isEmpty) return role;
  return '${role[0]}${role.substring(1).toLowerCase()}';
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: child),
    ],
  );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    subtitle: Text(value),
    trailing: trailing,
    onTap: onTap,
  );
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(label),
      ],
    ),
  );
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
