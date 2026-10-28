import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_profit_mobile/features/design/fundwell_theme.dart';
import 'package:restaurant_profit_mobile/features/more/foundation.dart';
import 'package:restaurant_profit_mobile/features/more/team_access_screen.dart';

void main() {
  testWidgets('public demo explains team privacy without exposing identities', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: fundWellTheme(),
          home: const TeamAccessScreen(
            organizationId: 'demo-org',
            role: 'OWNER',
            demoMode: true,
          ),
        ),
      ),
    );
    expect(find.text('Team management is private'), findsOneWidget);
    expect(
      find.textContaining('does not reveal customer identities'),
      findsOneWidget,
    );
    expect(find.text('Invite staff'), findsNothing);
  });

  testWidgets('viewer receives a private access explanation', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: fundWellTheme(),
          home: const TeamAccessScreen(
            organizationId: 'org-a',
            role: 'VIEWER',
            demoMode: false,
          ),
        ),
      ),
    );
    expect(find.text('Owner or administrator access required'), findsOneWidget);
  });

  testWidgets('owner sees members and pending invitations', (tester) async {
    final data = TeamAccessData(
      currentUserId: 'owner-user',
      currentRole: 'OWNER',
      members: const [
        TeamMemberData(
          id: 'member-a',
          userId: 'owner-user',
          email: 'owner@example.com',
          role: 'OWNER',
          firstName: 'Alex',
        ),
      ],
      invitations: [
        TeamInvitationData(
          id: 'invite-a',
          email: 'staff@example.com',
          role: 'VIEWER',
          expiresAt: DateTime.now().add(const Duration(days: 7)),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          teamAccessProvider.overrideWith((ref, organizationId) async => data),
        ],
        child: MaterialApp(
          theme: fundWellTheme(),
          home: const TeamAccessScreen(
            organizationId: 'org-a',
            role: 'OWNER',
            demoMode: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Restaurant team'), findsOneWidget);
    expect(find.text('owner@example.com · Owner'), findsOneWidget);
    expect(find.text('staff@example.com'), findsOneWidget);
    expect(find.text('Invite staff'), findsOneWidget);
    expect(find.text('Revoke'), findsOneWidget);
  });
}
