import 'package:flutter/widgets.dart';

import '../domain/models.dart';
import '../geography/geography_registry.dart';

enum MemberPollingUnitLinkSource {
  pvc,
  manual,
  imported,
}

class MemberPollingUnitLink {
  const MemberPollingUnitLink({
    required this.memberId,
    required this.pollingUnitId,
    required this.linkedAt,
    required this.source,
    this.pvcPollingUnitCode,
    this.linkedBy,
  });

  final String memberId;
  final String pollingUnitId;
  final DateTime linkedAt;
  final MemberPollingUnitLinkSource source;
  final String? pvcPollingUnitCode;
  final String? linkedBy;
}

class MembershipOperationsController extends ChangeNotifier {
  MembershipOperationsController._({
    required GeographyRegistry geography,
    required List<TgcgMember> members,
    required List<AccreditedAgent> agents,
    required Map<String, GeographicScope> memberScopes,
    required Map<String, MemberPollingUnitLink> memberPollingUnits,
  })  : _geography = geography,
        _members = members,
        _agents = agents,
        _memberScopes = memberScopes,
        _memberPollingUnits = memberPollingUnits;

  factory MembershipOperationsController.prototypeSeed(
    GeographyRegistry geography,
  ) {
    final now = DateTime.utc(2026, 9, 27, 7, 30);
    final kdPu = geography.pollingUnit('KD-KN-W01-PU001')!.scope;
    final zaPu = geography.pollingUnit('KD-ZA-W01-PU004')!.scope;
    final jmPu = geography.pollingUnit('KD-JM-W03-PU012')!.scope;

    GeographicScope lgaScope(String name) => geography.lgas
        .firstWhere((item) => item.name == name)
        .scope;

    final members = <TgcgMember>[
      TgcgMember(
        id: 'MEM-0001',
        fullName: 'Amina Yusuf',
        phoneNumber: '+2348000000001',
        membershipNumber: 'USESF-000001',
        createdAt: now.subtract(const Duration(days: 45)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0002',
        fullName: 'Samuel Terna',
        phoneNumber: '+2348000000002',
        membershipNumber: 'USESF-000002',
        createdAt: now.subtract(const Duration(days: 38)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0003',
        fullName: 'Chinedu Okafor',
        phoneNumber: '+2348000000003',
        membershipNumber: 'USESF-000003',
        createdAt: now.subtract(const Duration(days: 30)),
        status: RecordStatus.submitted,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0004',
        fullName: 'Bisi Adeyemi',
        phoneNumber: '+2348000000004',
        membershipNumber: 'USESF-000004',
        createdAt: now.subtract(const Duration(days: 21)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0005',
        fullName: 'Hauwa Bello',
        phoneNumber: '+2348000000005',
        membershipNumber: 'USESF-000005',
        createdAt: now.subtract(const Duration(days: 18)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0006',
        fullName: 'Ibrahim Musa',
        phoneNumber: '+2348000000006',
        membershipNumber: 'USESF-000006',
        createdAt: now.subtract(const Duration(days: 17)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0007',
        fullName: 'Ifeanyi Nwosu',
        phoneNumber: '+2348000000007',
        membershipNumber: 'USESF-000007',
        createdAt: now.subtract(const Duration(days: 14)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0008',
        fullName: 'Ebiye George',
        phoneNumber: '+2348000000008',
        membershipNumber: 'USESF-000008',
        createdAt: now.subtract(const Duration(days: 13)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0009',
        fullName: 'Tunde Adebayo',
        phoneNumber: '+2348000000009',
        membershipNumber: 'USESF-000009',
        createdAt: now.subtract(const Duration(days: 11)),
        status: RecordStatus.submitted,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0010',
        fullName: 'Grace Yakubu',
        phoneNumber: '+2348000000010',
        membershipNumber: 'USESF-000010',
        createdAt: now.subtract(const Duration(days: 9)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0011',
        fullName: 'Fatima Adamu',
        phoneNumber: '+2348000000011',
        membershipNumber: 'USESF-000011',
        createdAt: now.subtract(const Duration(days: 7)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0012',
        fullName: 'Ini Etim',
        phoneNumber: '+2348000000012',
        membershipNumber: 'USESF-000012',
        createdAt: now.subtract(const Duration(days: 5)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
    ];

    return MembershipOperationsController._(
      geography: geography,
      members: members,
      memberPollingUnits: {
        'MEM-0001': MemberPollingUnitLink(
          memberId: 'MEM-0001',
          pollingUnitId: kdPu.pollingUnitId!,
          linkedAt: now.subtract(const Duration(days: 20)),
          source: MemberPollingUnitLinkSource.imported,
        ),
        'MEM-0002': MemberPollingUnitLink(
          memberId: 'MEM-0002',
          pollingUnitId: zaPu.pollingUnitId!,
          linkedAt: now.subtract(const Duration(days: 18)),
          source: MemberPollingUnitLinkSource.imported,
        ),
        'MEM-0004': MemberPollingUnitLink(
          memberId: 'MEM-0004',
          pollingUnitId: jmPu.pollingUnitId!,
          linkedAt: now.subtract(const Duration(days: 9)),
          source: MemberPollingUnitLinkSource.imported,
        ),
      },
      memberScopes: {
        'MEM-0001': kdPu,
        'MEM-0002': zaPu,
        'MEM-0003': lgaScope('Chikun'),
        'MEM-0004': jmPu,
        'MEM-0005': lgaScope('Igabi'),
        'MEM-0006': lgaScope('Kaduna South'),
        'MEM-0007': lgaScope('Sabon Gari'),
        'MEM-0008': lgaScope('Kachia'),
        'MEM-0009': lgaScope('Zangon Kataf'),
        'MEM-0010': lgaScope('Giwa'),
        'MEM-0011': lgaScope('Lere'),
        'MEM-0012': lgaScope('Kagarko'),
      },
      agents: [
        AccreditedAgent(
          id: 'ACC-0001',
          memberId: 'MEM-0001',
          agentId: 'AG-KD-001',
          role: TgcgRole.pollingUnitAgent,
          scope: kdPu,
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 20)),
          registeredPhoneNumber: '+2348000000001',
          deviceId: 'DEV-KD-001',
          simFingerprint: 'SIM-KD-001',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0002',
          memberId: 'MEM-0002',
          agentId: 'AG-ZA-014',
          role: TgcgRole.pollingUnitAgent,
          scope: zaPu,
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 18)),
          registeredPhoneNumber: '+2348000000002',
          deviceId: 'DEV-ZA-014',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0003',
          memberId: 'MEM-0004',
          agentId: 'AG-JM-032',
          role: TgcgRole.pollingUnitAgent,
          scope: jmPu,
          status: AccreditationStatus.pending,
          createdAt: now.subtract(const Duration(days: 9)),
          registeredPhoneNumber: '+2348000000004',
          biometricEnrolled: false,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0004',
          memberId: 'MEM-0005',
          agentId: 'AG-IG-021',
          role: TgcgRole.lgaCoordinator,
          scope: lgaScope('Igabi'),
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 8)),
          registeredPhoneNumber: '+2348000000005',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0005',
          memberId: 'MEM-0006',
          agentId: 'AG-KS-015',
          role: TgcgRole.lgaCoordinator,
          scope: lgaScope('Kaduna South'),
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 8)),
          registeredPhoneNumber: '+2348000000006',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0006',
          memberId: 'MEM-0007',
          agentId: 'AG-SG-018',
          role: TgcgRole.lgaCoordinator,
          scope: lgaScope('Sabon Gari'),
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 7)),
          registeredPhoneNumber: '+2348000000007',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0007',
          memberId: 'MEM-0008',
          agentId: 'AG-KC-011',
          role: TgcgRole.lgaCoordinator,
          scope: lgaScope('Kachia'),
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 6)),
          registeredPhoneNumber: '+2348000000008',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0008',
          memberId: 'MEM-0009',
          agentId: 'AG-ZK-008',
          role: TgcgRole.lgaCoordinator,
          scope: lgaScope('Zangon Kataf'),
          status: AccreditationStatus.pending,
          createdAt: now.subtract(const Duration(days: 5)),
          registeredPhoneNumber: '+2348000000009',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0009',
          memberId: 'MEM-0010',
          agentId: 'AG-GW-006',
          role: TgcgRole.lgaCoordinator,
          scope: lgaScope('Giwa'),
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 4)),
          registeredPhoneNumber: '+2348000000010',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
      ],
    );
  }

  final GeographyRegistry _geography;
  final List<TgcgMember> _members;
  final List<AccreditedAgent> _agents;
  final Map<String, GeographicScope> _memberScopes;
  final Map<String, MemberPollingUnitLink> _memberPollingUnits;

  GeographyRegistry get geography => _geography;
  List<TgcgMember> get members => List.unmodifiable(_members);
  List<AccreditedAgent> get agents => List.unmodifiable(_agents);

  TgcgMember? memberById(String id) {
    for (final member in _members) {
      if (member.id == id) return member;
    }
    return null;
  }

  GeographicScope? registrationScopeForMember(String memberId) =>
      _memberScopes[memberId];

  MemberPollingUnitLink? pollingUnitLinkForMember(String memberId) =>
      _memberPollingUnits[memberId];

  CanonicalPollingUnit? homePollingUnitForMember(String memberId) {
    final link = pollingUnitLinkForMember(memberId);
    if (link == null) return null;
    return _geography.pollingUnit(link.pollingUnitId);
  }

  List<TgcgMember> membersForPollingUnit(String pollingUnitId) {
    final unit = _geography.pollingUnit(pollingUnitId);
    if (unit == null) return const [];
    return _members
        .where(
          (member) =>
              _memberPollingUnits[member.id]?.pollingUnitId ==
              unit.scope.pollingUnitId,
        )
        .toList(growable: false);
  }

  int memberCountForPollingUnit(String pollingUnitId) =>
      membersForPollingUnit(pollingUnitId).length;

  int get membersWithHomePollingUnit => _memberPollingUnits.length;

  int get membersWithoutHomePollingUnit =>
      _members.length - membersWithHomePollingUnit;

  List<TgcgMember> membersForScope(GeographicScope scope) => _members
      .where((member) {
        final memberScope = _memberScopes[member.id];
        return memberScope != null &&
            GeographyRegistry.scopeContains(scope, memberScope);
      })
      .toList(growable: false);

  int memberCountForScope(GeographicScope scope) =>
      membersForScope(scope).length;

  List<AccreditedAgent> agentsForScope(GeographicScope scope) =>
      _agents
          .where((agent) => GeographyRegistry.scopeContains(scope, agent.scope))
          .toList(growable: false);

  int agentCountForScope(GeographicScope scope) =>
      agentsForScope(scope).length;

  int assignedPollingUnitsWithin(GeographicScope scope) => agentsForScope(scope)
      .where((agent) =>
          agent.status == AccreditationStatus.approved &&
          agent.role == TgcgRole.pollingUnitAgent &&
          agent.scope.pollingUnitId != null)
      .map((agent) => agent.scope.pollingUnitId!)
      .toSet()
      .length;

  TgcgMember createMember({
    required String fullName,
    required String phoneNumber,
    String? email,
    GeographicScope registrationScope = GeographicScope.kaduna,
    String? homePollingUnitId,
    String? pvcPollingUnitCode,
    String? linkedBy,
  }) {
    CanonicalPollingUnit? homePollingUnit;
    if (homePollingUnitId != null && homePollingUnitId.trim().isNotEmpty) {
      homePollingUnit = _geography.pollingUnit(homePollingUnitId);
      if (homePollingUnit == null) {
        throw ArgumentError(
          'Home polling unit must exist in the canonical registry.',
        );
      }
    }

    final member = TgcgMember(
      id: 'MEM-${(_members.length + 1).toString().padLeft(4, '0')}',
      fullName: fullName.trim(),
      phoneNumber: phoneNumber.trim(),
      email: email?.trim().isEmpty == true ? null : email?.trim(),
      membershipNumber:
          'USESF-${(_members.length + 1).toString().padLeft(6, '0')}',
      createdAt: DateTime.now().toUtc(),
      status: RecordStatus.submitted,
      origin: RecordOrigin.localEntry,
    );
    _members.insert(0, member);
    _memberScopes[member.id] =
        homePollingUnit?.scope ?? registrationScope;
    if (homePollingUnit != null) {
      _memberPollingUnits[member.id] = MemberPollingUnitLink(
        memberId: member.id,
        pollingUnitId: homePollingUnit.scope.pollingUnitId!,
        linkedAt: DateTime.now().toUtc(),
        source: pvcPollingUnitCode?.trim().isNotEmpty == true
            ? MemberPollingUnitLinkSource.pvc
            : MemberPollingUnitLinkSource.manual,
        pvcPollingUnitCode: pvcPollingUnitCode?.trim().isEmpty == true
            ? null
            : pvcPollingUnitCode?.trim(),
        linkedBy: linkedBy?.trim().isEmpty == true ? null : linkedBy?.trim(),
      );
    }
    notifyListeners();
    return member;
  }

  MemberPollingUnitLink linkMemberToPollingUnit({
    required String memberId,
    required String pollingUnitId,
    MemberPollingUnitLinkSource source = MemberPollingUnitLinkSource.manual,
    String? pvcPollingUnitCode,
    String? linkedBy,
  }) {
    if (memberById(memberId) == null) {
      throw ArgumentError('Unknown member: $memberId');
    }
    final unit = _geography.pollingUnit(pollingUnitId);
    if (unit == null) {
      throw ArgumentError(
        'Polling-unit link must use canonical geography.',
      );
    }
    final link = MemberPollingUnitLink(
      memberId: memberId,
      pollingUnitId: unit.scope.pollingUnitId!,
      linkedAt: DateTime.now().toUtc(),
      source: source,
      pvcPollingUnitCode: pvcPollingUnitCode?.trim().isEmpty == true
          ? null
          : pvcPollingUnitCode?.trim(),
      linkedBy: linkedBy?.trim().isEmpty == true ? null : linkedBy?.trim(),
    );
    _memberPollingUnits[memberId] = link;
    _memberScopes[memberId] = unit.scope;
    notifyListeners();
    return link;
  }

  CanonicalPollingUnit verifyPollingUnitCoordinate({
    required String pollingUnitId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required String verifiedBy,
    DateTime? verifiedAt,
  }) {
    final updated = _geography.verifyPollingUnitCoordinate(
      pollingUnitId: pollingUnitId,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      verifiedBy: verifiedBy,
      verifiedAt: verifiedAt,
    );
    notifyListeners();
    return updated;
  }

  CanonicalPollingUnit setPollingUnitReferenceCoordinate({
    required String pollingUnitId,
    required double latitude,
    required double longitude,
    required String source,
    String? officialCode,
  }) {
    final updated = _geography.setPollingUnitReferenceCoordinate(
      pollingUnitId: pollingUnitId,
      latitude: latitude,
      longitude: longitude,
      source: source,
      officialCode: officialCode,
    );
    notifyListeners();
    return updated;
  }

  AccreditedAgent accredit({
    required String memberId,
    required TgcgRole role,
    required GeographicScope scope,
    String? phoneNumber,
    String? deviceId,
    String? simFingerprint,
  }) {
    if (scope.level == GeographyLevel.pollingUnit &&
        _geography.pollingUnit(scope.pollingUnitId ?? '') == null) {
      throw ArgumentError(
        'Polling-unit assignment must use canonical geography.',
      );
    }

    final agent = AccreditedAgent(
      id: 'ACC-${(_agents.length + 1).toString().padLeft(4, '0')}',
      memberId: memberId,
      agentId: 'AG-${(_agents.length + 1).toString().padLeft(5, '0')}',
      role: role,
      scope: scope,
      status: AccreditationStatus.pending,
      createdAt: DateTime.now().toUtc(),
      registeredPhoneNumber: phoneNumber?.trim(),
      deviceId: deviceId?.trim().isEmpty == true ? null : deviceId?.trim(),
      simFingerprint:
          simFingerprint?.trim().isEmpty == true ? null : simFingerprint?.trim(),
      origin: RecordOrigin.localEntry,
    );
    _agents.insert(0, agent);
    notifyListeners();
    return agent;
  }

  void updateAccreditationStatus(String id, AccreditationStatus status) {
    final index = _agents.indexWhere((agent) => agent.id == id);
    if (index < 0) return;
    _agents[index] = _copyAgent(_agents[index], status: status);
    notifyListeners();
  }

  void updateReadiness(
    String id, {
    bool? trainingCompleted,
    bool? biometricEnrolled,
    String? deviceId,
    String? simFingerprint,
  }) {
    final index = _agents.indexWhere((agent) => agent.id == id);
    if (index < 0) return;
    final current = _agents[index];
    _agents[index] = AccreditedAgent(
      id: current.id,
      memberId: current.memberId,
      agentId: current.agentId,
      role: current.role,
      scope: current.scope,
      status: current.status,
      createdAt: current.createdAt,
      registeredPhoneNumber: current.registeredPhoneNumber,
      deviceId: deviceId ?? current.deviceId,
      simFingerprint: simFingerprint ?? current.simFingerprint,
      biometricEnrolled: biometricEnrolled ?? current.biometricEnrolled,
      trainingCompleted: trainingCompleted ?? current.trainingCompleted,
      origin: current.origin,
    );
    notifyListeners();
  }

  static AccreditedAgent _copyAgent(
    AccreditedAgent current, {
    AccreditationStatus? status,
  }) => AccreditedAgent(
        id: current.id,
        memberId: current.memberId,
        agentId: current.agentId,
        role: current.role,
        scope: current.scope,
        status: status ?? current.status,
        createdAt: current.createdAt,
        registeredPhoneNumber: current.registeredPhoneNumber,
        deviceId: current.deviceId,
        simFingerprint: current.simFingerprint,
        biometricEnrolled: current.biometricEnrolled,
        trainingCompleted: current.trainingCompleted,
        origin: current.origin,
      );
}

class MembershipOperations extends InheritedNotifier<MembershipOperationsController> {
  const MembershipOperations({
    super.key,
    required MembershipOperationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static MembershipOperationsController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value =
          context.dependOnInheritedWidgetOfExactType<MembershipOperations>();
      assert(value != null, 'MembershipOperations is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<MembershipOperations>();
    final value = element?.widget as MembershipOperations?;
    assert(value != null, 'MembershipOperations is missing above this context.');
    return value!.notifier!;
  }
}
