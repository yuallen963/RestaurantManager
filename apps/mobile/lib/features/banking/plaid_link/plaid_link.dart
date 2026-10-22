import 'plaid_link_stub.dart'
    if (dart.library.io) 'plaid_link_native.dart'
    if (dart.library.js_interop) 'plaid_link_web.dart'
    as implementation;

enum PlaidLinkOutcome { success, cancelled, error }

bool isPlaidOAuthReturn(Uri uri) =>
    uri.queryParameters.containsKey('oauth_state_id');

class PlaidLinkContext {
  const PlaidLinkContext({
    required this.organizationId,
    required this.locationId,
    this.connectionId,
  });

  final String organizationId;
  final String locationId;
  final String? connectionId;

  Map<String, dynamic> toJson() => {
    'organizationId': organizationId,
    'locationId': locationId,
    if (connectionId != null) 'connectionId': connectionId,
  };

  factory PlaidLinkContext.fromJson(Map<String, dynamic> json) =>
      PlaidLinkContext(
        organizationId: json['organizationId'] as String,
        locationId: json['locationId'] as String,
        connectionId: json['connectionId'] as String?,
      );
}

class PlaidLinkRequest {
  const PlaidLinkRequest({required this.linkToken, required this.context});

  final String linkToken;
  final PlaidLinkContext context;
}

class PlaidLinkResult {
  const PlaidLinkResult._(
    this.outcome, {
    required this.context,
    this.publicToken,
    this.message,
  });

  factory PlaidLinkResult.success(
    String publicToken,
    PlaidLinkContext context,
  ) => PlaidLinkResult._(
    PlaidLinkOutcome.success,
    context: context,
    publicToken: publicToken,
  );

  factory PlaidLinkResult.cancelled(PlaidLinkContext context) =>
      PlaidLinkResult._(PlaidLinkOutcome.cancelled, context: context);

  factory PlaidLinkResult.error(PlaidLinkContext context, [String? message]) =>
      PlaidLinkResult._(
        PlaidLinkOutcome.error,
        context: context,
        message: message,
      );

  final PlaidLinkOutcome outcome;
  final PlaidLinkContext context;
  final String? publicToken;
  final String? message;
}

abstract class PlaidLinkLauncher {
  bool get isWeb;

  Future<PlaidLinkResult> open(PlaidLinkRequest request);

  Future<PlaidLinkResult?> resumeOAuth();

  void dispose();
}

PlaidLinkLauncher createPlaidLinkLauncher() =>
    implementation.createPlaidLinkLauncher();
