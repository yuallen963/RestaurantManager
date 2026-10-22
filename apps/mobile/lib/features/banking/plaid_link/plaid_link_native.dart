import 'dart:async';

import 'package:plaid_link_flutter/plaid_link_flutter.dart';

import 'plaid_link.dart';

PlaidLinkLauncher createPlaidLinkLauncher() => _NativePlaidLinkLauncher();

class _NativePlaidLinkLauncher implements PlaidLinkLauncher {
  PlaidLinkSession? _session;
  bool _opening = false;

  @override
  bool get isWeb => false;

  @override
  Future<PlaidLinkResult> open(PlaidLinkRequest request) async {
    if (_opening) {
      return PlaidLinkResult.error(
        request.context,
        'A bank connection window is already open.',
      );
    }
    _opening = true;
    final completer = Completer<PlaidLinkResult>();
    try {
      _session = await createPlaidLinkSession(
        LinkTokenConfiguration(
          token: request.linkToken,
          onSuccess: (success) {
            if (!completer.isCompleted) {
              completer.complete(
                PlaidLinkResult.success(success.publicToken, request.context),
              );
            }
          },
          onExit: (exit) {
            if (completer.isCompleted) return;
            final message = exit.error?.errorMessage;
            completer.complete(
              message == null
                  ? PlaidLinkResult.cancelled(request.context)
                  : PlaidLinkResult.error(request.context, message),
            );
          },
          onEvent: (_) {},
        ),
      );
      await _session!.open(true);
      return await completer.future;
    } catch (_) {
      return PlaidLinkResult.error(
        request.context,
        'Unable to open the secure bank connection window.',
      );
    } finally {
      _session?.dispose();
      _session = null;
      _opening = false;
    }
  }

  @override
  Future<PlaidLinkResult?> resumeOAuth() async => null;

  @override
  void dispose() {
    _session?.dispose();
    _session = null;
  }
}
