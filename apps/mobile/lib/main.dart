// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:math';

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
import 'features/auth/auth_screens.dart';
import 'features/auth/auth_links.dart';

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
const sharedTestUserModeRequested = bool.fromEnvironment(
  'SHARED_TEST_USER_MODE',
);
final sharedTestUserModeProvider = Provider<bool>(
  (_) => sharedTestUserModeRequested,
);

enum AccountSessionMode { standard, private }

const sessionModeStorageKey = 'accountSessionMode';
const pendingAuthChallengeKey = 'pendingAuthChallenge';
const pendingAuthChallengeMethodKey = 'pendingAuthChallengeMethod';
const pendingAuthChallengeModeKey = 'pendingAuthChallengeMode';
const authDeviceIdKey = 'authDeviceId';

Future<String> authDeviceId() async {
  final existing = await storage.read(key: authDeviceIdKey);
  if (existing != null) return existing;
  final random = Random.secure();
  final value = base64Url
      .encode(List<int>.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
  await storage.write(key: authDeviceIdKey, value: value);
  return value;
}

final authDeviceIdProvider = FutureProvider<String>((_) => authDeviceId());

String get authDeviceName => '${defaultTargetPlatform.name} FundWell app';
final accountSessionModeProvider = StateProvider<AccountSessionMode>(
  (_) => AccountSessionMode.standard,
);
const _demoEmail = 'demo@profitlens.local';
const _demoPassword = 'DemoProfit2026!';

class ProfitApp extends StatefulWidget {
  const ProfitApp({super.key});
  @override
  State<ProfitApp> createState() => _ProfitAppState();
}

class _ProfitAppState extends State<ProfitApp> {
  final navigatorKey = GlobalKey<NavigatorState>();
  late final AuthLinkCoordinator links = AuthLinkCoordinator(
    navigatorKey: navigatorKey,
  );
  @override
  void initState() {
    super.initState();
    links.start();
  }

  @override
  void dispose() {
    links.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    title: 'Profit Lens',
    theme: ThemeData(useMaterial3: true),
    home: AuthBootstrap(onReady: links.ready),
  );
}

class AuthBootstrap extends ConsumerStatefulWidget {
  const AuthBootstrap({super.key, this.onReady});
  final VoidCallback? onReady;
  @override
  ConsumerState<AuthBootstrap> createState() => _AuthBootstrapState();
}

class _AuthBootstrapState extends ConsumerState<AuthBootstrap> {
  String? error;
  bool get devAutoLogin => ref.read(demoModeProvider);
  bool get sharedTestUserMode => ref.read(sharedTestUserModeProvider);
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final client = ref.read(api);
    final access = await storage.read(key: 'accessToken');
    final refresh = await storage.read(key: 'refreshToken');
    final storedMode = await storage.read(key: sessionModeStorageKey);
    final privateSession = storedMode == AccountSessionMode.private.name;
    ref.read(accountSessionModeProvider.notifier).state = privateSession
        ? AccountSessionMode.private
        : AccountSessionMode.standard;
    try {
      final pendingChallenge = await storage.read(key: pendingAuthChallengeKey);
      if (pendingChallenge != null) {
        final method =
            await storage.read(key: pendingAuthChallengeMethodKey) ??
            'AUTHENTICATOR';
        final pendingMode =
            await storage.read(key: pendingAuthChallengeModeKey) ==
                AccountSessionMode.private.name
            ? AccountSessionMode.private
            : AccountSessionMode.standard;
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => LoginChallengeScreen(
                challengeId: pendingChallenge,
                method: method,
                accountMode: pendingMode,
              ),
            ),
          );
        }
        widget.onReady?.call();
        return;
      }
      // Shared test mode deliberately obtains a session on every launch. This
      // prevents an old device's saved account from leaking into this temporary
      // single-restaurant testing environment.
      if (sharedTestUserMode && !privateSession) {
        await _sharedTestSession();
        return;
      }
      if (access != null) {
        client.options.headers['Authorization'] = 'Bearer $access';
        final profile = await client.get('/auth/me');
        if (privateSession && profile.data['accountMode'] != 'private') {
          throw StateError('Stored private session identity is invalid');
        }
        await _enterAuthenticatedApp();
        return;
      }
      if (refresh != null) {
        final response = await client.post(
          '/auth/refresh',
          data: {'refreshToken': refresh},
        );
        await _save(
          response.data as Map<String, dynamic>,
          mode: privateSession
              ? AccountSessionMode.private
              : AccountSessionMode.standard,
        );
        if (privateSession) {
          final profile = await client.get('/auth/me');
          if (profile.data['accountMode'] != 'private') {
            throw StateError('Refreshed private session identity is invalid');
          }
        }
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
      widget.onReady?.call();
    } catch (_) {
      if (refresh != null) {
        try {
          final response = await client.post(
            '/auth/refresh',
            data: {'refreshToken': refresh},
          );
          await _save(
            response.data as Map<String, dynamic>,
            mode: privateSession
                ? AccountSessionMode.private
                : AccountSessionMode.standard,
          );
          if (privateSession) {
            final profile = await client.get('/auth/me');
            if (profile.data['accountMode'] != 'private')
              throw StateError('Private session expired');
          }
          await _enterAuthenticatedApp();
          return;
        } catch (_) {}
      }
      if (privateSession) {
        await storage.delete(key: 'accessToken');
        await storage.delete(key: 'refreshToken');
        await storage.delete(key: sessionModeStorageKey);
        client.options.headers.remove('Authorization');
        ref.read(accountSessionModeProvider.notifier).state =
            AccountSessionMode.standard;
      }
      if (sharedTestUserMode) {
        try {
          await _sharedTestSession();
          return;
        } catch (_) {
          if (mounted)
            setState(
              () => error =
                  'Shared test sign-in is unavailable. Confirm shared test mode is enabled on the API.',
            );
          widget.onReady?.call();
        }
      } else if (devAutoLogin) {
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
          widget.onReady?.call();
        }
      } else if (mounted)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      if (!sharedTestUserMode && !devAutoLogin) widget.onReady?.call();
    }
  }

  Future<void> _sharedTestSession() async {
    final response = await ref.read(api).post('/auth/shared-test-session');
    await _save(
      response.data as Map<String, dynamic>,
      mode: AccountSessionMode.standard,
    );
    await _enterAuthenticatedApp(forceHome: true);
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
    widget.onReady?.call();
  }

  Future<void> _save(
    Map<String, dynamic> data, {
    AccountSessionMode mode = AccountSessionMode.standard,
  }) async {
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
    await storage.write(key: sessionModeStorageKey, value: mode.name);
    ref.read(accountSessionModeProvider.notifier).state = mode;
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
      final deviceId = await ref.read(authDeviceIdProvider.future);
      final response = await ref
          .read(api)
          .post(
            creatingAccount ? '/auth/register' : '/auth/login',
            data: {
              'email': email.text,
              'password': password.text,
              'deviceId': deviceId,
              'deviceName': authDeviceName,
            },
          );
      if (creatingAccount) {
        final data = Map<String, dynamic>.from(response.data as Map);
        if (mounted)
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CheckEmailScreen(
                email: data['email'] as String,
                developmentToken:
                    data['developmentVerificationToken'] as String?,
              ),
            ),
          );
        return;
      }
      if (response.data['challengeRequired'] == true) {
        final challengeId = response.data['challengeId'] as String;
        final method = response.data['method'] as String;
        await storage.write(key: pendingAuthChallengeKey, value: challengeId);
        await storage.write(key: pendingAuthChallengeMethodKey, value: method);
        await storage.write(
          key: pendingAuthChallengeModeKey,
          value: AccountSessionMode.standard.name,
        );
        if (mounted)
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => LoginChallengeScreen(
                challengeId: challengeId,
                method: method,
              ),
            ),
          );
        return;
      }
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
    } on DioException catch (exception) {
      if (!creatingAccount && exception.response?.statusCode == 403) {
        if (mounted)
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CheckEmailScreen(email: email.text.trim()),
            ),
          );
      } else {
        setState(
          () => error = creatingAccount && exception.response?.statusCode == 409
              ? 'An account already exists. Log in or reset your password.'
              : creatingAccount
              ? 'Unable to create account. Use a valid email and a password of at least 12 characters.'
              : 'Unable to sign in.',
        );
      }
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
            if (!creatingAccount)
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ForgotPasswordScreen(),
                        ),
                      ),
                child: const Text('Forgot password?'),
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
