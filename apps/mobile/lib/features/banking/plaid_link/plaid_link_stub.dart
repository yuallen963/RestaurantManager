import 'plaid_link.dart';

PlaidLinkLauncher createPlaidLinkLauncher() => _UnsupportedPlaidLinkLauncher();

class _UnsupportedPlaidLinkLauncher implements PlaidLinkLauncher {
  @override
  bool get isWeb => false;

  @override
  Future<PlaidLinkResult> open(PlaidLinkRequest request) async =>
      PlaidLinkResult.error(
        request.context,
        'Bank connection is not supported on this platform.',
      );

  @override
  Future<PlaidLinkResult?> resumeOAuth() async => null;

  @override
  void dispose() {}
}
