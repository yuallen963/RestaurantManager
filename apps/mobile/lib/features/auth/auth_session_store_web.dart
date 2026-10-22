import 'package:web/web.dart' as web;

import 'auth_session_store_interface.dart';

AuthSessionStore createAuthSessionStore() => WebAuthSessionStore();

/// Keeps the short-lived access token in memory and leaves the refresh token
/// exclusively in the API's HttpOnly cookie. Non-secret navigation state uses
/// session storage so a browser reload can resume the same sign-in flow.
class WebAuthSessionStore implements AuthSessionStore {
  String? _accessToken;

  @override
  Future<String?> read({required String key}) async {
    if (key == 'accessToken') return _accessToken;
    if (key == 'refreshToken') return null;
    return web.window.sessionStorage.getItem(key);
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    if (key == 'accessToken') {
      _accessToken = value;
      return;
    }
    if (key == 'refreshToken') return;
    if (value == null) {
      web.window.sessionStorage.removeItem(key);
    } else {
      web.window.sessionStorage.setItem(key, value);
    }
  }

  @override
  Future<void> delete({required String key}) async {
    if (key == 'accessToken') _accessToken = null;
    if (key != 'refreshToken') web.window.sessionStorage.removeItem(key);
  }
}
