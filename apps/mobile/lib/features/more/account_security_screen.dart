import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show AuthScreen, demoModeProvider;
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
    final demo = ref.watch(demoModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Account Security')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            title: const Text('Sign out all devices'),
            subtitle: const Text('Revokes every active session.'),
            trailing: FilledButton(
              onPressed: busy ? null : signOutAll,
              child: const Text('Sign out all'),
            ),
          ),
          const Divider(),
          Text('Delete account', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: password,
            obscureText: true,
            enabled: !demo && !busy,
            decoration: const InputDecoration(labelText: 'Confirm password'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: demo || busy ? null : deleteAccount,
            child: Text(
              demo ? 'Demo account cannot be deleted' : 'Delete account',
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
