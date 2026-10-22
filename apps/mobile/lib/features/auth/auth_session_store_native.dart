import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_session_store_interface.dart';

AuthSessionStore createAuthSessionStore() => NativeAuthSessionStore();

class NativeAuthSessionStore implements AuthSessionStore {
  const NativeAuthSessionStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String? value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}
