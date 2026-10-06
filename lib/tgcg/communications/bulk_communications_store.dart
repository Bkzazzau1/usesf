import 'package:flutter/widgets.dart';

import '../devices/managed_device_store.dart';
import '../domain/local_id.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../governance/governance_store.dart';
import '../membership/membership_store.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

enum BulkCommunicationChannel { push, sms, email, voice }

enum BulkCommunicationPurpose {
  operations,
  safety,
  logistics,
  technicalSupport,
  incidentResponse,
}

enum BulkDeliveryJobState {
  draft,
  queued,
  waitingForProvider,
  processing,
  completed,
  partiallyDelivered,
  failed,
  cancelled,
}

enum ProviderConnectionState { notConfigured, ready, degraded, unavailable }

class CommunicationPreference {
  const CommunicationPreference({
    required this.memberId,
    required this.updatedAt,
    required this.updatedBy,
    required this.source,
    this.smsOptIn = false,
    this.pushOptIn = false,
    this.emailOptIn = false,
    this.voiceOptIn = false,
    this.suppressed = false,
  });

  final String memberId;
  final bool smsOptIn;
  final bool pushOptIn;
  final bool emailOptIn;
  final bool voiceOptIn;
  final bool suppressed;
  final DateTime updatedAt;
  final String updatedBy;
  final String source;

  bool optedIn(BulkCommunicationChannel channel) => switch (channel) {
        BulkCommunicationChannel.sms => smsOptIn,
        BulkCommunicationChannel.push => pushOptIn,
        BulkCommunicationChannel.email => emailOptIn,
        BulkCommunicationChannel.voice => voiceOptIn,
      };
}

class CommunicationContact {
  const CommunicationContact({
    required this.memberId,
    required this.fullName,
    required this.phoneNumber,
    required this.scope,
    required this.preference,
    required this.hasAppDevice,
    this.email,
  });

  final String memberId;
  final String fullName;
  final String phoneNumber;
  final String? email;
  final GeographicScope scope;
  final CommunicationPreference preference;
  final bool hasAppDevice;

  bool eligibleFor(BulkCommunicationChannel channel) {
    if (preference.suppressed || !preference.optedIn(channel)) return false;
    return switch (channel) {
      BulkCommunicationChannel.sms => phoneNumber.trim().isNotEmpty,
      BulkCommunicationChannel.push => hasAppDevice,
      BulkCommunicationChannel.email => email?.trim().isNotEmpty == true,
      BulkCommunicationChannel.voice => phoneNumber.trim().isNotEmpty,
    };
  }
}

class BulkDeliveryProvider {
  const BulkDeliveryProvider({
    required this.id,
    required this.name,
    required this.channel,
    required this.priority,
    required this.state,
    this.supportsDeliveryReceipts = false,
  });

  final String id;
  final String name;
  final BulkCommunicationChannel channel;
  final int priority;
  final ProviderConnectionState state;
  final bool supportsDeliveryReceipts;

  bool get available => state == ProviderConnectionState.ready;
}

class BulkDeliveryJob {
  const BulkDeliveryJob({
    required this.id,
    required this.title,
    required this.body,
    required this.purpose,
    required this.targetScope,
    required this.channels,
    required this.createdBy,
    required this.createdAt,
    required this.state,
    required this.targetContactCount,
    required this.eligibleRecipientCount,
    required this.suppressedCount,
    required this.channelPlan,
    this.targetRoles = const [],
    this.targetMemberIds = const [],
    this.scheduledFor,
    this.sentCount = 0,
    this.deliveredCount = 0,
    this.failedCount = 0,
  });

  final String id;
  final String title;
  final String body;
  final BulkCommunicationPurpose purpose;
  final GeographicScope targetScope;
  final List<BulkCommunicationChannel> channels;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? scheduledFor;
  final BulkDeliveryJobState state;
  final int targetContactCount;
  final int eligibleRecipientCount;
  final int suppressedCount;
  final Map<BulkCommunicationChannel, int> channelPlan;
  final List<TgcgRole> targetRoles;
  final List<String> targetMemberIds;
  final int sentCount;
  final int deliveredCount;
  final int failedCount;
}

class BulkCommunicationsController extends ChangeNotifier {
  BulkCommunicationsController._({
    required MembershipOperationsController membership,
    required ManagedDeviceController devices,
    required GovernanceOperationsController governance,
    OfflinePersistenceController? persistence,
    Map<String, CommunicationPreference> preferences = const {},
    List<BulkDeliveryJob> jobs = const [],
    List<BulkDeliveryProvider> providers = const [],
  })  : _membership = membership,
        _devices = devices,
        _governance = governance,
        _persistence = persistence,
        _preferences = Map.of(preferences),
        _jobs = List.of(jobs),
        _providers = List.of(providers);

  factory BulkCommunicationsController.productionFoundation({
    required MembershipOperationsController membership,
    required ManagedDeviceController devices,
    required GovernanceOperationsController governance,
    OfflinePersistenceController? persistence,
  }) {
    return BulkCommunicationsController._(
      membership: membership,
      devices: devices,
      governance: governance,
      persistence: persistence,
      providers: const [
        BulkDeliveryProvider(
          id: 'PUSH-PRIMARY',
          name: 'Push Notification Provider',
          channel: BulkCommunicationChannel.push,
          priority: 1,
          state: ProviderConnectionState.notConfigured,
          supportsDeliveryReceipts: true,
        ),
        BulkDeliveryProvider(
          id: 'SMS-PRIMARY',
          name: 'Primary SMS Gateway',
          channel: BulkCommunicationChannel.sms,
          priority: 1,
          state: ProviderConnectionState.notConfigured,
          supportsDeliveryReceipts: true,
        ),
        BulkDeliveryProvider(
          id: 'SMS-BACKUP',
          name: 'Backup SMS Gateway',
          channel: BulkCommunicationChannel.sms,
          priority: 2,
          state: ProviderConnectionState.notConfigured,
          supportsDeliveryReceipts: true,
        ),
        BulkDeliveryProvider(
          id: 'EMAIL-PRIMARY',
          name: 'Transactional Email Provider',
          channel: BulkCommunicationChannel.email,
          priority: 1,
          state: ProviderConnectionState.notConfigured,
          supportsDeliveryReceipts: true,
        ),
        BulkDeliveryProvider(
          id: 'VOICE-PRIMARY',
          name: 'Voice / IVR Provider',
          channel: BulkCommunicationChannel.voice,
          priority: 1,
          state: ProviderConnectionState.notConfigured,
          supportsDeliveryReceipts: true,
        ),
      ],
    );
  }

  final MembershipOperationsController _membership;
  final ManagedDeviceController _devices;
  final GovernanceOperationsController _governance;
  final OfflinePersistenceController? _persistence;
  final Map<String, CommunicationPreference> _preferences;
  final List<BulkDeliveryJob> _jobs;
  final List<BulkDeliveryProvider> _providers;

  List<BulkDeliveryProvider> get providers => List.unmodifiable(
        [..._providers]..sort((a, b) {
          final channel = a.channel.index.compareTo(b.channel.index);
          if (channel != 0) return channel;
          return a.priority.compareTo(b.priority);
        }),
      );

  List<BulkDeliveryJob> get jobs => List.unmodifiable(
        [..._jobs]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  Future<void> hydrateFromOffline() async {
    final persistence = _persistence;
    if (persistence == null) return;

    final preferenceRows =
        await persistence.readEntities(entityType: 'communication_preference');
    final jobRows =
        await persistence.readEntities(entityType: 'bulk_delivery_job');
    var changed = false;

    for (final row in preferenceRows) {
      final preference = _preferenceFromPayload(row);
      if (preference == null ||
          _membership.memberById(preference.memberId) == null) {
        continue;
      }
      _preferences[preference.memberId] = preference;
      changed = true;
    }

    for (final row in jobRows) {
      final job = _jobFromPayload(row);
      if (job == null) continue;
      final index = _jobs.indexWhere((item) => item.id == job.id);
      if (index < 0) {
        _jobs.add(job);
      } else {
        _jobs[index] = job;
      }
      changed = true;
    }

    if (changed) {
      _jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }
  }

  List<CommunicationContact> get contacts => _membership.members
      .map(_contactForMember)
      .toList(growable: false);

  List<CommunicationContact> contactsForScope(GeographicScope scope) => contacts
      .where((contact) => TgcgPermissionPolicy.scopeAllows(scope, contact.scope))
      .toList(growable: false);

  List<BulkDeliveryJob> jobsForScope(GeographicScope scope) => jobs
      .where((job) => TgcgPermissionPolicy.scopeAllows(scope, job.targetScope))
      .toList(growable: false);

  CommunicationContact _contactForMember(TgcgMember member) {
    final scope = _membership.registrationScopeForMember(member.id) ??
        GeographicScope.kaduna;
    final hasAppDevice = _devices.deviceForMember(member.id) != null;
    final preference = _preferences[member.id] ??
        CommunicationPreference(
          memberId: member.id,
          updatedAt: member.createdAt,
          updatedBy: 'UNSET',
          source: 'No communication preference recorded',
        );
    return CommunicationContact(
      memberId: member.id,
      fullName: member.fullName,
      phoneNumber: member.phoneNumber,
      email: member.email,
      scope: scope,
      preference: preference,
      hasAppDevice: hasAppDevice,
    );
  }

  int eligibleCount(
    GeographicScope scope,
    BulkCommunicationChannel channel,
  ) =>
      contactsForScope(scope).where((contact) => contact.eligibleFor(channel)).length;

  int suppressedCount(GeographicScope scope) => contactsForScope(scope)
      .where((contact) => contact.preference.suppressed)
      .length;

  Future<bool> recordPreference({
    required String memberId,
    required String actorId,
    required TgcgRole actorRole,
    required GeographicScope actorScope,
    required String source,
    required bool smsOptIn,
    required bool pushOptIn,
    required bool emailOptIn,
    required bool voiceOptIn,
    bool suppressed = false,
  }) async {
    if (!TgcgPermissionPolicy.allows(
      actorRole,
      TgcgCapability.manageMembership,
    )) {
      return false;
    }
    final member = _membership.memberById(memberId);
    if (member == null) return false;
    final memberScope = _membership.registrationScopeForMember(memberId) ??
        GeographicScope.kaduna;
    if (!TgcgPermissionPolicy.scopeAllows(actorScope, memberScope)) return false;
    final normalizedSource = source.trim();
    if (normalizedSource.isEmpty) return false;

    final preference = CommunicationPreference(
      memberId: memberId,
      smsOptIn: smsOptIn,
      pushOptIn: pushOptIn,
      emailOptIn: emailOptIn,
      voiceOptIn: voiceOptIn,
      suppressed: suppressed,
      updatedAt: DateTime.now().toUtc(),
      updatedBy: actorId,
      source: normalizedSource,
    );

    await _persistence?.persistMutation(
      entityType: 'communication_preference',
      entityId: memberId,
      mutationType: SyncMutationType.update,
      payload: _preferencePayload(preference),
      scopeKey: scopeStorageKey(memberScope),
      ownerId: actorId,
    );
    _preferences[memberId] = preference;
    _governance.recordAudit(
      actorId: actorId,
      action: 'communication_preference_updated',
      entityType: 'communication_preference',
      entityId: memberId,
      detail:
          'Communication preference updated. Source: ${preference.source}. Suppressed: ${preference.suppressed}.',
      scope: memberScope,
    );
    notifyListeners();
    return true;
  }

  Future<BulkDeliveryJob?> queueJob({
    required String title,
    required String body,
    required BulkCommunicationPurpose purpose,
    required GeographicScope targetScope,
    required List<BulkCommunicationChannel> channels,
    required String actorId,
    required TgcgRole actorRole,
    required GeographicScope actorScope,
    List<TgcgRole> targetRoles = const [],
    List<String> targetMemberIds = const [],
    DateTime? scheduledFor,
  }) async {
    if (!TgcgPermissionPolicy.allows(actorRole, TgcgCapability.sendBroadcast)) {
      return null;
    }
    if (!TgcgPermissionPolicy.scopeAllows(actorScope, targetScope)) return null;
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    final orderedChannels = channels.toSet().toList(growable: false);
    if (cleanTitle.isEmpty || cleanBody.isEmpty || orderedChannels.isEmpty) {
      return null;
    }

    final roleFilter = targetRoles.toSet();
    final memberFilter = targetMemberIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();

    var targetContacts = contactsForScope(targetScope);
    if (roleFilter.isNotEmpty) {
      targetContacts = targetContacts.where((contact) {
        final roles = _governance.activeRolesForMember(contact.memberId);
        return roles.any((record) => roleFilter.contains(record.role));
      }).toList(growable: false);
    }
    if (memberFilter.isNotEmpty) {
      targetContacts = targetContacts
          .where((contact) => memberFilter.contains(contact.memberId))
          .toList(growable: false);
    }

    final channelPlan = <BulkCommunicationChannel, int>{
      for (final channel in BulkCommunicationChannel.values) channel: 0,
    };
    var eligible = 0;
    var suppressed = 0;
    for (final contact in targetContacts) {
      if (contact.preference.suppressed) {
        suppressed++;
        continue;
      }
      BulkCommunicationChannel? route;
      for (final channel in orderedChannels) {
        if (contact.eligibleFor(channel)) {
          route = channel;
          break;
        }
      }
      if (route != null) {
        eligible++;
        channelPlan[route] = (channelPlan[route] ?? 0) + 1;
      }
    }
    if (eligible == 0) return null;

    final providerReady = orderedChannels.any(
      (channel) => _providers.any(
        (provider) => provider.channel == channel && provider.available,
      ),
    );
    final now = DateTime.now().toUtc();
    final job = BulkDeliveryJob(
      id: newLocalId('BULK', now),
      title: cleanTitle,
      body: cleanBody,
      purpose: purpose,
      targetScope: targetScope,
      channels: orderedChannels,
      createdBy: actorId,
      createdAt: now,
      scheduledFor: scheduledFor,
      state: providerReady
          ? BulkDeliveryJobState.queued
          : BulkDeliveryJobState.waitingForProvider,
      targetContactCount: targetContacts.length,
      eligibleRecipientCount: eligible,
      suppressedCount: suppressed,
      channelPlan: Map.unmodifiable(channelPlan),
      targetRoles: List.unmodifiable(roleFilter),
      targetMemberIds: List.unmodifiable(memberFilter),
    );

    await _persistence?.persistMutation(
      entityType: 'bulk_delivery_job',
      entityId: job.id,
      mutationType: SyncMutationType.create,
      payload: _jobPayload(job),
      scopeKey: scopeStorageKey(targetScope),
      ownerId: actorId,
    );
    _jobs.insert(0, job);
    _governance.recordAudit(
      actorId: actorId,
      action: 'bulk_delivery_job_created',
      entityType: 'bulk_delivery_job',
      entityId: job.id,
      detail:
          '${job.purpose.name} delivery queued for ${job.eligibleRecipientCount} eligible recipients within ${targetScope.label}'
          '${job.targetRoles.isEmpty ? '' : ' • roles: ${job.targetRoles.map((item) => item.name).join(', ')}'}'
          '${job.targetMemberIds.isEmpty ? '' : ' • explicit members: ${job.targetMemberIds.length}'}'
          '.',
      scope: targetScope,
    );
    notifyListeners();
    return job;
  }

  Map<String, Object?> _preferencePayload(CommunicationPreference value) => {
        'member_id': value.memberId,
        'sms_opt_in': value.smsOptIn,
        'push_opt_in': value.pushOptIn,
        'email_opt_in': value.emailOptIn,
        'voice_opt_in': value.voiceOptIn,
        'suppressed': value.suppressed,
        'updated_at': value.updatedAt.toIso8601String(),
        'updated_by': value.updatedBy,
        'source': value.source,
      };

  Map<String, Object?> _jobPayload(BulkDeliveryJob value) => {
        'id': value.id,
        'title': value.title,
        'body': value.body,
        'purpose': value.purpose.name,
        'target_scope': scopeStorageKey(value.targetScope),
        'target_scope_json': geographicScopeToJson(value.targetScope),
        'channels': value.channels.map((item) => item.name).toList(),
        'created_by': value.createdBy,
        'created_at': value.createdAt.toIso8601String(),
        'scheduled_for': value.scheduledFor?.toIso8601String(),
        'state': value.state.name,
        'target_contact_count': value.targetContactCount,
        'eligible_recipient_count': value.eligibleRecipientCount,
        'suppressed_count': value.suppressedCount,
        'channel_plan': {
          for (final entry in value.channelPlan.entries)
            entry.key.name: entry.value,
        },
        'target_roles': value.targetRoles.map((item) => item.name).toList(),
        'target_member_ids': value.targetMemberIds,
      };

  CommunicationPreference? _preferenceFromPayload(
    Map<String, Object?> row,
  ) {
    final memberId = row['member_id']?.toString();
    final updatedAt =
        DateTime.tryParse(row['updated_at']?.toString() ?? '')?.toUtc();
    final updatedBy = row['updated_by']?.toString();
    final source = row['source']?.toString();
    if (memberId == null ||
        updatedAt == null ||
        updatedBy == null ||
        source == null) {
      return null;
    }
    return CommunicationPreference(
      memberId: memberId,
      smsOptIn: row['sms_opt_in'] == true,
      pushOptIn: row['push_opt_in'] == true,
      emailOptIn: row['email_opt_in'] == true,
      voiceOptIn: row['voice_opt_in'] == true,
      suppressed: row['suppressed'] == true,
      updatedAt: updatedAt,
      updatedBy: updatedBy,
      source: source,
    );
  }

  BulkDeliveryJob? _jobFromPayload(Map<String, Object?> row) {
    final id = row['id']?.toString();
    final title = row['title']?.toString();
    final body = row['body']?.toString();
    final purpose = _enumValue(
      BulkCommunicationPurpose.values,
      row['purpose'],
    );
    final targetScope = _scopeFromPayload(
      row['target_scope_json'],
      row['target_scope'],
    );
    final channels = _enumList(
      BulkCommunicationChannel.values,
      row['channels'],
    );
    final createdBy = row['created_by']?.toString();
    final createdAt =
        DateTime.tryParse(row['created_at']?.toString() ?? '')?.toUtc();
    final scheduledRaw = row['scheduled_for']?.toString();
    final scheduledFor = scheduledRaw == null || scheduledRaw.isEmpty
        ? null
        : DateTime.tryParse(scheduledRaw)?.toUtc();
    final state = _enumValue(BulkDeliveryJobState.values, row['state']);
    final targetContactCount = _intValue(row['target_contact_count']);
    final eligibleRecipientCount = _intValue(row['eligible_recipient_count']);
    final suppressedCount = _intValue(row['suppressed_count']);
    final channelPlan = _channelPlanFromPayload(row['channel_plan']);
    final targetRoles = _enumList(TgcgRole.values, row['target_roles']);
    final targetMemberIds = _stringList(row['target_member_ids']);

    if (id == null ||
        title == null ||
        body == null ||
        purpose == null ||
        targetScope == null ||
        channels.isEmpty ||
        createdBy == null ||
        createdAt == null ||
        state == null ||
        targetContactCount == null ||
        eligibleRecipientCount == null ||
        suppressedCount == null ||
        channelPlan == null) {
      return null;
    }

    return BulkDeliveryJob(
      id: id,
      title: title,
      body: body,
      purpose: purpose,
      targetScope: targetScope,
      channels: List.unmodifiable(channels),
      createdBy: createdBy,
      createdAt: createdAt,
      scheduledFor: scheduledFor,
      state: state,
      targetContactCount: targetContactCount,
      eligibleRecipientCount: eligibleRecipientCount,
      suppressedCount: suppressedCount,
      channelPlan: Map.unmodifiable(channelPlan),
      targetRoles: List.unmodifiable(targetRoles),
      targetMemberIds: List.unmodifiable(targetMemberIds),
      sentCount: _intValue(row['sent_count']) ?? 0,
      deliveredCount: _intValue(row['delivered_count']) ?? 0,
      failedCount: _intValue(row['failed_count']) ?? 0,
    );
  }

  GeographicScope? _scopeFromPayload(Object? fullScope, Object? legacyKey) {
    final restored = geographicScopeFromJson(fullScope);
    if (restored != null) return restored;

    final key = legacyKey?.toString();
    if (key == null || key.isEmpty) return null;

    final candidates = <GeographicScope>[
      for (final state in _membership.geography.states) state.scope,
      for (final district in _membership.geography.senatorialDistricts)
        district.scope,
      for (final lga in _membership.geography.lgas) lga.scope,
      ..._wardScopes(),
      for (final unit in _membership.geography.pollingUnits) unit.scope,
    ];
    for (final scope in candidates) {
      if (scopeStorageKey(scope) == key) return scope;
    }
    return null;
  }

  List<GeographicScope> _wardScopes() {
    final wards = <String, GeographicScope>{};
    for (final unit in _membership.geography.pollingUnits) {
      final scope = unit.scope;
      final wardId = scope.wardId;
      if (wardId == null) continue;
      wards.putIfAbsent(
        wardId,
        () => GeographicScope(
          level: GeographyLevel.ward,
          country: scope.country,
          zoneId: scope.zoneId,
          zoneName: scope.zoneName,
          stateId: scope.stateId,
          stateName: scope.stateName,
          senatorialDistrictId: scope.senatorialDistrictId,
          senatorialDistrictName: scope.senatorialDistrictName,
          lgaId: scope.lgaId,
          lgaName: scope.lgaName,
          wardId: wardId,
          wardName: scope.wardName,
        ),
      );
    }
    return wards.values.toList(growable: false);
  }

  static T? _enumValue<T extends Enum>(List<T> values, Object? raw) {
    final name = raw?.toString();
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static List<T> _enumList<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! List) return const [];
    final result = <T>[];
    for (final item in raw) {
      final value = _enumValue(values, item);
      if (value != null) result.add(value);
    }
    return result;
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
  }

  static Map<BulkCommunicationChannel, int>? _channelPlanFromPayload(
    Object? raw,
  ) {
    if (raw is! Map) return null;
    final result = <BulkCommunicationChannel, int>{
      for (final channel in BulkCommunicationChannel.values) channel: 0,
    };
    for (final entry in raw.entries) {
      final channel = _enumValue(
        BulkCommunicationChannel.values,
        entry.key,
      );
      final count = _intValue(entry.value);
      if (channel != null && count != null) result[channel] = count;
    }
    return result;
  }

  static int? _intValue(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }
}

class BulkCommunications
    extends InheritedNotifier<BulkCommunicationsController> {
  const BulkCommunications({
    super.key,
    required BulkCommunicationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static BulkCommunicationsController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value =
          context.dependOnInheritedWidgetOfExactType<BulkCommunications>();
      assert(value != null, 'BulkCommunications is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<BulkCommunications>();
    final value = element?.widget as BulkCommunications?;
    assert(value != null, 'BulkCommunications is missing above this context.');
    return value!.notifier!;
  }
}
