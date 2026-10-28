import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/fundwell_theme.dart';
import '../responsive.dart';
import 'foundation.dart';

class TeamAccessScreen extends ConsumerWidget {
  const TeamAccessScreen({
    required this.organizationId,
    required this.role,
    required this.demoMode,
    super.key,
  });
  final String organizationId, role;
  final bool demoMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = !demoMode && (role == 'OWNER' || role == 'ADMIN');
    return Scaffold(
      appBar: AppBar(title: const Text('Team & Access')),
      body: ResponsiveContent(
        maxWidth: 1000,
        child: canManage
            ? ref
                  .watch(teamAccessProvider(organizationId))
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _MessageState(
                      icon: Icons.error_outline,
                      title: 'Team access is unavailable',
                      message: _errorMessage(error),
                      action: OutlinedButton(
                        onPressed: () =>
                            ref.invalidate(teamAccessProvider(organizationId)),
                        child: const Text('Try again'),
                      ),
                    ),
                    data: (data) => _TeamContent(
                      organizationId: organizationId,
                      data: data,
                    ),
                  )
            : _MessageState(
                icon: demoMode ? Icons.visibility_outlined : Icons.lock_outline,
                title: demoMode
                    ? 'Team management is private'
                    : 'Owner or administrator access required',
                message: demoMode
                    ? 'The public demo does not reveal customer identities or allow invitations and permission changes. Open Private Account to manage your restaurant team.'
                    : 'Your role can use FundWell but cannot view private team identities or change organization access.',
              ),
      ),
    );
  }
}

class _TeamContent extends ConsumerWidget {
  const _TeamContent({required this.organizationId, required this.data});
  final String organizationId;
  final TeamAccessData data;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(teamAccessProvider(organizationId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = data.invitations.where((invite) => invite.pending).toList();
    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        padding: const EdgeInsets.all(FundWellTokens.space6),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Restaurant team',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Control who can access this organization and what they can manage.',
                    style: TextStyle(color: FundWellTokens.mutedInk),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: () => _invite(context, ref),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Invite staff'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SectionCard(
            title: 'Team members',
            subtitle: '${data.members.length} people with access',
            children: [
              for (var index = 0; index < data.members.length; index++) ...[
                _MemberRow(
                  organizationId: organizationId,
                  member: data.members[index],
                  actorRole: data.currentRole,
                  currentUserId: data.currentUserId,
                ),
                if (index < data.members.length - 1) const Divider(height: 1),
              ],
            ],
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Pending invitations',
            subtitle: pending.isEmpty
                ? 'No invitations are waiting'
                : '${pending.length} waiting for acceptance',
            children: pending.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'New invitations will appear here until accepted, expired, or revoked.',
                        style: TextStyle(color: FundWellTokens.mutedInk),
                      ),
                    ),
                  ]
                : [
                    for (var index = 0; index < pending.length; index++) ...[
                      _InvitationRow(
                        organizationId: organizationId,
                        invitation: pending[index],
                      ),
                      if (index < pending.length - 1) const Divider(height: 1),
                    ],
                  ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Owners control all restaurant settings. Administrators manage operations and staff access. Viewers have read-only access.',
            style: TextStyle(color: FundWellTokens.mutedInk),
          ),
        ],
      ),
    );
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _InviteDialog(),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(teamAccessRepositoryProvider)
          .invite(organizationId, result.$1, result.$2);
      ref.invalidate(teamAccessProvider(organizationId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invitation sent to ${result.$1}.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    }
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.organizationId,
    required this.member,
    required this.actorRole,
    required this.currentUserId,
  });
  final String organizationId, actorRole, currentUserId;
  final TeamMemberData member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelf = member.userId == currentUserId;
    final canEdit =
        !isSelf && actorRole == 'OWNER' && member.role != 'OWNER' ||
        !isSelf &&
            actorRole == 'ADMIN' &&
            (member.role == 'MANAGER' || member.role == 'VIEWER');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: FundWellTokens.surfaceSubtle,
        child: Text(
          (member.name.isNotEmpty ? member.name : member.email)
              .substring(0, 1)
              .toUpperCase(),
        ),
      ),
      title: Text(
        member.name.isEmpty ? member.email : member.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: member.name.isEmpty
          ? Text(_role(member.role))
          : Text('${member.email} · ${_role(member.role)}'),
      trailing: canEdit
          ? PopupMenuButton<String>(
              onSelected: (value) => value == 'REMOVE'
                  ? _remove(context, ref)
                  : _changeRole(context, ref, value),
              itemBuilder: (_) => [
                if (actorRole == 'OWNER')
                  const PopupMenuItem(
                    value: 'ADMIN',
                    child: Text('Make administrator'),
                  ),
                const PopupMenuItem(
                  value: 'VIEWER',
                  child: Text('Make viewer'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'REMOVE',
                  child: Text('Remove access'),
                ),
              ],
            )
          : Chip(
              label: Text(
                isSelf ? '${_role(member.role)} · You' : _role(member.role),
              ),
            ),
    );
  }

  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    String role,
  ) async {
    if (role == member.role) return;
    try {
      await ref
          .read(teamAccessRepositoryProvider)
          .updateRole(organizationId, member.id, role);
      ref.invalidate(teamAccessProvider(organizationId));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Remove team access?'),
            content: Text(
              '${member.email} will no longer be able to access this restaurant.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    try {
      await ref
          .read(teamAccessRepositoryProvider)
          .removeMember(organizationId, member.id);
      ref.invalidate(teamAccessProvider(organizationId));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    }
  }
}

class _InvitationRow extends ConsumerWidget {
  const _InvitationRow({
    required this.organizationId,
    required this.invitation,
  });
  final String organizationId;
  final TeamInvitationData invitation;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
    leading: const CircleAvatar(
      backgroundColor: FundWellTokens.surfaceSubtle,
      child: Icon(Icons.mail_outline),
    ),
    title: Text(
      invitation.email,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      '${_role(invitation.role)} · Expires ${MaterialLocalizations.of(context).formatMediumDate(invitation.expiresAt.toLocal())}',
    ),
    trailing: TextButton(
      onPressed: () async {
        try {
          await ref
              .read(teamAccessRepositoryProvider)
              .revokeInvitation(invitation.id);
          ref.invalidate(teamAccessProvider(organizationId));
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
          }
        }
      },
      child: const Text('Revoke'),
    ),
  );
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog();
  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final email = TextEditingController();
  String role = 'VIEWER';
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Invite staff'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Work email'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: role,
            decoration: const InputDecoration(labelText: 'Access level'),
            items: const [
              DropdownMenuItem(
                value: 'VIEWER',
                child: Text('Viewer — read only'),
              ),
              DropdownMenuItem(
                value: 'ADMIN',
                child: Text('Administrator — manage restaurant'),
              ),
            ],
            onChanged: (value) => setState(() => role = value ?? 'VIEWER'),
          ),
          const SizedBox(height: 12),
          const Text(
            'The invitation expires in 7 days and can be used once.',
            style: TextStyle(color: FundWellTokens.mutedInk),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final value = email.text.trim();
          if (value.contains('@')) Navigator.pop(context, (value, role));
        },
        child: const Text('Send invitation'),
      ),
    ],
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title, subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: FundWellTokens.mutedInk),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ...children,
      ],
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 36, color: FundWellTokens.purple),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: FundWellTokens.mutedInk),
                ),
                if (action != null) ...[const SizedBox(height: 20), action!],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String _role(String role) => switch (role) {
  'OWNER' => 'Owner',
  'ADMIN' => 'Administrator',
  'MANAGER' => 'Manager',
  _ => 'Viewer',
};
String _errorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
  }
  return 'Something went wrong. Please try again.';
}
