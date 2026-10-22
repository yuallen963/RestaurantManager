import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/banking/plaid_link/plaid_link.dart';

void main() {
  test('VM/mobile selects the native Plaid Link implementation', () {
    final launcher = createPlaidLinkLauncher();
    expect(launcher.isWeb, isFalse);
    launcher.dispose();
  });

  test('OAuth return detection requires Plaid state', () {
    expect(
      isPlaidOAuthReturn(
        Uri.parse('https://app.example.com/?oauth_state_id=state-a'),
      ),
      isTrue,
    );
    expect(isPlaidOAuthReturn(Uri.parse('https://app.example.com/')), isFalse);
  });
}
