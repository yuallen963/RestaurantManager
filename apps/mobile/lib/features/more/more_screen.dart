import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart'
    show
        AccountSessionMode,
        AuthBootstrap,
        AuthScreen,
        accountSessionModeProvider,
        authDeviceIdProvider,
        authDeviceName,
        demoModeProvider,
        pendingAuthChallengeKey,
        pendingAuthChallengeMethodKey,
        pendingAuthChallengeModeKey,
        storage;
import '../auth/auth_screens.dart';
import '../dashboard/foundation.dart';
import '../expenses/foundation.dart';
import '../invoices/foundation.dart';
import '../revenue/foundation.dart';
import '../vendors/foundation.dart';
import '../needs_attention/foundation.dart';
import '../savings/foundation.dart';
import '../price_intelligence/foundation.dart';
import '../product_matches/foundation.dart';
import '../banking/foundation.dart';
import '../banking/bank_screens.dart';
import '../design/fundwell_theme.dart';
import '../invoice_email/invoice_email_screen.dart';
import '../pos/pos_integrations_screen.dart';
import '../notifications/notification_screen.dart';
import '../responsive.dart';
import 'foundation.dart';
import 'account_security_screen.dart';
import 'location_management_screen.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  bool _signingOut = false;
  bool _switchingAccount = false;

  void _clearAccountState() {
    ref.read(activeLocationControllerProvider.notifier).clear();
    ref.invalidate(activeLocationControllerProvider);
    ref.invalidate(moreAccountProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(previousDashboardProvider);
    ref.invalidate(expenseLookupsProvider);
    ref.invalidate(expenseListProvider);
    ref.invalidate(expenseDetailProvider);
    ref.invalidate(invoiceListProvider);
    ref.invalidate(invoiceDetailProvider);
    ref.invalidate(invoiceLineItemsProvider);
    ref.invalidate(revenueListProvider);
    ref.invalidate(revenueDetailProvider);
    ref.invalidate(vendorListProvider);
    ref.invalidate(vendorDetailProvider);
    ref.invalidate(needsAttentionProvider);
    ref.invalidate(savingsOpportunitiesProvider);
    ref.invalidate(priceChangesProvider);
    ref.invalidate(priceHistoryProvider);
    ref.invalidate(productMatchCandidatesProvider);
    ref.invalidate(productGroupsProvider);
    ref.invalidate(bankConnectionsProvider);
    ref.invalidate(bankTransactionsProvider);
    ref.invalidate(bankTransactionsAwaitingReviewProvider);
    ref.invalidate(allBankTransactionsProvider);
    ref.invalidate(unverifiedBankDepositsProvider);
    ref.invalidate(merchantRulesProvider);
    ref.invalidate(bankSyncStatusProvider);
    ref.invalidate(notificationListProvider);
    ref.invalidate(notificationPreferenceProvider);
  }

  Future<void> _enterPrivateAccount() async {
    if (kIsWeb) {
      await ref.read(privateAccountRepositoryProvider).signOut();
      ref.read(accountSessionModeProvider.notifier).state =
          AccountSessionMode.standard;
      _clearAccountState();
      if (mounted) context.go('/login');
      return;
    }
    Map<String, dynamic>? challenge;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PrivateAccountDialog(
        onSubmit: (code) async {
          challenge = await ref
              .read(privateAccountRepositoryProvider)
              .unlockPrivate(
                code,
                deviceId: await ref.read(authDeviceIdProvider.future),
                deviceName: authDeviceName,
              );
          if (challenge != null) return;
          ref.read(accountSessionModeProvider.notifier).state =
              AccountSessionMode.private;
          _clearAccountState();
        },
      ),
    );
    if (!mounted) return;
    if (challenge != null) {
      final challengeId = challenge!['challengeId'] as String;
      final method = challenge!['method'] as String;
      await storage.write(key: pendingAuthChallengeKey, value: challengeId);
      await storage.write(key: pendingAuthChallengeMethodKey, value: method);
      await storage.write(
        key: pendingAuthChallengeModeKey,
        value: AccountSessionMode.private.name,
      );
      if (!mounted) return;
      if (kIsWeb) {
        context.go('/');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LoginChallengeScreen(
            challengeId: challengeId,
            method: method,
            accountMode: AccountSessionMode.private,
          ),
        ),
      );
      return;
    }
    if (!mounted ||
        ref.read(accountSessionModeProvider) != AccountSessionMode.private) {
      return;
    }
    if (kIsWeb) {
      context.go('/');
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthBootstrap()),
        (_) => false,
      );
    }
  }

  Future<void> _returnToBeta() async {
    if (_switchingAccount) return;
    setState(() => _switchingAccount = true);
    try {
      if (kIsWeb) {
        await ref.read(privateAccountRepositoryProvider).returnToBeta();
        ref.read(accountSessionModeProvider.notifier).state =
            AccountSessionMode.demo;
        _clearAccountState();
        if (!mounted) return;
        context.go('/');
        return;
      }
      await ref.read(privateAccountRepositoryProvider).returnToBeta();
      ref.read(accountSessionModeProvider.notifier).state =
          AccountSessionMode.standard;
      _clearAccountState();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthBootstrap()),
        (_) => false,
      );
    } finally {
      if (mounted) setState(() => _switchingAccount = false);
    }
  }

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
    if (kIsWeb) {
      context.go('/login');
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(activeLocationStateProvider);
    final account = ref.watch(moreAccountProvider);
    final metadata = ref.watch(appMetadataProvider);
    final demoMode = ref.watch(demoModeProvider);
    final sessionMode = ref.watch(accountSessionModeProvider);

    return ResponsiveContent(
      child: ListView(
        key: const Key('more-list'),
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width >= FundWellBreakpoints.desktop
              ? 28
              : 16,
          24,
          MediaQuery.sizeOf(context).width >= FundWellBreakpoints.desktop
              ? 28
              : 16,
          36,
        ),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Text('More', style: Theme.of(context).textTheme.headlineMedium),
              if (demoMode)
                const Chip(
                  avatar: Icon(Icons.visibility_outlined, size: 18),
                  label: Text('Demo Mode'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Manage your restaurant, account, integrations, and application preferences.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: FundWellTokens.mutedInk),
          ),
          if (demoMode) ...[
            const SizedBox(height: 16),
            const _DemoAccountBanner(),
          ],
          const SizedBox(height: 24),
          _Section(
            title: 'Integrations',
            description:
                'Connect the services that bring financial activity into FundWell.',
            child: _InfoTile(
              icon: Icons.point_of_sale_outlined,
              label: 'POS Integrations',
              value: 'Connect and sync Square sales',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PosIntegrationsScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Application',
            description: 'Choose how FundWell keeps you informed.',
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
            description: 'Tools for collecting and reviewing vendor invoices.',
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
            description:
                'Manage secure bank connections and restaurant assignments.',
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
            description: 'Organization details and restaurant locations.',
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
                      onTap: state.locations.length > 1
                          ? _selectLocation
                          : null,
                    ),
                  ),
                  const Divider(height: 1),
                  _InfoTile(
                    icon: Icons.store_mall_directory_outlined,
                    label: 'Manage Locations',
                    value: value.role == 'OWNER' || value.role == 'ADMIN'
                        ? 'Add, edit, and switch restaurants'
                        : 'View and switch restaurants',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LocationManagementScreen(
                          canManage:
                              value.role == 'OWNER' || value.role == 'ADMIN',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Account',
            description: 'Profile, role, security, and session controls.',
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
                  _InfoTile(
                    icon: Icons.security_outlined,
                    label: 'Account Security',
                    value: 'Password, sessions and account deletion',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AccountSecurityScreen(),
                      ),
                    ),
                  ),
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
            description: 'Installed FundWell application information.',
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
          const SizedBox(height: 20),
          _Section(
            title: sessionMode == AccountSessionMode.private
                ? 'Private Account'
                : 'Private Access',
            description: sessionMode == AccountSessionMode.private
                ? 'Manage the active private restaurant session.'
                : 'Open your secure private restaurant workspace.',
            child: _InfoTile(
              icon: sessionMode == AccountSessionMode.private
                  ? Icons.lock_open_outlined
                  : Icons.lock_outline,
              label: sessionMode == AccountSessionMode.private
                  ? kIsWeb
                        ? 'Sign Out of Private Account'
                        : 'Return to Beta Account'
                  : 'Private Account',
              value: sessionMode == AccountSessionMode.private
                  ? kIsWeb
                        ? 'End this private browser session securely'
                        : 'Leave the private account and restore beta access'
                  : kIsWeb
                  ? 'Sign in securely to your private workspace'
                  : 'Password-protected private access',
              trailing: _switchingAccount
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _switchingAccount
                  ? null
                  : sessionMode == AccountSessionMode.private
                  ? _returnToBeta
                  : _enterPrivateAccount,
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoAccountBanner extends StatelessWidget {
  const _DemoAccountBanner();

  @override
  Widget build(BuildContext context) => Card(
    color: FundWellTokens.surfaceSubtle,
    child: const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: FundWellTokens.purple),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exploring the public demo',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  'This workspace is view only and contains synthetic restaurant data. Use Private Account below to sign in securely to your own restaurant.',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PrivateAccountDialog extends StatefulWidget {
  const _PrivateAccountDialog({required this.onSubmit});
  final Future<void> Function(String code) onSubmit;

  @override
  State<_PrivateAccountDialog> createState() => _PrivateAccountDialogState();
}

class _PrivateAccountDialogState extends State<_PrivateAccountDialog> {
  final controller = TextEditingController();
  bool submitting = false;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (submitting || controller.text.isEmpty) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await widget.onSubmit(controller.text);
      if (mounted) Navigator.pop(context);
    } on DioException catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception.response?.statusCode == 503
            ? 'Private account access is not configured.'
            : 'Incorrect password.';
        submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Unable to open the private account.';
        submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Private Account'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          obscureText: true,
          enabled: !submitting,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Password', errorText: error),
          onSubmitted: (_) => submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: submitting ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: submitting ? null : submit,
        child: submitting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Submit'),
      ),
    ],
  );
}

String _formatRole(String role) {
  if (role.isEmpty) return role;
  return '${role[0]}${role.substring(1).toLowerCase()}';
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.description});
  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      if (description != null) ...[
        const SizedBox(height: 3),
        Text(
          description!,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: FundWellTokens.mutedInk),
        ),
      ],
      const SizedBox(height: 10),
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
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
    leading: DecoratedBox(
      decoration: BoxDecoration(
        color: FundWellTokens.surfaceSubtle,
        borderRadius: BorderRadius.circular(FundWellTokens.radiusSmall),
      ),
      child: SizedBox.square(
        dimension: 40,
        child: Icon(icon, size: 21, color: FundWellTokens.purple),
      ),
    ),
    title: Text(label),
    subtitle: Text(
      value,
      style: const TextStyle(color: FundWellTokens.mutedInk),
    ),
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
