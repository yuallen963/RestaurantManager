// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'features/tabs.dart';
import 'features/notifications/notification_screen.dart';
import 'features/notifications/push_service.dart';
import 'features/notifications/notification_router.dart';
import 'features/onboarding/foundation.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/dashboard/foundation.dart';
import 'features/auth/auth_screens.dart';
import 'features/auth/auth_links.dart';
import 'features/auth/auth_session_store_interface.dart';
import 'features/auth/auth_session_store_native.dart'
    if (dart.library.html) 'features/auth/auth_session_store_web.dart'
    as auth_store;
import 'features/auth/api_client_config_native.dart'
    if (dart.library.html) 'features/auth/api_client_config_web.dart'
    as api_client_config;
import 'features/banking/plaid_link/plaid_link.dart';
import 'features/responsive.dart';

final AuthSessionStore storage = auth_store.createAuthSessionStore();
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api/v1',
);
BaseOptions apiOptions() => BaseOptions(
  baseUrl: apiBaseUrl,
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 15),
);

Dio createApiClient({Dio? refreshClient, VoidCallback? onSessionExpired}) {
  final client = Dio(apiOptions());
  api_client_config.configureApiClient(client);
  final tokenClient = refreshClient ?? Dio(apiOptions());
  api_client_config.configureApiClient(tokenClient);
  installAuthRefreshInterceptor(
    client,
    refreshClient: tokenClient,
    onSessionExpired: onSessionExpired,
  );
  return client;
}

const _publicAuthPaths = {
  '/auth/register',
  '/auth/verify-email',
  '/auth/resend-verification',
  '/auth/login',
  '/auth/login-challenge',
  '/auth/login-challenge/resend',
  '/auth/shared-test-session',
  '/auth/private-session',
  '/auth/forgot-password',
  '/auth/reset-password',
};

void installAuthRefreshInterceptor(
  Dio client, {
  required Dio refreshClient,
  VoidCallback? onSessionExpired,
}) {
  client.interceptors.add(
    QueuedInterceptorsWrapper(
      onError: (error, handler) async {
        final request = error.requestOptions;
        if (error.response?.statusCode != 401 ||
            request.path == '/auth/refresh' ||
            _publicAuthPaths.contains(request.path) ||
            request.headers['Authorization'] == null) {
          handler.next(error);
          return;
        }
        if (request.extra['authRetried'] == true) {
          await storage.delete(key: 'accessToken');
          await storage.delete(key: 'refreshToken');
          client.options.headers.remove('Authorization');
          onSessionExpired?.call();
          handler.next(error);
          return;
        }

        try {
          final failedAuthorization = request.headers['Authorization'];
          var authorization = client.options.headers['Authorization'];
          if (authorization == null || authorization == failedAuthorization) {
            final refreshToken = await storage.read(key: 'refreshToken');
            if (refreshToken == null && !kIsWeb) {
              handler.next(error);
              return;
            }
            final response = await refreshClient.post<Map<String, dynamic>>(
              '/auth/refresh',
              data: kIsWeb
                  ? const <String, dynamic>{}
                  : {'refreshToken': refreshToken},
            );
            final data = response.data;
            final accessToken = data?['accessToken'] as String?;
            final replacementRefreshToken = data?['refreshToken'] as String?;
            if (accessToken == null ||
                (!kIsWeb && replacementRefreshToken == null)) {
              handler.next(error);
              return;
            }
            await storage.write(key: 'accessToken', value: accessToken);
            if (!kIsWeb) {
              await storage.write(
                key: 'refreshToken',
                value: replacementRefreshToken,
              );
            }
            authorization = 'Bearer $accessToken';
            client.options.headers['Authorization'] = authorization;
          }

          request.headers['Authorization'] = authorization;
          request.extra['authRetried'] = true;
          handler.resolve(await client.fetch<dynamic>(request));
        } catch (_) {
          await storage.delete(key: 'accessToken');
          await storage.delete(key: 'refreshToken');
          client.options.headers.remove('Authorization');
          onSessionExpired?.call();
          handler.next(error);
        }
      },
    ),
  );
}

final authSessionExpiredProvider = StateProvider<bool>((_) => false);
final api = Provider(
  (ref) => createApiClient(
    onSessionExpired: () {
      ref.read(authSessionExpiredProvider.notifier).state = true;
    },
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
const sharedTestClientToken = String.fromEnvironment(
  'SHARED_TEST_CLIENT_TOKEN',
);
bool sharedTestModeAllowed({required bool requested, required bool isWeb}) =>
    requested && !isWeb;
final sharedTestUserModeProvider = Provider<bool>(
  (_) => sharedTestModeAllowed(
    requested: sharedTestUserModeRequested,
    isWeb: kIsWeb,
  ),
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

class ProfitApp extends ConsumerStatefulWidget {
  const ProfitApp({super.key});
  @override
  ConsumerState<ProfitApp> createState() => _ProfitAppState();
}

class _ProfitAppState extends ConsumerState<ProfitApp> {
  final navigatorKey = GlobalKey<NavigatorState>();
  late final GoRouter webRouter = GoRouter(
    navigatorKey: navigatorKey,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => AuthBootstrap(onReady: links.ready),
      ),
      GoRoute(path: '/login', builder: (_, _) => const AuthScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, state) => VerifyEmailLinkScreen(
          token: state.uri.queryParameters['token'] ?? '',
        ),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, state) => ResetPasswordScreen(
          initialToken: state.uri.queryParameters['token'],
        ),
      ),
    ],
  );
  late final AuthLinkCoordinator links = AuthLinkCoordinator(
    navigatorKey: navigatorKey,
  );
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) links.start();
  }

  @override
  void dispose() {
    links.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authSessionExpiredProvider, (_, expired) {
      if (!expired) return;
      ref.read(authSessionExpiredProvider.notifier).state = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (kIsWeb) {
          webRouter.go('/login');
        } else {
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthScreen()),
            (_) => false,
          );
        }
      });
    });
    if (kIsWeb) {
      return MaterialApp.router(
        title: 'FundWell',
        theme: ThemeData(useMaterial3: true),
        routerConfig: webRouter,
      );
    }
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Profit Lens',
      theme: ThemeData(useMaterial3: true),
      home: AuthBootstrap(onReady: links.ready),
    );
  }
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
      if (refresh != null || kIsWeb) {
        final response = await client.post(
          '/auth/refresh',
          data: kIsWeb ? const <String, dynamic>{} : {'refreshToken': refresh},
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
      if (mounted) _showLogin();
      widget.onReady?.call();
    } catch (_) {
      if (refresh != null || kIsWeb) {
        try {
          final response = await client.post(
            '/auth/refresh',
            data: kIsWeb
                ? const <String, dynamic>{}
                : {'refreshToken': refresh},
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
      } else if (mounted) {
        _showLogin();
      }
      if (!sharedTestUserMode && !devAutoLogin) widget.onReady?.call();
    }
  }

  Future<void> _sharedTestSession() async {
    final response = await ref
        .read(api)
        .post(
          '/auth/shared-test-session',
          options: Options(
            headers: {'X-FundWell-Shared-Test-Token': sharedTestClientToken},
          ),
        );
    await _save(
      response.data as Map<String, dynamic>,
      mode: AccountSessionMode.standard,
    );
    await _enterAuthenticatedApp(forceHome: true);
  }

  void _showLogin() {
    if (kIsWeb) {
      context.go('/login');
    } else {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const AuthScreen()));
    }
  }

  Future<void> _enterAuthenticatedApp({bool forceHome = false}) async {
    if (!mounted) return;
    final completed =
        forceHome ||
        (await ref.read(onboardingRepositoryProvider).get()).completed;
    if (!mounted) return;
    if (kIsWeb) {
      final navigator = Navigator.of(context);
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => completed ? const Home() : const Onboarding(),
        ),
      );
      widget.onReady?.call();
      return;
    }
    final navigator = Navigator.of(context);
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => completed ? const Home() : const Onboarding(),
      ),
    );
    if (completed && isPlaidOAuthReturn(Uri.base)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigator.push(
          MaterialPageRoute(builder: (_) => const BankAccountsScreen()),
        );
      });
    }
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
    final refreshToken = data['refreshToken'] as String?;
    if (refreshToken != null) {
      await storage.write(key: 'refreshToken', value: refreshToken);
    }
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
        if (mounted) {
          if (kIsWeb) {
            context.go('/');
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => LoginChallengeScreen(
                  challengeId: challengeId,
                  method: method,
                ),
              ),
            );
          }
        }
        return;
      }
      await storage.write(
        key: 'accessToken',
        value: response.data['accessToken'],
      );
      final refreshToken = response.data['refreshToken'] as String?;
      if (refreshToken != null) {
        await storage.write(key: 'refreshToken', value: refreshToken);
      }
      ref.read(api).options.headers['Authorization'] =
          'Bearer ${response.data['accessToken']}';
      final onboarding = await ref.read(onboardingRepositoryProvider).get();
      if (mounted) {
        if (kIsWeb) {
          context.go('/');
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  onboarding.completed ? const Home() : const Onboarding(),
            ),
          );
        }
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
                    : () {
                        if (kIsWeb) {
                          context.go('/forgot-password');
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          );
                        }
                      },
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
    const destinations = [
      FundWellDestination(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: 'Home',
      ),
      FundWellDestination(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        label: 'Expenses',
      ),
      FundWellDestination(
        icon: Icons.attach_money_outlined,
        selectedIcon: Icons.attach_money,
        label: 'Revenue',
      ),
      FundWellDestination(
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront,
        label: 'Vendors',
      ),
      FundWellDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: 'More',
      ),
    ];
    final location = ref.watch(activeLocationProvider);
    final locations = ref.watch(availableLocationsProvider);
    return AdaptiveNavigationShell(
      selectedIndex: index,
      onDestinationSelected: (value) => setState(() => index = value),
      destinations: destinations,
      body: pages[index],
      applicationName: kIsWeb ? 'FundWell' : 'Profit Lens',
      desktopHeader: location == null
          ? null
          : DropdownButtonFormField<String>(
              key: const Key('desktop-location-selector'),
              initialValue: location.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Restaurant',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final item in locations.isEmpty ? [location] : locations)
                  DropdownMenuItem(value: item.id, child: Text(item.name)),
              ],
              onChanged: (id) {
                if (id == null || id == location.id) return;
                final selected = locations.where((item) => item.id == id);
                if (selected.isNotEmpty) {
                  ref
                      .read(activeLocationControllerProvider.notifier)
                      .select(selected.first);
                }
              },
            ),
      onNotifications: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
      ),
    );
  }
}
