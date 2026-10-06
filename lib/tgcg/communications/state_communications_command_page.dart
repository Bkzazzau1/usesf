import 'package:flutter/material.dart';

import '../assignments/assignment_store.dart';
import '../governance/governance_store.dart';
import '../meeting/operational_call_store.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'bulk_communications_store.dart';
import 'communications_store.dart';

class StateCommunicationSnapshot {
  const StateCommunicationSnapshot({
    required this.contacts,
    required this.rooms,
    required this.messages,
    required this.broadcasts,
    required this.jobs,
    required this.providers,
    required this.calls,
  });

  final List<CommunicationContact> contacts;
  final List<OperationalRoom> rooms;
  final List<OperationalMessage> messages;
  final List<OperationalBroadcast> broadcasts;
  final List<BulkDeliveryJob> jobs;
  final List<BulkDeliveryProvider> providers;
  final List<OperationalCallSession> calls;

  int eligible(BulkCommunicationChannel channel) =>
      contacts.where((item) => item.eligibleFor(channel)).length;

  int get suppressed =>
      contacts.where((item) => item.preference.suppressed).length;
  int get noEligibleChannel => contacts
      .where(
        (item) =>
            !BulkCommunicationChannel.values.any(item.eligibleFor) &&
            !item.preference.suppressed,
      )
      .length;
  int get queuedMessages => messages
      .where(
        (item) =>
            item.deliveryState == MessageDeliveryState.localQueued ||
            item.deliveryState == MessageDeliveryState.sending,
      )
      .length;
  int get failedMessages => messages
      .where((item) => item.deliveryState == MessageDeliveryState.failed)
      .length;
  int get queuedBroadcasts => broadcasts
      .where((item) => item.deliveryState == BroadcastDeliveryState.queued)
      .length;
  int get problemBroadcasts => broadcasts
      .where(
        (item) =>
            item.deliveryState == BroadcastDeliveryState.failed ||
            item.deliveryState == BroadcastDeliveryState.partiallyDelivered,
      )
      .length;
  int get activeJobs => jobs
      .where(
        (item) =>
            item.state == BulkDeliveryJobState.queued ||
            item.state == BulkDeliveryJobState.waitingForProvider ||
            item.state == BulkDeliveryJobState.processing,
      )
      .length;
  int get problemJobs => jobs
      .where(
        (item) =>
            item.state == BulkDeliveryJobState.failed ||
            item.state == BulkDeliveryJobState.partiallyDelivered,
      )
      .length;
  int get providerReady =>
      providers.where((item) => item.state == ProviderConnectionState.ready).length;
  int get providerProblems =>
      providers.where((item) => item.state != ProviderConnectionState.ready).length;
  int get openCalls => calls.where((item) => item.isOpen).length;
}

class StateCommunicationException {
  const StateCommunicationException({
    required this.title,
    required this.detail,
    required this.severity,
    required this.module,
  });

  final String title;
  final String detail;
  final int severity;
  final TgcgModule module;
}

StateCommunicationSnapshot buildStateCommunicationSnapshot({
  required CommunicationsController communications,
  required BulkCommunicationsController bulk,
  required OperationalCallController calls,
}) =>
    StateCommunicationSnapshot(
      contacts: List.unmodifiable(
        bulk.contactsForScope(GeographicScope.kaduna),
      ),
      rooms: List.unmodifiable(
        communications.roomsForScope(GeographicScope.kaduna),
      ),
      messages: List.unmodifiable(communications.messages),
      broadcasts: List.unmodifiable(
        communications.broadcastsForScope(GeographicScope.kaduna),
      ),
      jobs: List.unmodifiable(
        bulk.jobsForScope(GeographicScope.kaduna),
      ),
      providers: List.unmodifiable(bulk.providers),
      calls: List.unmodifiable(calls.calls),
    );

List<StateCommunicationException> buildStateCommunicationExceptions(
  StateCommunicationSnapshot snapshot,
) {
  final items = <StateCommunicationException>[];
  if (snapshot.failedMessages > 0) {
    items.add(
      StateCommunicationException(
        title: 'Operational messages failed',
        detail: '${snapshot.failedMessages} message(s) failed delivery.',
        severity: 4,
        module: TgcgModule.communications,
      ),
    );
  }
  if (snapshot.problemBroadcasts > 0) {
    items.add(
      StateCommunicationException(
        title: 'Broadcast delivery problem',
        detail:
            '${snapshot.problemBroadcasts} broadcast(s) failed or partially delivered.',
        severity: 4,
        module: TgcgModule.communications,
      ),
    );
  }
  if (snapshot.problemJobs > 0) {
    items.add(
      StateCommunicationException(
        title: 'Bulk delivery problem',
        detail:
            '${snapshot.problemJobs} bulk job(s) failed or partially delivered.',
        severity: 4,
        module: TgcgModule.bulkCommunications,
      ),
    );
  }
  final waitingProvider = snapshot.jobs
      .where((item) => item.state == BulkDeliveryJobState.waitingForProvider)
      .length;
  if (waitingProvider > 0) {
    items.add(
      StateCommunicationException(
        title: 'Delivery jobs waiting for provider',
        detail: '$waitingProvider job(s) cannot progress until a provider is ready.',
        severity: 3,
        module: TgcgModule.bulkCommunications,
      ),
    );
  }
  if (snapshot.providerProblems > 0) {
    items.add(
      StateCommunicationException(
        title: 'Communication provider readiness gap',
        detail:
            '${snapshot.providerProblems} provider connection(s) are not ready for delivery.',
        severity: 3,
        module: TgcgModule.bulkCommunications,
      ),
    );
  }
  if (snapshot.noEligibleChannel > 0) {
    items.add(
      StateCommunicationException(
        title: 'Members without eligible outbound channel',
        detail:
            '${snapshot.noEligibleChannel} contact(s) have no opted-in usable Push/SMS/Email/Voice route.',
        severity: 2,
        module: TgcgModule.bulkCommunications,
      ),
    );
  }
  if (snapshot.queuedMessages > 0) {
    items.add(
      StateCommunicationException(
        title: 'Operational messages still queued',
        detail: '${snapshot.queuedMessages} message(s) have not reached delivered state.',
        severity: 2,
        module: TgcgModule.communications,
      ),
    );
  }
  items.sort((a, b) => b.severity.compareTo(a.severity));
  return List.unmodifiable(items);
}

class StateCommunicationsCommandPage extends StatefulWidget {
  const StateCommunicationsCommandPage({
    super.key,
    required this.onOpenModule,
  });

  final ValueChanged<TgcgModule> onOpenModule;

  @override
  State<StateCommunicationsCommandPage> createState() =>
      _StateCommunicationsCommandPageState();
}

class _StateCommunicationsCommandPageState
    extends State<StateCommunicationsCommandPage> {
  final _broadcastTitle = TextEditingController();
  final _broadcastBody = TextEditingController();
  final _bulkTitle = TextEditingController();
  final _bulkBody = TextEditingController();

  GeographicScope _targetScope = GeographicScope.kaduna;
  TgcgRole? _targetRole;
  String? _groupId;
  BulkCommunicationPurpose _purpose = BulkCommunicationPurpose.operations;
  final Set<BulkCommunicationChannel> _channels = {
    BulkCommunicationChannel.push,
    BulkCommunicationChannel.sms,
  };
  bool _sending = false;

  @override
  void dispose() {
    _broadcastTitle.dispose();
    _broadcastBody.dispose();
    _bulkTitle.dispose();
    _bulkBody.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (session.role != TgcgRole.stateCoordinator) {
      return const Center(
        child: TgcgEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'State Communications unavailable',
          message: 'State Coordinator authority is required.',
        ),
      );
    }

    final membership = MembershipOperations.of(context);
    final assignments = Assignments.of(context);
    final governance = GovernanceOperations.of(context);
    final communications = Communications.of(context);
    final bulk = BulkCommunications.of(context);
    final calls = OperationalCalls.of(context);

    final snapshot = buildStateCommunicationSnapshot(
      communications: communications,
      bulk: bulk,
      calls: calls,
    );
    final exceptions = buildStateCommunicationExceptions(snapshot);
    final scopes = _targetScopes(membership);
    final matchingScope = scopes.where(
      (item) => _sameScope(item, _targetScope),
    );
    _targetScope = matchingScope.isEmpty
        ? scopes.first
        : matchingScope.first;

    final activeGroups = assignments.groupAssignments
        .where((item) => !item.isTerminal)
        .toList(growable: false);
    if (_groupId != null &&
        !activeGroups.any((item) => item.id == _groupId)) {
      _groupId = null;
    }
    final selectedGroup = _groupId == null
        ? null
        : activeGroups.where((item) => item.id == _groupId).firstOrNull;

    final audience = _previewAudience(
      bulk: bulk,
      governance: governance,
      scope: _targetScope,
      role: _targetRole,
      explicitMemberIds: selectedGroup?.memberIds ?? const [],
      channels: _channels,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        const TgcgPageHeader(
          eyebrow: 'STATE COMMUNICATIONS COMMAND',
          title: 'State Communications Command',
          subtitle: 'Kaduna State • targeting, delivery accountability and escalation',
          trailing: TgcgStatusPill(
            label: 'STATE COORDINATOR',
            color: TgcgColors.primary,
            icon: Icons.campaign_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _Metrics(snapshot: snapshot),
        const SizedBox(height: 16),
        _CommandActions(onOpen: widget.onOpenModule),
        const SizedBox(height: 16),
        _Exceptions(
          items: exceptions,
          onOpen: widget.onOpenModule,
        ),
        const SizedBox(height: 16),
        _LgaReachabilityBoard(
          membership: membership,
          bulk: bulk,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final operational = _OperationalBroadcastComposer(
              scopes: scopes,
              targetScope: _targetScope,
              title: _broadcastTitle,
              body: _broadcastBody,
              sending: _sending,
              onScope: (scope) => setState(() => _targetScope = scope),
              onSend: () => _sendOperationalBroadcast(
                context,
                communications: communications,
                session: session,
              ),
            );
            final targeted = _TargetedBulkComposer(
              scopes: scopes,
              groups: activeGroups,
              targetScope: _targetScope,
              targetRole: _targetRole,
              groupId: _groupId,
              purpose: _purpose,
              channels: _channels,
              audience: audience,
              title: _bulkTitle,
              body: _bulkBody,
              sending: _sending,
              onScope: (scope) => setState(() => _targetScope = scope),
              onRole: (role) => setState(() => _targetRole = role),
              onGroup: (id) => setState(() => _groupId = id),
              onPurpose: (value) => setState(() => _purpose = value),
              onChannel: (channel) => setState(() {
                if (_channels.contains(channel)) {
                  if (_channels.length > 1) _channels.remove(channel);
                } else {
                  _channels.add(channel);
                }
              }),
              onQueue: () => _queueBulk(
                context,
                bulk: bulk,
                session: session,
                group: selectedGroup,
              ),
            );
            if (constraints.maxWidth < 1080) {
              return Column(
                children: [
                  operational,
                  const SizedBox(height: 14),
                  targeted,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: operational),
                const SizedBox(width: 14),
                Expanded(child: targeted),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _RecentActivity(snapshot: snapshot),
      ],
    );
  }

  Future<void> _sendOperationalBroadcast(
    BuildContext context, {
    required CommunicationsController communications,
    required TgcgSessionController session,
  }) async {
    setState(() => _sending = true);
    try {
      final ok = await communications.sendBroadcast(
        title: _broadcastTitle.text,
        body: _broadcastBody.text,
        targetScope: _targetScope,
        senderId:
            session.accessId.isEmpty ? session.operatorName : session.accessId,
        role: TgcgRole.stateCoordinator,
        userScope: GeographicScope.kaduna,
        capabilityAuthorized: true,
      );
      if (!context.mounted) return;
      if (ok) {
        _broadcastTitle.clear();
        _broadcastBody.clear();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Operational broadcast queued for ${_targetScope.label}.'
                : 'Broadcast was not queued. Check title/body and target.',
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Broadcast could not be queued securely on this device.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _queueBulk(
    BuildContext context, {
    required BulkCommunicationsController bulk,
    required TgcgSessionController session,
    required GroupAssignment? group,
  }) async {
    setState(() => _sending = true);
    try {
      final job = await bulk.queueJob(
        title: _bulkTitle.text,
        body: _bulkBody.text,
        purpose: _purpose,
        targetScope: _targetScope,
        channels: _channels.toList(growable: false),
        actorId:
            session.accessId.isEmpty ? session.operatorName : session.accessId,
        actorRole: TgcgRole.stateCoordinator,
        actorScope: GeographicScope.kaduna,
        targetRoles: _targetRole == null ? const [] : [_targetRole!],
        targetMemberIds: group?.memberIds ?? const [],
      );
      if (!context.mounted) return;
      if (job != null) {
        _bulkTitle.clear();
        _bulkBody.clear();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            job == null
                ? 'No eligible recipients. Check consent, audience and channels.'
                : '${job.id} queued for ${job.eligibleRecipientCount} eligible recipient(s).',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _AudiencePreview {
  const _AudiencePreview({
    required this.targetContacts,
    required this.eligibleRecipients,
    required this.suppressed,
  });

  final int targetContacts;
  final int eligibleRecipients;
  final int suppressed;
}

_AudiencePreview _previewAudience({
  required BulkCommunicationsController bulk,
  required GovernanceOperationsController governance,
  required GeographicScope scope,
  required TgcgRole? role,
  required List<String> explicitMemberIds,
  required Set<BulkCommunicationChannel> channels,
}) {
  var contacts = bulk.contactsForScope(scope);
  if (role != null) {
    contacts = contacts.where((contact) {
      return governance
          .activeRolesForMember(contact.memberId)
          .any((item) => item.role == role);
    }).toList(growable: false);
  }
  if (explicitMemberIds.isNotEmpty) {
    final ids = explicitMemberIds.toSet();
    contacts =
        contacts.where((item) => ids.contains(item.memberId)).toList(growable: false);
  }
  final suppressed =
      contacts.where((item) => item.preference.suppressed).length;
  final eligible = contacts.where((contact) {
    return channels.any(contact.eligibleFor);
  }).length;
  return _AudiencePreview(
    targetContacts: contacts.length,
    eligibleRecipients: eligible,
    suppressed: suppressed,
  );
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.snapshot});
  final StateCommunicationSnapshot snapshot;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1100
              ? 6
              : constraints.maxWidth >= 720
                  ? 3
                  : constraints.maxWidth >= 460
                      ? 2
                      : 1;
          const gap = 10.0;
          final width =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Contacts',
                value: '${snapshot.contacts.length}',
                detail: '${snapshot.suppressed} suppressed',
                icon: Icons.contacts_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Push eligible',
                value: '${snapshot.eligible(BulkCommunicationChannel.push)}',
                detail: 'Approved app-device + consent',
                icon: Icons.notifications_active_outlined,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'SMS eligible',
                value: '${snapshot.eligible(BulkCommunicationChannel.sms)}',
                detail: 'Phone + consent',
                icon: Icons.sms_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Delivery jobs',
                value: '${snapshot.activeJobs}',
                detail: '${snapshot.problemJobs} problem jobs',
                icon: Icons.outbox_outlined,
                tone: snapshot.problemJobs == 0
                    ? TgcgMetricTone.info
                    : TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Providers',
                value: '${snapshot.providerReady}/${snapshot.providers.length}',
                detail: 'Ready connections',
                icon: Icons.hub_outlined,
                tone: snapshot.providerReady > 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Operational calls',
                value: '${snapshot.openCalls}',
                detail: 'Currently ringing / active',
                icon: Icons.call_outlined,
                tone: TgcgMetricTone.neutral,
              ),
            ],
          );
        },
      );
}

class _CommandActions extends StatelessWidget {
  const _CommandActions({required this.onOpen});
  final ValueChanged<TgcgModule> onOpen;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Communication workspaces',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.bulkCommunications),
              icon: const Icon(Icons.send_to_mobile_outlined),
              label: const Text('Bulk Communications'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.discussionRoom),
              icon: const Icon(Icons.dynamic_feed_outlined),
              label: const Text('Discussion Forum'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.meetingRoom),
              icon: const Icon(Icons.video_camera_front_outlined),
              label: const Text('Meeting Room'),
            ),
            OutlinedButton.icon(
              onPressed: () => onOpen(TgcgModule.membershipNetwork),
              icon: const Icon(Icons.groups_2_outlined),
              label: const Text('Membership Intelligence'),
            ),
          ],
        ),
      );
}

class _Exceptions extends StatelessWidget {
  const _Exceptions({
    required this.items,
    required this.onOpen,
  });

  final List<StateCommunicationException> items;
  final ValueChanged<TgcgModule> onOpen;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Needs attention',
        trailing: TgcgStatusPill(
          label: '${items.length} OPEN',
          color: items.isEmpty ? TgcgColors.success : TgcgColors.warning,
          compact: true,
        ),
        child: items.isEmpty
            ? const TgcgStatusPill(
                label: 'NO CURRENT COMMUNICATION EXCEPTION',
                color: TgcgColors.success,
                icon: Icons.check_circle_outline_rounded,
              )
            : Column(
                children: [
                  for (final item in items)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onOpen(item.module),
                        borderRadius: BorderRadius.circular(TgcgRadius.sm),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _severityColor(item.severity)
                                .withValues(alpha: .04),
                            borderRadius:
                                BorderRadius.circular(TgcgRadius.sm),
                            border: Border.all(
                              color: _severityColor(item.severity)
                                  .withValues(alpha: .16),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: _severityColor(item.severity),
                                size: 19,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        color: TgcgColors.ink,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      item.detail,
                                      style: const TextStyle(
                                        color: TgcgColors.muted,
                                        fontSize: 9.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: TgcgColors.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      );
}

class _LgaReachabilityBoard extends StatelessWidget {
  const _LgaReachabilityBoard({
    required this.membership,
    required this.bulk,
  });

  final MembershipOperationsController membership;
  final BulkCommunicationsController bulk;

  @override
  Widget build(BuildContext context) {
    final lgas = membership.geography.lgas;
    return TgcgSectionCard(
      title: 'LGA communication reachability',
      child: Column(
        children: [
          for (final lga in lgas)
            Builder(
              builder: (context) {
                final contacts = bulk.contactsForScope(lga.scope);
                int eligible(BulkCommunicationChannel channel) => contacts
                    .where((item) => item.eligibleFor(channel))
                    .length;
                return Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: TgcgColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(TgcgRadius.sm),
                    border: Border.all(color: TgcgColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          lga.name,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          TgcgStatusPill(
                            label: '${contacts.length} CONTACTS',
                            color: TgcgColors.info,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label:
                                '${eligible(BulkCommunicationChannel.push)} PUSH',
                            color: TgcgColors.ai,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label:
                                '${eligible(BulkCommunicationChannel.sms)} SMS',
                            color: TgcgColors.success,
                            compact: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _OperationalBroadcastComposer extends StatelessWidget {
  const _OperationalBroadcastComposer({
    required this.scopes,
    required this.targetScope,
    required this.title,
    required this.body,
    required this.sending,
    required this.onScope,
    required this.onSend,
  });

  final List<GeographicScope> scopes;
  final GeographicScope targetScope;
  final TextEditingController title;
  final TextEditingController body;
  final bool sending;
  final ValueChanged<GeographicScope> onScope;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Operational broadcast',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<GeographicScope>(
              initialValue: targetScope,
              decoration: const InputDecoration(labelText: 'Target geography'),
              items: [
                for (final scope in scopes)
                  DropdownMenuItem(
                    value: scope,
                    child: Text(_scopeLabel(scope)),
                  ),
              ],
              onChanged: sending
                  ? null
                  : (value) {
                      if (value != null) onScope(value);
                    },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: title,
              enabled: !sending,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: body,
              enabled: !sending,
              minLines: 4,
              maxLines: 7,
              decoration:
                  const InputDecoration(labelText: 'Operational notice'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: sending ? null : onSend,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Queue operational broadcast'),
            ),
          ],
        ),
      );
}

class _TargetedBulkComposer extends StatelessWidget {
  const _TargetedBulkComposer({
    required this.scopes,
    required this.groups,
    required this.targetScope,
    required this.targetRole,
    required this.groupId,
    required this.purpose,
    required this.channels,
    required this.audience,
    required this.title,
    required this.body,
    required this.sending,
    required this.onScope,
    required this.onRole,
    required this.onGroup,
    required this.onPurpose,
    required this.onChannel,
    required this.onQueue,
  });

  final List<GeographicScope> scopes;
  final List<GroupAssignment> groups;
  final GeographicScope targetScope;
  final TgcgRole? targetRole;
  final String? groupId;
  final BulkCommunicationPurpose purpose;
  final Set<BulkCommunicationChannel> channels;
  final _AudiencePreview audience;
  final TextEditingController title;
  final TextEditingController body;
  final bool sending;
  final ValueChanged<GeographicScope> onScope;
  final ValueChanged<TgcgRole?> onRole;
  final ValueChanged<String?> onGroup;
  final ValueChanged<BulkCommunicationPurpose> onPurpose;
  final ValueChanged<BulkCommunicationChannel> onChannel;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Targeted bulk delivery',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<GeographicScope>(
              initialValue: targetScope,
              decoration: const InputDecoration(labelText: 'Target geography'),
              items: [
                for (final scope in scopes)
                  DropdownMenuItem(
                    value: scope,
                    child: Text(_scopeLabel(scope)),
                  ),
              ],
              onChanged: sending
                  ? null
                  : (value) {
                      if (value != null) onScope(value);
                    },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<TgcgRole?>(
              initialValue: targetRole,
              decoration: const InputDecoration(labelText: 'Role filter'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All roles'),
                ),
                for (final role in _targetableRoles)
                  DropdownMenuItem(
                    value: role,
                    child: Text(_roleLabel(role)),
                  ),
              ],
              onChanged: sending ? null : onRole,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: groupId,
              decoration:
                  const InputDecoration(labelText: 'Assignment group filter'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All members in audience'),
                ),
                for (final group in groups)
                  DropdownMenuItem(
                    value: group.id,
                    child: Text(group.title),
                  ),
              ],
              onChanged: sending ? null : onGroup,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<BulkCommunicationPurpose>(
              initialValue: purpose,
              decoration: const InputDecoration(labelText: 'Purpose'),
              items: [
                for (final item in BulkCommunicationPurpose.values)
                  DropdownMenuItem(
                    value: item,
                    child: Text(_purposeLabel(item)),
                  ),
              ],
              onChanged: sending
                  ? null
                  : (value) {
                      if (value != null) onPurpose(value);
                    },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final channel in BulkCommunicationChannel.values)
                  FilterChip(
                    selected: channels.contains(channel),
                    onSelected:
                        sending ? null : (_) => onChannel(channel),
                    label: Text(_channelLabel(channel)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                TgcgStatusPill(
                  label: '${audience.targetContacts} TARGET',
                  color: TgcgColors.info,
                  compact: true,
                ),
                TgcgStatusPill(
                  label: '${audience.eligibleRecipients} ELIGIBLE',
                  color: audience.eligibleRecipients > 0
                      ? TgcgColors.success
                      : TgcgColors.warning,
                  compact: true,
                ),
                TgcgStatusPill(
                  label: '${audience.suppressed} SUPPRESSED',
                  color: audience.suppressed == 0
                      ? TgcgColors.muted
                      : TgcgColors.warning,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: title,
              enabled: !sending,
              decoration: const InputDecoration(labelText: 'Message title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: body,
              enabled: !sending,
              minLines: 4,
              maxLines: 7,
              decoration:
                  const InputDecoration(labelText: 'Delivery message'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: sending ? null : onQueue,
              icon: const Icon(Icons.send_to_mobile_outlined),
              label: const Text('Queue targeted delivery'),
            ),
          ],
        ),
      );
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.snapshot});
  final StateCommunicationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final jobs = snapshot.jobs.take(8).toList(growable: false);
    final broadcasts = snapshot.broadcasts.take(6).toList(growable: false);
    return TgcgSectionCard(
      title: 'Recent communication activity',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final job in jobs)
            _ActivityRow(
              icon: Icons.send_to_mobile_outlined,
              title: job.title,
              detail:
                  '${job.targetScope.label} • ${job.eligibleRecipientCount} eligible • ${job.state.name.toUpperCase()}',
              color: _jobColor(job.state),
            ),
          for (final broadcast in broadcasts)
            _ActivityRow(
              icon: Icons.campaign_outlined,
              title: broadcast.title,
              detail:
                  '${broadcast.scope.label} • ${broadcast.deliveryState.name.toUpperCase()}',
              color: _broadcastColor(broadcast.deliveryState),
            ),
          if (jobs.isEmpty && broadcasts.isEmpty)
            const TgcgEmptyState(
              icon: Icons.forum_outlined,
              title: 'No communication activity',
              message: 'Broadcasts and delivery jobs will appear here.',
            ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceRaised,
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 10.5,
                    ),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

List<GeographicScope> _targetScopes(MembershipOperationsController membership) {
  final scopes = <GeographicScope>[GeographicScope.kaduna];
  scopes.addAll(membership.geography.lgas.map((item) => item.scope));
  final wards = <String, GeographicScope>{};
  for (final unit in membership.geography.pollingUnits) {
    final wardId = unit.scope.wardId;
    if (wardId == null) continue;
    wards[wardId] = GeographicScope(
      level: GeographyLevel.ward,
      country: unit.scope.country,
      zoneId: unit.scope.zoneId,
      zoneName: unit.scope.zoneName,
      stateId: unit.scope.stateId,
      stateName: unit.scope.stateName,
      senatorialDistrictId: unit.scope.senatorialDistrictId,
      senatorialDistrictName: unit.scope.senatorialDistrictName,
      lgaId: unit.scope.lgaId,
      lgaName: unit.scope.lgaName,
      wardId: unit.scope.wardId,
      wardName: unit.scope.wardName,
    );
  }
  scopes.addAll(wards.values);
  return List.unmodifiable(scopes);
}

const _targetableRoles = <TgcgRole>[
  TgcgRole.senatorialCoordinator,
  TgcgRole.lgaCoordinator,
  TgcgRole.wardCoordinator,
  TgcgRole.pollingUnitCoordinator,
  TgcgRole.pollingUnitAgent,
  TgcgRole.mediaOfficer,
  TgcgRole.womenMobilizationCoordinator,
  TgcgRole.youthMobilizationCoordinator,
  TgcgRole.communicationsOfficer,
  TgcgRole.logisticsOfficer,
  TgcgRole.monitoringEvaluationOfficer,
  TgcgRole.dataEvidenceOfficer,
  TgcgRole.transportCoordinator,
  TgcgRole.trainingOfficer,
  TgcgRole.ictOfficer,
  TgcgRole.observer,
];

bool _sameScope(GeographicScope a, GeographicScope b) =>
    a.level == b.level &&
    a.stateId == b.stateId &&
    a.senatorialDistrictId == b.senatorialDistrictId &&
    a.lgaId == b.lgaId &&
    a.wardId == b.wardId &&
    a.pollingUnitId == b.pollingUnitId;

String _scopeLabel(GeographicScope scope) => switch (scope.level) {
      GeographyLevel.state => 'Kaduna State',
      GeographyLevel.lga => scope.lgaName ?? scope.label,
      GeographyLevel.ward =>
        '${scope.lgaName ?? 'LGA'} • ${scope.wardName ?? 'Ward'}',
      _ => scope.label,
    };

String _roleLabel(TgcgRole role) {
  final value = role.name.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return value.isEmpty
      ? value
      : '${value[0].toUpperCase()}${value.substring(1)}';
}

String _purposeLabel(BulkCommunicationPurpose purpose) => switch (purpose) {
      BulkCommunicationPurpose.operations => 'Operations',
      BulkCommunicationPurpose.safety => 'Safety',
      BulkCommunicationPurpose.logistics => 'Logistics',
      BulkCommunicationPurpose.technicalSupport => 'Technical Support',
      BulkCommunicationPurpose.incidentResponse => 'Incident Response',
    };

String _channelLabel(BulkCommunicationChannel channel) => switch (channel) {
      BulkCommunicationChannel.push => 'Push',
      BulkCommunicationChannel.sms => 'SMS',
      BulkCommunicationChannel.email => 'Email',
      BulkCommunicationChannel.voice => 'Voice / IVR',
    };

Color _severityColor(int severity) =>
    severity >= 4 ? TgcgColors.danger : TgcgColors.warning;

Color _jobColor(BulkDeliveryJobState state) => switch (state) {
      BulkDeliveryJobState.completed => TgcgColors.success,
      BulkDeliveryJobState.partiallyDelivered => TgcgColors.warning,
      BulkDeliveryJobState.failed => TgcgColors.danger,
      BulkDeliveryJobState.cancelled => TgcgColors.muted,
      _ => TgcgColors.info,
    };

Color _broadcastColor(BroadcastDeliveryState state) => switch (state) {
      BroadcastDeliveryState.sent => TgcgColors.success,
      BroadcastDeliveryState.partiallyDelivered => TgcgColors.warning,
      BroadcastDeliveryState.failed => TgcgColors.danger,
      BroadcastDeliveryState.queued => TgcgColors.info,
    };

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
