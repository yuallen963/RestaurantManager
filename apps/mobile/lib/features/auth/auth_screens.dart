import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show AuthScreen, api;

class CheckEmailScreen extends ConsumerStatefulWidget {
  const CheckEmailScreen({
    super.key,
    required this.email,
    this.developmentToken,
  });
  final String email;
  final String? developmentToken;
  @override
  ConsumerState<CheckEmailScreen> createState() => _CheckEmailScreenState();
}

class _CheckEmailScreenState extends ConsumerState<CheckEmailScreen> {
  bool busy = false;
  String? message;
  String? token;
  Future<void> resend() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final response = await ref
          .read(api)
          .post('/auth/resend-verification', data: {'email': widget.email});
      token = (response.data as Map)['developmentVerificationToken'] as String?;
      if (mounted) {
        setState(() => message = 'Verification email sent.');
      }
    } on DioException {
      if (mounted) {
        setState(() => message = 'Unable to resend verification right now.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> verifyDevelopmentToken() async {
    setState(() => busy = true);
    try {
      await ref
          .read(api)
          .post(
            '/auth/verify-email',
            data: {'token': token ?? widget.developmentToken},
          );
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const VerificationCompleteScreen()),
        );
      }
    } on DioException {
      if (mounted) {
        setState(() => message = 'Verification link is invalid or expired.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Check your email')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.mark_email_unread_outlined, size: 64),
        const SizedBox(height: 20),
        Text(
          'We sent a verification link to ${widget.email}. Verify your email before signing in.',
          textAlign: TextAlign.center,
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(message!, textAlign: TextAlign.center),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : resend,
          child: const Text('Resend verification'),
        ),
        if (widget.developmentToken != null || token != null)
          TextButton(
            onPressed: busy ? null : verifyDevelopmentToken,
            child: const Text('Verify now (development)'),
          ),
        TextButton(
          onPressed: busy
              ? null
              : () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                  (_) => false,
                ),
          child: const Text('Back to login'),
        ),
      ],
    ),
  );
}

class VerificationCompleteScreen extends StatelessWidget {
  const VerificationCompleteScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              'Email verified',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('You can now log in to continue.'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const AuthScreen()),
                (_) => false,
              ),
              child: const Text('Continue to login'),
            ),
          ],
        ),
      ),
    ),
  );
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final email = TextEditingController();
  bool busy = false;
  String? message;
  String? developmentToken;
  Future<void> submit() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final response = await ref
          .read(api)
          .post('/auth/forgot-password', data: {'email': email.text.trim()});
      developmentToken =
          (response.data as Map)['developmentResetToken'] as String?;
      if (mounted) {
        setState(
          () => message =
              'If an account exists for this email, password reset instructions have been sent.',
        );
      }
    } on DioException {
      if (mounted) {
        setState(() => message = 'Password reset is temporarily unavailable.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Forgot password')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Enter your email and we’ll send password reset instructions.',
        ),
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(message!),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : submit,
          child: const Text('Send reset instructions'),
        ),
        if (developmentToken != null)
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ResetPasswordScreen(initialToken: developmentToken!),
              ),
            ),
            child: const Text('Reset now (development)'),
          ),
      ],
    ),
  );
}

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.initialToken});
  final String? initialToken;
  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  late final token = TextEditingController(text: widget.initialToken);
  final password = TextEditingController();
  bool busy = false;
  String? error;
  Future<void> submit() async {
    if (password.text.length < 12) {
      setState(() => error = 'Use at least 12 characters.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(api)
          .post(
            '/auth/reset-password',
            data: {'token': token.text.trim(), 'password': password.text},
          );
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (_) => false,
        );
      }
    } on DioException {
      if (mounted) {
        setState(() => error = 'Reset link is invalid or expired.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reset password')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (widget.initialToken == null)
          TextField(
            controller: token,
            decoration: const InputDecoration(labelText: 'Reset token'),
          ),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'New password'),
        ),
        if (error != null) Text(error!),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : submit,
          child: const Text('Reset password'),
        ),
      ],
    ),
  );
}
