import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'plaid_link.dart';

const _pendingLinkKey = 'fundwell.plaid.pending-link';

PlaidLinkLauncher createPlaidLinkLauncher() => PlaidWebLinkLauncher();

typedef PlaidSuccessCallback = void Function(String publicToken);
typedef PlaidExitCallback = void Function(String? errorMessage);

abstract class PlaidWebSession {
  void open();
  void exit();
}

abstract class PlaidWebSdk {
  PlaidWebSession create({
    required String token,
    String? receivedRedirectUri,
    required PlaidSuccessCallback onSuccess,
    required PlaidExitCallback onExit,
  });
}

abstract class PlaidWebStorage {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

class PlaidWebLinkLauncher implements PlaidLinkLauncher {
  PlaidWebLinkLauncher({
    PlaidWebSdk? sdk,
    PlaidWebStorage? storage,
    Uri Function()? currentUri,
  }) : _sdk = sdk ?? _BrowserPlaidWebSdk(),
       _storage = storage ?? _BrowserPlaidWebStorage(),
       _currentUri = currentUri ?? (() => Uri.base);

  final PlaidWebSdk _sdk;
  final PlaidWebStorage _storage;
  final Uri Function() _currentUri;
  PlaidWebSession? _session;
  bool _opening = false;

  @override
  bool get isWeb => true;

  @override
  Future<PlaidLinkResult> open(PlaidLinkRequest request) {
    return _open(request, persistForOAuth: true);
  }

  @override
  Future<PlaidLinkResult?> resumeOAuth() async {
    if (!isPlaidOAuthReturn(_currentUri())) return null;
    final encoded = _storage.read(_pendingLinkKey);
    if (encoded == null) return null;
    try {
      final json = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      final request = PlaidLinkRequest(
        linkToken: json['linkToken'] as String,
        context: PlaidLinkContext.fromJson(
          Map<String, dynamic>.from(json['context'] as Map),
        ),
      );
      return await _open(
        request,
        persistForOAuth: false,
        receivedRedirectUri: _currentUri().toString(),
      );
    } catch (_) {
      _storage.remove(_pendingLinkKey);
      return null;
    }
  }

  Future<PlaidLinkResult> _open(
    PlaidLinkRequest request, {
    required bool persistForOAuth,
    String? receivedRedirectUri,
  }) async {
    if (_opening) {
      return PlaidLinkResult.error(
        request.context,
        'A bank connection window is already open.',
      );
    }
    _opening = true;
    final completer = Completer<PlaidLinkResult>();
    if (persistForOAuth) {
      // Plaid requires the original Link token after an OAuth redirect. Keep
      // only that short-lived token and non-secret routing IDs in this tab's
      // session storage. Public tokens and access tokens are never persisted.
      _storage.write(
        _pendingLinkKey,
        jsonEncode({
          'linkToken': request.linkToken,
          'context': request.context.toJson(),
        }),
      );
    }
    try {
      _session = _sdk.create(
        token: request.linkToken,
        receivedRedirectUri: receivedRedirectUri,
        onSuccess: (publicToken) {
          _storage.remove(_pendingLinkKey);
          if (!completer.isCompleted) {
            completer.complete(
              PlaidLinkResult.success(publicToken, request.context),
            );
          }
        },
        onExit: (errorMessage) {
          _storage.remove(_pendingLinkKey);
          if (completer.isCompleted) return;
          completer.complete(
            errorMessage == null
                ? PlaidLinkResult.cancelled(request.context)
                : PlaidLinkResult.error(request.context, errorMessage),
          );
        },
      );
      _session!.open();
      return await completer.future;
    } catch (_) {
      _storage.remove(_pendingLinkKey);
      return PlaidLinkResult.error(
        request.context,
        'Unable to open the secure bank connection window.',
      );
    } finally {
      _session = null;
      _opening = false;
    }
  }

  @override
  void dispose() {
    _session?.exit();
    _session = null;
  }
}

class _BrowserPlaidWebStorage implements PlaidWebStorage {
  @override
  String? read(String key) => web.window.sessionStorage.getItem(key);

  @override
  void remove(String key) => web.window.sessionStorage.removeItem(key);

  @override
  void write(String key, String value) =>
      web.window.sessionStorage.setItem(key, value);
}

class _BrowserPlaidWebSdk implements PlaidWebSdk {
  @override
  PlaidWebSession create({
    required String token,
    String? receivedRedirectUri,
    required PlaidSuccessCallback onSuccess,
    required PlaidExitCallback onExit,
  }) {
    final plaid = globalContext.getProperty<JSAny?>('Plaid'.toJS);
    if (plaid == null || plaid.isUndefinedOrNull) {
      throw StateError('Plaid Link JavaScript SDK is unavailable');
    }
    final handler = (plaid as JSObject).callMethod<JSObject>(
      'create'.toJS,
      _PlaidConfiguration(
        token: token,
        receivedRedirectUri: receivedRedirectUri,
        onSuccess: ((JSString publicToken, JSAny? _) {
          onSuccess(publicToken.toDart);
        }).toJS,
        onExit: ((JSAny? error, JSAny? _) {
          onExit(_errorMessage(error));
        }).toJS,
        onEvent: ((JSString eventName, JSAny? metadata) {}).toJS,
        onLoad: (() {}).toJS,
      ),
    );
    return _BrowserPlaidWebSession(handler);
  }

  String? _errorMessage(JSAny? error) {
    if (error == null || error.isUndefinedOrNull) return null;
    final value = (error as JSObject).getProperty<JSAny?>('error_message'.toJS);
    if (value == null || value.isUndefinedOrNull) {
      return 'Plaid could not connect this bank account.';
    }
    return (value as JSString).toDart;
  }
}

class _BrowserPlaidWebSession implements PlaidWebSession {
  _BrowserPlaidWebSession(this._handler);
  final JSObject _handler;

  @override
  void exit() => _handler.callMethod<JSAny?>('exit'.toJS);

  @override
  void open() => _handler.callMethod<JSAny?>('open'.toJS);
}

@JS()
@anonymous
extension type _PlaidConfiguration._(JSObject _) implements JSObject {
  external factory _PlaidConfiguration({
    required String token,
    String? receivedRedirectUri,
    required JSFunction onSuccess,
    required JSFunction onExit,
    required JSFunction onEvent,
    required JSFunction onLoad,
  });
}
