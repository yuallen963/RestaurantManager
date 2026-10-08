import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../main.dart' show api, storage;
import '../dashboard/foundation.dart';

class MoreAccountData {
  const MoreAccountData({
    required this.email,
    required this.organizationName,
    this.role,
  });

  final String email;
  final String organizationName;
  final String? role;
}

class AppMetadata {
  const AppMetadata({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;
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
      role: role,
    );
  }

  Future<void> signOut() async {
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

final appMetadataProvider = FutureProvider<AppMetadata>((_) async {
  final info = await PackageInfo.fromPlatform();
  return AppMetadata(version: info.version, buildNumber: info.buildNumber);
});
