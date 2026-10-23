import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart'
    show
        AuthScreen,
        AccountSessionMode,
        Home,
        accountSessionModeProvider,
        api,
        pendingAuthChallengeKey,
        pendingAuthChallengeMethodKey,
        pendingAuthChallengeModeKey,
        pendingAuthReturnPathKey,
        safeWebReturnPath,
        sessionModeStorageKey,
        storage;
import '../onboarding/foundation.dart';
import '../onboarding/onboarding_screen.dart';

class InvitationRegistrationScreen extends ConsumerStatefulWidget {
  const InvitationRegistrationScreen({super.key, this.invitationToken});

  final String? invitationToken;

  @override
  ConsumerState<InvitationRegistrationScreen> createState() =>
      _InvitationRegistrationScreenState();
}

class _InvitationRegistrationScreenState
    extends ConsumerState<InvitationRegistrationScreen> {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool loading = true;
  bool submitting = false;
  String? email;
  String? organizationName;
  String? role;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadInvitation();
  }

  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> _loadInvitation() async {
    final token = widget.invitationToken?.trim();
    if (token == null || token.isEmpty) {
      setState(() {
        loading = false;
        error = 'This invitation link is incomplete or invalid.';
      });
      return;
    }
    try {
      final response = await ref
          .read(api)
          .post('/auth/invitation-preview', data: {'token': token});
      final data = Map<String, dynamic>.from(response.data as Map);
      if (!mounted) return;
      setState(() {
        email = data['email'] as String?;
        organizationName = data['organizationName'] as String?;
        role = data['role'] as String?;
        loading = false;
        if (email == null || organizationName == null) {
          error = 'This invitation is not configured correctly.';
        }
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'This invitation is invalid, expired, or already used.';
      });
    }
  }

  Future<void> _register() async {
    final token = widget.invitationToken?.trim();
    if (token == null || email == null) return;
    if (password.text.length < 12) {
      setState(() => error = 'Use a password with at least 12 characters.');
      return;
    }
    if (password.text != confirmation.text) {
      setState(() => error = 'The passwords do not match.');
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final response = await ref
          .read(api)
          .post(
            '/auth/register',
            data: {
              'email': email,
              'password': password.text,
              'invitationToken': token,
            },
          );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CheckEmailScreen(
            email: data['email'] as String,
            developmentToken: data['developmentVerificationToken'] as String?,
          ),
        ),
      );
    } on DioException catch (exception) {
      if (!mounted) return;
      final message = exception.response?.data is Map
          ? (exception.response?.data as Map)['message']
          : null;
      setState(() {
        error = message is String && message.isNotEmpty
            ? message
            : 'Unable to create the account. Request a new invitation if this link has expired.';
      });
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  String get _roleLabel => role == 'ADMIN' ? 'Administrator' : 'Member';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Accept invitation')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null && email == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link_off_outlined, size: 56),
                    const SizedBox(height: 16),
                    Text(error!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Return to login'),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Join $organizationName',
                      key: const Key('invitation-organization'),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      email!,
                      key: const Key('invitation-email'),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      _roleLabel,
                      key: const Key('invitation-role'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      key: const Key('invitation-password'),
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Create password',
                      ),
                    ),
                    TextField(
                      key: const Key('invitation-password-confirmation'),
                      controller: confirmation,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(error!, textAlign: TextAlign.center),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const Key('accept-invitation'),
                      onPressed: submitting ? null : _register,
                      child: Text(
                        submitting ? 'Creating account…' : 'Create account',
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}

class LoginChallengeScreen extends ConsumerStatefulWidget {
  const LoginChallengeScreen({
    super.key,
    required this.challengeId,
    required this.method,
    this.accountMode = AccountSessionMode.standard,
    this.returnTo,
  });
  final String challengeId;
  final String method;
  final AccountSessionMode accountMode;
  final String? returnTo;
  @override
  ConsumerState<LoginChallengeScreen> createState() =>
      _LoginChallengeScreenState();
}

class _LoginChallengeScreenState extends ConsumerState<LoginChallengeScreen> {
  final code = TextEditingController();
  bool busy = false;
  String? error;
  Future<void> verify() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await ref
          .read(api)
          .post(
            '/auth/login-challenge',
            data: {'challengeId': widget.challengeId, 'code': code.text.trim()},
          );
      await storage.write(
        key: 'accessToken',
        value: response.data['accessToken'],
      );
      final refreshToken = response.data['refreshToken'] as String?;
      if (refreshToken != null) {
        await storage.write(key: 'refreshToken', value: refreshToken);
      }
      await storage.delete(key: pendingAuthChallengeKey);
      await storage.delete(key: pendingAuthChallengeMethodKey);
      await storage.delete(key: pendingAuthChallengeModeKey);
      await storage.delete(key: pendingAuthReturnPathKey);
      await storage.write(
        key: sessionModeStorageKey,
        value: widget.accountMode.name,
      );
      ref.read(accountSessionModeProvider.notifier).state = widget.accountMode;
      ref.read(api).options.headers['Authorization'] =
          'Bearer ${response.data['accessToken']}';
      final onboarding = await ref.read(onboardingRepositoryProvider).get();
      if (mounted) {
        if (kIsWeb) {
          context.go(safeWebReturnPath(widget.returnTo) ?? '/');
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  onboarding.completed ? const Home() : const Onboarding(),
            ),
            (_) => false,
          );
        }
      }
    } on DioException catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.response?.statusCode == 429
              ? 'Too many attempts. Try again later.'
              : 'That code is incorrect or expired.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resend() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(api)
          .post(
            '/auth/login-challenge/resend',
            data: {'challengeId': widget.challengeId},
          );
      if (mounted) setState(() => error = 'A new code was sent.');
    } on DioException {
      if (mounted) {
        setState(() => error = 'Wait before requesting another code.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verify sign-in')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          widget.method == 'EMAIL'
              ? Icons.mark_email_read_outlined
              : Icons.phonelink_lock_outlined,
          size: 60,
        ),
        const SizedBox(height: 16),
        Text(
          widget.method == 'EMAIL'
              ? 'Enter the six-digit code sent to your email. It expires in 5 minutes.'
              : 'Enter the code from your authenticator app or a one-time recovery code.',
        ),
        TextField(
          key: const Key('login-challenge-code'),
          controller: code,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Verification code'),
        ),
        if (error != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : verify,
          child: const Text('Verify and sign in'),
        ),
        if (widget.method == 'EMAIL')
          TextButton(
            onPressed: busy ? null : resend,
            child: const Text('Send another code'),
          ),
        TextButton(
          onPressed: busy
              ? null
              : () async {
                  await storage.delete(key: pendingAuthChallengeKey);
                  await storage.delete(key: pendingAuthChallengeMethodKey);
                  await storage.delete(key: pendingAuthChallengeModeKey);
                  await storage.delete(key: pendingAuthReturnPathKey);
                  if (!context.mounted) return;
                  if (kIsWeb) {
                    context.go(
                      widget.accountMode == AccountSessionMode.private
                          ? '/'
                          : '/login',
                    );
                  } else if (widget.accountMode == AccountSessionMode.private) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                      (_) => false,
                    );
                  }
                },
          child: const Text('Cancel sign-in'),
        ),
      ],
    ),
  );
}

class VerifyEmailLinkScreen extends ConsumerStatefulWidget {
  const VerifyEmailLinkScreen({super.key, required this.token});
  final String token;
  @override
  ConsumerState<VerifyEmailLinkScreen> createState() =>
      _VerifyEmailLinkScreenState();
}

class _VerifyEmailLinkScreenState extends ConsumerState<VerifyEmailLinkScreen> {
  bool complete = false;
  String? error;
  @override
  void initState() {
    super.initState();
    verify();
  }

  Future<void> verify() async {
    try {
      await ref
          .read(api)
          .post('/auth/verify-email', data: {'token': widget.token});
      if (mounted) setState(() => complete = true);
    } on DioException {
      if (mounted) {
        setState(() => error = 'Verification link is invalid or expired.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verify email')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: error != null
            ? Text(error!, textAlign: TextAlign.center)
            : complete
            ? const Text('Email verified. You can continue using FundWell.')
            : const CircularProgressIndicator(),
      ),
    ),
  );
}

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
