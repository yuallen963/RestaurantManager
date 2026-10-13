import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../main.dart'
    show AuthScreen, demoModeProvider, sharedTestUserModeProvider;
import 'foundation.dart';

class AccountSecurityScreen extends ConsumerStatefulWidget {
  const AccountSecurityScreen({super.key});
  @override
  ConsumerState<AccountSecurityScreen> createState() =>
      _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends ConsumerState<AccountSecurityScreen> {
  final password = TextEditingController();
  bool busy = false;
  String? message;

  Future<List<String>?> _credentialsDialog(
    String title,
    List<String> labels,
  ) async {
    final controllers = labels.map((_) => TextEditingController()).toList();
    return showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < labels.length; index++)
              TextField(
                controller: controllers[index],
                obscureText: labels[index].toLowerCase().contains('password'),
                decoration: InputDecoration(labelText: labels[index]),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              controllers.map((value) => value.text).toList(),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> changePassword() async {
    final values = await _credentialsDialog('Change password', [
      'Current password',
      'New password',
    ]);
    if (values == null) return;
    if (values[1].length < 12) {
      setState(() => message = 'Use a new password of at least 12 characters.');
      return;
    }
    await _run(
      () =>
          ref.read(moreRepositoryProvider).changePassword(values[0], values[1]),
      'Password changed. Sign in again on your devices.',
    );
  }

  Future<void> toggleEmailVerification(bool enabled) async {
    final values = await _credentialsDialog(
      '${enabled ? 'Enable' : 'Disable'} email sign-in verification',
      ['Password'],
    );
    if (values == null) return;
    await _run(
      () => ref
          .read(moreRepositoryProvider)
          .setEmailLoginVerification(enabled, values[0]),
      'Email sign-in verification ${enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> enableMfa() async {
    final values = await _credentialsDialog('Enable authenticator MFA', [
      'Password',
    ]);
    if (values == null) return;
    try {
      setState(() => busy = true);
      final setup = await ref.read(moreRepositoryProvider).beginMfa(values[0]);
      if (!mounted) return;
      final code = TextEditingController();
      List<String>? recoveryCodes;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Scan authenticator code'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(data: setup['otpauthUri'] as String, size: 190),
                const Text('Or enter this setup key:'),
                SelectableText(setup['secret'] as String),
                TextField(
                  key: const Key('mfa-confirm-code'),
                  controller: code,
                  decoration: const InputDecoration(
                    labelText: 'Six-digit code',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  recoveryCodes = await ref
                      .read(moreRepositoryProvider)
                      .confirmMfa(code.text.trim());
                  if (context.mounted) Navigator.pop(context, true);
                } on DioException {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Incorrect authenticator code.'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Enable'),
            ),
          ],
        ),
      );
      if (confirmed == true && recoveryCodes != null && mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Save recovery codes'),
            content: SelectableText(recoveryCodes!.join('\n')),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('I saved them'),
              ),
            ],
          ),
        );
        ref.invalidate(accountSecurityProvider);
        setState(() => message = 'Authenticator MFA enabled.');
      }
    } on DioException {
      if (mounted) {
        setState(
          () => message =
              'Unable to start authenticator setup. Check your password.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> disableMfa() async {
    final values = await _credentialsDialog('Disable authenticator MFA', [
      'Password',
      'Authenticator or recovery code',
    ]);
    if (values == null) return;
    await _run(
      () => ref.read(moreRepositoryProvider).disableMfa(values[0], values[1]),
      'Authenticator MFA disabled.',
    );
  }

  Future<void> regenerateCodes() async {
    final values = await _credentialsDialog('Generate new recovery codes', [
      'Password',
      'Authenticator code',
    ]);
    if (values == null) return;
    try {
      final codes = await ref
          .read(moreRepositoryProvider)
          .regenerateRecoveryCodes(values[0], values[1]);
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('New recovery codes'),
            content: SelectableText(codes.join('\n')),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('I saved them'),
              ),
            ],
          ),
        );
      }
      ref.invalidate(accountSecurityProvider);
    } on DioException {
      if (mounted) {
        setState(() => message = 'Unable to regenerate recovery codes.');
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
      ref.invalidate(accountSecurityProvider);
      if (mounted) setState(() => message = success);
    } on DioException {
      if (mounted) {
        setState(
          () => message =
              'Security change failed. Verify your credentials and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signOutAll() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await ref.read(moreRepositoryProvider).signOutAll();
      if (mounted) {
        _returnToLogin();
      }
    } on DioException {
      if (mounted) {
        setState(() => message = 'Unable to sign out all devices. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> deleteAccount() async {
    if (password.text.isEmpty) {
      setState(() => message = 'Enter your password to confirm deletion.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This removes your access and personal account data. Business financial records are preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await ref.read(moreRepositoryProvider).deleteAccount(password.text);
      if (mounted) {
        _returnToLogin();
      }
    } on DioException catch (error) {
      if (mounted) {
        setState(
          () => message = error.response?.statusCode == 409
              ? 'Transfer organization ownership before deleting your account.'
              : 'Unable to delete account. Check your password and try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  void _returnToLogin() => Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const AuthScreen()),
    (_) => false,
  );

  @override
  Widget build(BuildContext context) {
    final protectedBetaAccount =
        ref.watch(demoModeProvider) || ref.watch(sharedTestUserModeProvider);
    final security = protectedBetaAccount
        ? null
        : ref.watch(accountSecurityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Account Security')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (protectedBetaAccount)
            const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('Shared beta account'),
              subtitle: Text(
                'Security settings are managed centrally for internal testers.',
              ),
            )
          else
            security!.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const ListTile(
                title: Text('Unable to load security settings'),
              ),
              data: (data) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: Text(data.email),
                    subtitle: Text(
                      data.emailVerified
                          ? 'Email verified'
                          : 'Email not verified',
                    ),
                  ),
                  ListTile(
                    title: const Text('Change password'),
                    subtitle: const Text(
                      'Revokes active sessions after a successful change.',
                    ),
                    trailing: FilledButton(
                      onPressed: protectedBetaAccount || busy
                          ? null
                          : changePassword,
                      child: const Text('Change'),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Email sign-in verification'),
                    subtitle: Text(
                      data.emailLoginAvailable
                          ? 'Requires a five-minute email code after your password.'
                          : 'Not available until enabled by the FundWell administrator.',
                    ),
                    value: data.emailLoginVerificationEnabled,
                    onChanged:
                        protectedBetaAccount ||
                            busy ||
                            !data.emailLoginAvailable
                        ? null
                        : toggleEmailVerification,
                  ),
                  ListTile(
                    title: const Text('Authenticator app MFA'),
                    subtitle: Text(
                      data.mfaEnabled
                          ? '${data.recoveryCodesRemaining} recovery codes remaining'
                          : data.mfaAvailable
                          ? 'Works with standard authenticator apps.'
                          : 'Not available until enabled by the FundWell administrator.',
                    ),
                    trailing: FilledButton(
                      onPressed:
                          protectedBetaAccount || busy || !data.mfaAvailable
                          ? null
                          : data.mfaEnabled
                          ? disableMfa
                          : enableMfa,
                      child: Text(data.mfaEnabled ? 'Disable' : 'Enable'),
                    ),
                  ),
                  if (data.mfaEnabled)
                    TextButton(
                      onPressed: busy ? null : regenerateCodes,
                      child: const Text('Generate new recovery codes'),
                    ),
                  const Divider(),
                  Text(
                    'Active sessions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (data.sessions.isEmpty)
                    const ListTile(title: Text('No active sessions')),
                  for (final session in data.sessions)
                    ListTile(
                      title: Text(
                        session['deviceLabel']?.toString() ?? 'Unknown device',
                      ),
                      subtitle: Text('Last active ${session['lastSeenAt']}'),
                      trailing: IconButton(
                        tooltip: 'Revoke session',
                        onPressed: busy
                            ? null
                            : () => _run(
                                () => ref
                                    .read(moreRepositoryProvider)
                                    .revokeSession(session['id'] as String),
                                'Session revoked.',
                              ),
                        icon: const Icon(Icons.logout),
                      ),
                    ),
                  Text(
                    'Recognized devices',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (data.devices.isEmpty)
                    const ListTile(title: Text('No recognized devices')),
                  for (final device in data.devices)
                    ListTile(
                      title: Text(
                        device['label']?.toString() ?? 'Unknown device',
                      ),
                      subtitle: Text('Last seen ${device['lastSeenAt']}'),
                      trailing: IconButton(
                        tooltip: 'Forget device',
                        onPressed: busy
                            ? null
                            : () => _run(
                                () => ref
                                    .read(moreRepositoryProvider)
                                    .revokeDevice(device['id'] as String),
                                'Device removed.',
                              ),
                        icon: const Icon(Icons.phonelink_erase),
                      ),
                    ),
                  const Divider(),
                ],
              ),
            ),
          ListTile(
            title: const Text('Sign out all devices'),
            subtitle: Text(
              protectedBetaAccount
                  ? 'Unavailable for the shared beta account.'
                  : 'Revokes every active session.',
            ),
            trailing: FilledButton(
              onPressed: protectedBetaAccount || busy ? null : signOutAll,
              child: Text(protectedBetaAccount ? 'Protected' : 'Sign out all'),
            ),
          ),
          const Divider(),
          Text('Delete account', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: password,
            obscureText: true,
            enabled: !protectedBetaAccount && !busy,
            decoration: const InputDecoration(labelText: 'Confirm password'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: protectedBetaAccount || busy ? null : deleteAccount,
            child: Text(
              protectedBetaAccount
                  ? 'Shared beta account cannot be deleted'
                  : 'Delete account',
            ),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(message!),
            ),
        ],
      ),
    );
  }
}
