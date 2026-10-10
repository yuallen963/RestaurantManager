// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'features/tabs.dart';
import 'features/notifications/notification_screen.dart';
import 'features/notifications/push_service.dart';
import 'features/notifications/notification_router.dart';
import 'features/onboarding/foundation.dart';
import 'features/onboarding/onboarding_screen.dart';

const storage = FlutterSecureStorage();
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api/v1',
);
final api = Provider(
  (_) => Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  ),
);
void main() {
  if (kDebugMode) debugPrint('[DEV] API base URL: $apiBaseUrl');
  runApp(const ProviderScope(child: ProfitApp()));
}

const devAutoLoginRequested = bool.fromEnvironment('ENABLE_DEV_AUTO_LOGIN');
final demoModeProvider = Provider<bool>(
  (_) => !kReleaseMode && devAutoLoginRequested,
);
const _demoEmail = 'demo@profitlens.local';
const _demoPassword = 'DemoProfit2026!';

class ProfitApp extends StatelessWidget {
  const ProfitApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Profit Lens',
    theme: ThemeData(useMaterial3: true),
    home: const AuthBootstrap(),
  );
}

class AuthBootstrap extends ConsumerStatefulWidget {
  const AuthBootstrap({super.key});
  @override
  ConsumerState<AuthBootstrap> createState() => _AuthBootstrapState();
}

class _AuthBootstrapState extends ConsumerState<AuthBootstrap> {
  String? error;
  bool get devAutoLogin => ref.read(demoModeProvider);
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final client = ref.read(api);
    final access = await storage.read(key: 'accessToken');
    final refresh = await storage.read(key: 'refreshToken');
    try {
      if (access != null) {
        client.options.headers['Authorization'] = 'Bearer $access';
        await client.get('/auth/me');
        await _enterAuthenticatedApp();
        return;
      }
      if (refresh != null) {
        final response = await client.post(
          '/auth/refresh',
          data: {'refreshToken': refresh},
        );
        await _save(response.data as Map<String, dynamic>);
        await _enterAuthenticatedApp();
        return;
      }
      if (devAutoLogin) {
        final response = await client.post(
          '/auth/login',
          data: {'email': _demoEmail, 'password': _demoPassword},
        );
        await _save(response.data as Map<String, dynamic>);
        await _enterAuthenticatedApp(forceHome: true);
        return;
      }
      if (mounted)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
    } catch (_) {
      if (refresh != null) {
        try {
          final response = await client.post(
            '/auth/refresh',
            data: {'refreshToken': refresh},
          );
          await _save(response.data as Map<String, dynamic>);
          await _enterAuthenticatedApp();
          return;
        } catch (_) {}
      }
      if (devAutoLogin) {
        try {
          final response = await client.post(
            '/auth/login',
            data: {'email': _demoEmail, 'password': _demoPassword},
          );
          await _save(response.data as Map<String, dynamic>);
          await _enterAuthenticatedApp(forceHome: true);
          return;
        } catch (_) {
          if (mounted)
            setState(
              () => error =
                  'Development auto-login failed. Start the API and seed the demo account.',
            );
        }
      } else if (mounted)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
    }
  }

  Future<void> _enterAuthenticatedApp({bool forceHome = false}) async {
    if (!mounted) return;
    final completed =
        forceHome ||
        (await ref.read(onboardingRepositoryProvider).get()).completed;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => completed ? const Home() : const Onboarding(),
      ),
    );
  }

  Future<void> _save(Map<String, dynamic> data) async {
    await storage.write(
      key: 'accessToken',
      value: data['accessToken'] as String,
    );
    ref.read(api).options.headers['Authorization'] =
        'Bearer ${data['accessToken']}';
    await storage.write(
      key: 'refreshToken',
      value: data['refreshToken'] as String,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: error == null
          ? const CircularProgressIndicator()
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _bootstrap,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
    ),
  );
}

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool creatingAccount = false;
  String? error;
  Future<void> login() async {
    setState(() => busy = true);
    try {
      final response = await ref
          .read(api)
          .post(
            creatingAccount ? '/auth/register' : '/auth/login',
            data: {'email': email.text, 'password': password.text},
          );
      await storage.write(
        key: 'accessToken',
        value: response.data['accessToken'],
      );
      await storage.write(
        key: 'refreshToken',
        value: response.data['refreshToken'],
      );
      ref.read(api).options.headers['Authorization'] =
          'Bearer ${response.data['accessToken']}';
      final onboarding = await ref.read(onboardingRepositoryProvider).get();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                onboarding.completed ? const Home() : const Onboarding(),
          ),
        );
      }
    } on DioException {
      setState(
        () => error = creatingAccount
            ? 'Unable to create account. Use a valid email and a password of at least 12 characters.'
            : 'Unable to sign in.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Profit Lens',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            if (error != null) Text(error!),
            FilledButton(
              onPressed: busy ? null : login,
              child: Text(creatingAccount ? 'Create account' : 'Log in'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      creatingAccount = !creatingAccount;
                      error = null;
                    }),
              child: Text(
                creatingAccount
                    ? 'Already have an account? Log in'
                    : 'New to ProfitLens? Create account',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class Home extends ConsumerStatefulWidget {
  const Home({super.key});
  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> {
  int index = 0;
  PushMessageCoordinator? coordinator;
  @override
  void initState() {
    super.initState();
    _startPush();
  }

  Future<void> _startPush() async {
    final client = await FirebasePushClient.create();
    if (!mounted) return;
    coordinator = PushMessageCoordinator(client);
    await coordinator!.start(
      onForeground: () {
        ref.invalidate(notificationListProvider);
      },
      onOpen: (data) async {
        if (!mounted) return;
        await ref
            .read(notificationRouterProvider)
            .open(context, ref, NotificationRouteData.fromJson(data));
      },
    );
  }

  @override
  void dispose() {
    coordinator?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pages = [
      HomeScreen(),
      ExpensesScreen(),
      RevenueScreen(),
      VendorsScreen(),
      MoreScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profit Lens'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationCenterScreen(),
              ),
            ),
          ),
        ],
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt), label: 'Expenses'),
          NavigationDestination(
            icon: Icon(Icons.attach_money),
            label: 'Revenue',
          ),
          NavigationDestination(icon: Icon(Icons.storefront), label: 'Vendors'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
