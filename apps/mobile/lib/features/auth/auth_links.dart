import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'auth_screens.dart';

enum AuthLinkKind { verifyEmail, resetPassword }

class AuthLinkTarget {
  const AuthLinkTarget(this.kind, this.token);
  final AuthLinkKind kind;
  final String token;
}

AuthLinkTarget? parseAuthLink(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host != 'restaurantmanager-production-6231.up.railway.app') {
    return null;
  }
  final token = uri.queryParameters['token'];
  if (token == null || token.isEmpty) return null;
  return switch (uri.path) {
    '/verify-email' => AuthLinkTarget(AuthLinkKind.verifyEmail, token),
    '/reset-password' => AuthLinkTarget(AuthLinkKind.resetPassword, token),
    _ => null,
  };
}

abstract class AuthLinkSource {
  Future<Uri?> initialLink();
  Stream<Uri> get links;
}

class AppAuthLinkSource implements AuthLinkSource {
  AppAuthLinkSource([AppLinks? links]) : _links = links ?? AppLinks();
  final AppLinks _links;
  @override
  Future<Uri?> initialLink() => _links.getInitialLink();
  @override
  Stream<Uri> get links => _links.uriLinkStream;
}

class AuthLinkCoordinator {
  AuthLinkCoordinator({required this.navigatorKey, AuthLinkSource? source})
    : source = source ?? AppAuthLinkSource();

  final GlobalKey<NavigatorState> navigatorKey;
  final AuthLinkSource source;
  StreamSubscription<Uri>? _subscription;
  AuthLinkTarget? _pending;
  bool _ready = false;
  String? _lastHandled;

  Future<void> start() async {
    final initial = await source.initialLink();
    if (initial != null) _receive(initial);
    _subscription = source.links.listen(_receive, onError: (_) {});
  }

  void ready() {
    _ready = true;
    _flush();
  }

  void _receive(Uri uri) {
    final target = parseAuthLink(uri);
    if (target == null) return;
    final identity = '${target.kind.name}:${target.token}';
    if (_lastHandled == identity) return;
    _lastHandled = identity;
    _pending = target;
    _flush();
  }

  void _flush() {
    if (!_ready || _pending == null) return;
    final target = _pending!;
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _flush());
      return;
    }
    _pending = null;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => target.kind == AuthLinkKind.verifyEmail
            ? VerifyEmailLinkScreen(token: target.token)
            : ResetPasswordScreen(initialToken: target.token),
      ),
    );
  }

  void dispose() => _subscription?.cancel();
}
