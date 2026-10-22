@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/banking/plaid_link/plaid_link.dart';
import 'package:restaurant_profit_mobile/features/banking/plaid_link/plaid_link_web.dart';

class FakeStorage implements PlaidWebStorage {
  final values = <String, String>{};
  @override
  String? read(String key) => values[key];
  @override
  void remove(String key) => values.remove(key);
  @override
  void write(String key, String value) => values[key] = value;
}

class FakeSession implements PlaidWebSession {
  FakeSession(this.onOpen);
  final void Function() onOpen;
  @override
  void exit() {}
  @override
  void open() => onOpen();
}

class FakeSdk implements PlaidWebSdk {
  PlaidSuccessCallback? success;
  PlaidExitCallback? exitCallback;
  String? token;
  String? receivedRedirectUri;
  bool completeOnOpen = true;

  @override
  PlaidWebSession create({
    required String token,
    String? receivedRedirectUri,
    required PlaidSuccessCallback onSuccess,
    required PlaidExitCallback onExit,
  }) {
    this.token = token;
    this.receivedRedirectUri = receivedRedirectUri;
    success = onSuccess;
    exitCallback = onExit;
    return FakeSession(() {
      if (completeOnOpen) onSuccess('public-token');
    });
  }
}

const context = PlaidLinkContext(
  organizationId: 'org-a',
  locationId: 'location-a',
);
const request = PlaidLinkRequest(linkToken: 'link-token', context: context);

void main() {
  test(
    'browser selects web Link and returns success without persisting public token',
    () async {
      final sdk = FakeSdk();
      final storage = FakeStorage();
      final launcher = PlaidWebLinkLauncher(
        sdk: sdk,
        storage: storage,
        currentUri: () => Uri.parse('https://app.example.com/banking'),
      );
      expect(launcher.isWeb, isTrue);
      final result = await launcher.open(request);
      expect(result.outcome, PlaidLinkOutcome.success);
      expect(result.publicToken, 'public-token');
      expect(storage.values, isEmpty);
      expect(jsonEncode(storage.values), isNot(contains('public-token')));
    },
  );

  test('cancellation and Plaid errors are distinct outcomes', () async {
    final sdk = FakeSdk()..completeOnOpen = false;
    final launcher = PlaidWebLinkLauncher(
      sdk: sdk,
      storage: FakeStorage(),
      currentUri: () => Uri.parse('https://app.example.com/banking'),
    );
    final cancelledFuture = launcher.open(request);
    sdk.exitCallback!(null);
    expect((await cancelledFuture).outcome, PlaidLinkOutcome.cancelled);

    final errorFuture = launcher.open(request);
    sdk.exitCallback!('Institution unavailable');
    final error = await errorFuture;
    expect(error.outcome, PlaidLinkOutcome.error);
    expect(error.message, 'Institution unavailable');
  });

  test('prevents a repeated launch while Link is open', () async {
    final sdk = FakeSdk()..completeOnOpen = false;
    final launcher = PlaidWebLinkLauncher(
      sdk: sdk,
      storage: FakeStorage(),
      currentUri: () => Uri.parse('https://app.example.com/banking'),
    );
    final first = launcher.open(request);
    final repeated = await launcher.open(request);
    expect(repeated.outcome, PlaidLinkOutcome.error);
    expect(repeated.message, contains('already open'));
    sdk.exitCallback!(null);
    await first;
  });

  test(
    'OAuth return reuses the original Link token and routing context',
    () async {
      final sdk = FakeSdk();
      final storage = FakeStorage();
      storage.write(
        'fundwell.plaid.pending-link',
        jsonEncode({
          'linkToken': 'original-link-token',
          'context': context.toJson(),
        }),
      );
      final redirect = Uri.parse(
        'https://app.example.com/banking?oauth_state_id=state-a',
      );
      final launcher = PlaidWebLinkLauncher(
        sdk: sdk,
        storage: storage,
        currentUri: () => redirect,
      );
      final result = await launcher.resumeOAuth();
      expect(result?.outcome, PlaidLinkOutcome.success);
      expect(result?.context.organizationId, 'org-a');
      expect(sdk.token, 'original-link-token');
      expect(sdk.receivedRedirectUri, redirect.toString());
      expect(storage.values, isEmpty);
    },
  );

  test('ignores a normal page load with no OAuth return state', () async {
    final launcher = PlaidWebLinkLauncher(
      sdk: FakeSdk(),
      storage: FakeStorage(),
      currentUri: () => Uri.parse('https://app.example.com/banking'),
    );
    expect(await launcher.resumeOAuth(), isNull);
  });
}
