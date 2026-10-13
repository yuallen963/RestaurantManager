import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../main.dart'
    show AccountSessionMode, api, sessionModeStorageKey, storage;
import '../dashboard/foundation.dart';

class MoreAccountData {
  const MoreAccountData({
    required this.email,
    required this.organizationName,
    required this.accountMode,
    this.role,
  });

  final String email;
  final String organizationName;
  final AccountSessionMode accountMode;
  final String? role;
}

class AppMetadata {
  const AppMetadata({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;
}

class AccountSecurityData {
  const AccountSecurityData({
    required this.email,
    required this.emailVerified,
    required this.emailLoginVerificationEnabled,
    required this.mfaEnabled,
    required this.emailLoginAvailable,
    required this.mfaAvailable,
    required this.recoveryCodesRemaining,
    required this.sessions,
    required this.devices,
  });
  final String email;
  final bool emailVerified;
  final bool emailLoginVerificationEnabled;
  final bool mfaEnabled;
  final bool emailLoginAvailable;
  final bool mfaAvailable;
  final int recoveryCodesRemaining;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> devices;
}

class MoreRepository {
  MoreRepository(this.dio, this.secureStorage);

  final Dio dio;
  final FlutterSecureStorage secureStorage;

  Future<MoreAccountData> load(RestaurantLocation location) async {
    final responses = await Future.wait([
      dio.get('/auth/me'),
      dio.get('/organizations'),
    ]);
    final profile = Map<String, dynamic>.from(responses[0].data as Map);
    final organizations = (responses[1].data as List)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
    final organization = organizations.firstWhere(
      (value) => value['id'] == location.organizationId,
      orElse: () => throw StateError('Active organization is unavailable'),
    );
    final memberships = organization['memberships'] as List? ?? const [];
    final role = memberships.isEmpty
        ? null
        : (memberships.first as Map)['role']?.toString();
    return MoreAccountData(
      email: profile['email'] as String,
      organizationName: organization['name'] as String,
      accountMode: profile['accountMode'] == 'private'
          ? AccountSessionMode.private
          : AccountSessionMode.standard,
      role: role,
    );
  }

  Future<Map<String, dynamic>?> unlockPrivate(
    String accessCode, {
    required String deviceId,
    required String deviceName,
  }) async {
    final response = await dio.post(
      '/auth/private-session',
      data: {
        'accessCode': accessCode,
        'deviceId': deviceId,
        'deviceName': deviceName,
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['challengeRequired'] == true) return data;
    await _installSession(data, AccountSessionMode.private);
    return null;
  }

  Future<void> returnToBeta() async {
    final privateRefresh = await secureStorage.read(key: 'refreshToken');
    if (privateRefresh != null) {
      try {
        await dio.post('/auth/logout', data: {'refreshToken': privateRefresh});
      } on DioException {
        // Replacing local private credentials must not expose stale private data.
      }
    }
    dio.options.headers.remove('Authorization');
    final response = await dio.post('/auth/shared-test-session');
    await _installSession(
      Map<String, dynamic>.from(response.data as Map),
      AccountSessionMode.standard,
    );
  }

  Future<void> _installSession(
    Map<String, dynamic> data,
    AccountSessionMode mode,
  ) async {
    final accessToken = data['accessToken'] as String;
    final refreshToken = data['refreshToken'] as String;
    await secureStorage.write(key: 'accessToken', value: accessToken);
    await secureStorage.write(key: 'refreshToken', value: refreshToken);
    await secureStorage.write(key: sessionModeStorageKey, value: mode.name);
    dio.options.headers['Authorization'] = 'Bearer $accessToken';
  }

  Future<void> signOut() async {
    final fcmToken = await secureStorage.read(key: 'fcmToken');
    if (fcmToken != null) {
      try {
        await dio.delete(
          '/notifications/devices/${Uri.encodeComponent(fcmToken)}',
        );
      } on DioException {
        /* never block local logout */
      }
    }
    final refreshToken = await secureStorage.read(key: 'refreshToken');
    if (refreshToken != null) {
      try {
        await dio.post('/auth/logout', data: {'refreshToken': refreshToken});
      } on DioException {
        // Local credentials must still be cleared if remote revocation fails.
      }
    }
    await secureStorage.delete(key: 'accessToken');
    await secureStorage.delete(key: 'refreshToken');
    await secureStorage.delete(key: 'fcmToken');
    await secureStorage.delete(key: sessionModeStorageKey);
    dio.options.headers.remove('Authorization');
  }

  Future<void> signOutAll() async {
    await dio.post('/auth/sign-out-all');
    await _clearCredentials();
  }

  Future<AccountSecurityData> security() async {
    final responses = await Future.wait([
      dio.get('/auth/security'),
      dio.get('/auth/sessions'),
      dio.get('/auth/devices'),
    ]);
    final data = Map<String, dynamic>.from(responses[0].data as Map);
    return AccountSecurityData(
      email: data['email'] as String,
      emailVerified: data['emailVerifiedAt'] != null,
      emailLoginVerificationEnabled:
          data['emailLoginVerificationEnabled'] == true,
      mfaEnabled: data['mfaEnabled'] == true,
      emailLoginAvailable: data['emailLoginVerificationAvailable'] == true,
      mfaAvailable: data['authenticatorMfaAvailable'] == true,
      recoveryCodesRemaining: data['recoveryCodesRemaining'] as int? ?? 0,
      sessions: (responses[1].data as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList(),
      devices: (responses[2].data as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList(),
    );
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await dio.post(
      '/auth/change-password',
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  Future<void> setEmailLoginVerification(bool enabled, String password) async {
    await dio.patch(
      '/auth/security/email-login-verification',
      data: {'enabled': enabled, 'password': password},
    );
  }

  Future<Map<String, dynamic>> beginMfa(String password) async =>
      Map<String, dynamic>.from(
        (await dio.post(
              '/auth/security/mfa/enroll',
              data: {'password': password},
            )).data
            as Map,
      );
  Future<List<String>> confirmMfa(String code) async => List<String>.from(
    ((await dio.post('/auth/security/mfa/confirm', data: {'code': code})).data
            as Map)['recoveryCodes']
        as List,
  );
  Future<void> disableMfa(String password, String code) async {
    await dio.post(
      '/auth/security/mfa/disable',
      data: {'password': password, 'code': code},
    );
  }

  Future<List<String>> regenerateRecoveryCodes(
    String password,
    String code,
  ) async => List<String>.from(
    ((await dio.post(
              '/auth/security/mfa/recovery-codes',
              data: {'password': password, 'code': code},
            )).data
            as Map)['recoveryCodes']
        as List,
  );
  Future<void> revokeSession(String id) async {
    await dio.delete('/auth/sessions/$id');
  }

  Future<void> revokeDevice(String id) async {
    await dio.delete('/auth/devices/$id');
  }

  Future<void> deleteAccount(String password) async {
    await dio.delete('/auth/account', data: {'password': password});
    await _clearCredentials();
  }

  Future<void> _clearCredentials() async {
    await secureStorage.delete(key: 'accessToken');
    await secureStorage.delete(key: 'refreshToken');
    await secureStorage.delete(key: 'fcmToken');
    await secureStorage.delete(key: sessionModeStorageKey);
    dio.options.headers.remove('Authorization');
  }
}

final moreRepositoryProvider = Provider(
  (ref) => MoreRepository(ref.watch(api), storage),
);

final moreAccountProvider = FutureProvider<MoreAccountData>((ref) async {
  final location = ref.watch(activeLocationProvider);
  if (location == null) throw StateError('No active restaurant location');
  return ref.watch(moreRepositoryProvider).load(location);
});

final accountSecurityProvider = FutureProvider<AccountSecurityData>(
  (ref) => ref.watch(moreRepositoryProvider).security(),
);

final privateAccountRepositoryProvider = Provider(
  (ref) => MoreRepository(ref.watch(api), storage),
);

final appMetadataProvider = FutureProvider<AppMetadata>((_) async {
  final info = await PackageInfo.fromPlatform();
  return AppMetadata(version: info.version, buildNumber: info.buildNumber);
});
