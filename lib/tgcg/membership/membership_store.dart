import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/models.dart';
import '../geography/geography_registry.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

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

class _MemberPinCredential {
  const _MemberPinCredential({
    required this.salt,
    required this.hash,
  });

  final String salt;
  final String hash;
}

class MembershipOperationsController extends ChangeNotifier {
  MembershipOperationsController._({
    required GeographyRegistry geography,
    required List<TgcgMember> members,
    required List<AccreditedAgent> agents,
    required Map<String, GeographicScope> memberScopes,
    required Map<String, MemberPollingUnitLink> memberPollingUnits,
    required OfflinePersistenceController persistence,
  })  : _geography = geography,
        _members = members,
        _agents = agents,
        _memberScopes = memberScopes,
        _memberPollingUnits = memberPollingUnits,
        _persistence = persistence;

  factory MembershipOperationsController.prototypeSeed(
    GeographyRegistry geography, {
    OfflinePersistenceController? persistence,
  }) {
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
      persistence: persistence ?? OfflinePersistenceController(),
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
  final OfflinePersistenceController _persistence;
  final Map<String, String> _memberPvcCredentialHashes = {};
  final Map<String, _MemberPinCredential> _memberPinCredentials = {};
  final Map<String, _MemberPinCredential> _memberPasswordCredentials = {};
  final FlutterSecureStorage _credentialStorage =
      const FlutterSecureStorage();

  GeographyRegistry get geography => _geography;
  List<TgcgMember> get members => List.unmodifiable(_members);
  List<AccreditedAgent> get agents => List.unmodifiable(_agents);

  Future<void> hydrateFromOffline() async {
    final memberRows = await _persistence.readEntities(
      entityType: 'usesf_member',
    );
    final coordinateRows = await _persistence.readEntities(
      entityType: 'polling_unit_coordinate',
    );
    final agentRows = await _persistence.readEntities(
      entityType: 'accredited_agent',
    );

    var changed = false;

    for (final row in memberRows) {
      final id = row['id']?.toString();
      final fullName = row['fullName']?.toString();
      final phoneNumber = row['phoneNumber']?.toString() ?? '';
      final createdAt =
          DateTime.tryParse(row['createdAt']?.toString() ?? '')?.toUtc();
      final status = _recordStatus(row['status']);
      if (id == null ||
          fullName == null ||
          createdAt == null ||
          status == null) {
        continue;
      }

      final origin = _recordOrigin(row['origin']) ?? RecordOrigin.localEntry;
      final member = TgcgMember(
        id: id,
        fullName: fullName,
        phoneNumber: phoneNumber,
        email: _nullableText(row['email']),
        emailVerified: row['emailVerified'] == true,
        membershipNumber: _nullableText(row['membershipNumber']),
        pvcVin: _nullableText(row['pvcVin']),
        selfieReference: _nullableText(row['selfieReference']),
        accountStatus: _memberAccountStatus(row['accountStatus']) ??
            MemberAccountStatus.active,
        identityReview: _memberIdentityReview(row['identityReview']) ??
            MemberIdentityReview.pending,
        createdAt: createdAt,
        status: status,
        origin: origin,
      );
      final scope =
          geographicScopeFromJson(row['registrationScope']) ??
              GeographicScope.kaduna;

      final index = _members.indexWhere((item) => item.id == id);
      if (index < 0) {
        _members.add(member);
      } else {
        _members[index] = member;
      }
      _memberScopes[id] = scope;

      final homeRaw = row['homePollingUnit'];
      if (homeRaw is Map) {
        final home = homeRaw.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final pollingUnitId = home['pollingUnitId']?.toString();
        final linkedAt =
            DateTime.tryParse(home['linkedAt']?.toString() ?? '')?.toUtc();
        final source = _linkSource(home['source']);
        if (pollingUnitId != null &&
            linkedAt != null &&
            source != null &&
            _geography.pollingUnit(pollingUnitId) != null) {
          _memberPollingUnits[id] = MemberPollingUnitLink(
            memberId: id,
            pollingUnitId: pollingUnitId,
            linkedAt: linkedAt,
            source: source,
            pvcPollingUnitCode:
                _nullableText(home['pvcPollingUnitCode']),
            linkedBy: _nullableText(home['linkedBy']),
          );
        }
      }
      changed = true;
    }

    for (final row in agentRows) {
      final id = row['id']?.toString();
      final memberId = row['memberId']?.toString();
      final agentId = row['agentId']?.toString();
      final role = _role(row['role']);
      final scope = geographicScopeFromJson(row['scope']);
      final status = _accreditationStatus(row['status']);
      final createdAt =
          DateTime.tryParse(row['createdAt']?.toString() ?? '')?.toUtc();
      if (id == null ||
          memberId == null ||
          agentId == null ||
          role == null ||
          scope == null ||
          status == null ||
          createdAt == null) {
        continue;
      }
      if (memberById(memberId) == null) continue;

      final restored = AccreditedAgent(
        id: id,
        memberId: memberId,
        agentId: agentId,
        role: role,
        scope: scope,
        status: status,
        createdAt: createdAt,
        registeredPhoneNumber:
            _nullableText(row['registeredPhoneNumber']),
        deviceId: _nullableText(row['deviceId']),
        simFingerprint: _nullableText(row['simFingerprint']),
        biometricEnrolled: row['biometricEnrolled'] == true,
        trainingCompleted: row['trainingCompleted'] == true,
        origin: _recordOrigin(row['origin']) ?? RecordOrigin.localEntry,
      );
      final index = _agents.indexWhere((item) => item.id == id);
      if (index < 0) {
        _agents.add(restored);
      } else {
        _agents[index] = restored;
      }
      changed = true;
    }

    for (final row in coordinateRows) {
      final pollingUnitId = row['pollingUnitId']?.toString();
      if (pollingUnitId == null ||
          _geography.pollingUnit(pollingUnitId) == null) {
        continue;
      }

      final referenceLatitude = _number(row['referenceLatitude']);
      final referenceLongitude = _number(row['referenceLongitude']);
      final referenceSource = _nullableText(row['referenceSource']);
      if (referenceLatitude != null &&
          referenceLongitude != null &&
          referenceSource != null) {
        _geography.setPollingUnitReferenceCoordinate(
          pollingUnitId: pollingUnitId,
          latitude: referenceLatitude,
          longitude: referenceLongitude,
          source: referenceSource,
          officialCode: _nullableText(row['officialCode']),
        );
      }

      final verifiedLatitude = _number(row['verifiedLatitude']);
      final verifiedLongitude = _number(row['verifiedLongitude']);
      final accuracy = _number(row['verificationAccuracyMeters']);
      final verifiedBy = _nullableText(row['verifiedBy']);
      final verifiedAt =
          DateTime.tryParse(row['verifiedAt']?.toString() ?? '')?.toUtc();
      if (verifiedLatitude != null &&
          verifiedLongitude != null &&
          accuracy != null &&
          verifiedBy != null &&
          verifiedAt != null) {
        _geography.verifyPollingUnitCoordinate(
          pollingUnitId: pollingUnitId,
          latitude: verifiedLatitude,
          longitude: verifiedLongitude,
          accuracyMeters: accuracy,
          verifiedBy: verifiedBy,
          verifiedAt: verifiedAt,
        );
      }
      changed = true;
    }

    if (changed) {
      _members.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }
  }

  TgcgMember? memberById(String id) {
    for (final member in _members) {
      if (member.id == id) return member;
    }
    return null;
  }

  TgcgMember? memberByPhone(String phoneNumber) {
    final target = _normalizePhone(phoneNumber);
    if (target.isEmpty) return null;
    for (final member in _members) {
      if (_normalizePhone(member.phoneNumber) == target) return member;
    }
    return null;
  }

  TgcgMember? memberByEmail(String email) {
    final target = email.trim().toLowerCase();
    if (target.isEmpty) return null;
    for (final member in _members) {
      if ((member.email ?? '').trim().toLowerCase() == target) return member;
    }
    return null;
  }

  Future<TgcgMember?> memberByPvcVin(String pvcVin) async {
    final target = _normalizePvcCredential(pvcVin);
    if (target.isEmpty) return null;
    for (final member in _members) {
      final stored = member.pvcVin;
      if (stored != null && _normalizePvcCredential(stored) == target) {
        return member;
      }
    }
    return memberByPvcCredential(pvcVin);
  }

  AccreditedAgent? approvedAccreditationForMember(String memberId) {
    for (final agent in _agents) {
      if (agent.memberId == memberId &&
          agent.status == AccreditationStatus.approved) {
        return agent;
      }
    }
    return null;
  }

  bool hasMemberPin(String memberId) =>
      _memberPinCredentials.containsKey(memberId);

  bool hasPvcCredential(String memberId) =>
      _memberPvcCredentialHashes.containsKey(memberId);

  Future<bool> hasMemberPinCredential(String memberId) async {
    if (_memberPinCredentials.containsKey(memberId)) return true;
    final stored = await _credentialStorage.read(
      key: _pinCredentialKey(memberId),
    );
    return stored != null && stored.trim().isNotEmpty;
  }

  Future<bool> hasMemberPasswordCredential(String memberId) async {
    if (_memberPasswordCredentials.containsKey(memberId)) return true;
    final stored = await _credentialStorage.read(
      key: _passwordCredentialKey(memberId),
    );
    if (stored != null && stored.trim().isNotEmpty) return true;

    // Development migration: existing 6-digit member PIN credentials remain
    // usable until the member sets a normal password.
    return hasMemberPinCredential(memberId);
  }

  Future<bool> hasPersistedPvcCredential(String memberId) async {
    if (_memberPvcCredentialHashes.containsKey(memberId)) return true;
    final fingerprint = await _credentialStorage.read(
      key: _pvcMemberFingerprintKey(memberId),
    );
    return fingerprint != null && fingerprint.trim().isNotEmpty;
  }

  Future<void> setPvcCredential({
    required String memberId,
    required String voterId,
  }) async {
    if (memberById(memberId) == null) {
      throw ArgumentError('Unknown member: $memberId');
    }
    final normalized = _normalizePvcCredential(voterId);
    if (normalized.length < 6) {
      throw ArgumentError('PVC/Voter ID is not valid enough to register.');
    }

    final fingerprint = await _sha256Base64(normalized);
    final previous = _memberPvcCredentialHashes[memberId] ??
        await _credentialStorage.read(
          key: _pvcMemberFingerprintKey(memberId),
        );
    if (previous != null &&
        previous.isNotEmpty &&
        !_constantTimeEquals(previous, fingerprint)) {
      await _credentialStorage.delete(
        key: _pvcIndexKey(previous),
      );
    }

    _memberPvcCredentialHashes[memberId] = fingerprint;
    await _credentialStorage.write(
      key: _pvcMemberFingerprintKey(memberId),
      value: fingerprint,
    );
    await _credentialStorage.write(
      key: _pvcIndexKey(fingerprint),
      value: memberId,
    );
    notifyListeners();
  }

  Future<TgcgMember?> memberByPvcCredential(String voterId) async {
    final normalized = _normalizePvcCredential(voterId);
    if (normalized.length < 6) return null;
    final fingerprint = await _sha256Base64(normalized);

    for (final entry in _memberPvcCredentialHashes.entries) {
      if (_constantTimeEquals(entry.value, fingerprint)) {
        return memberById(entry.key);
      }
    }

    final memberId = await _credentialStorage.read(
      key: _pvcIndexKey(fingerprint),
    );
    if (memberId == null || memberId.isEmpty) return null;
    final member = memberById(memberId);
    if (member != null) {
      _memberPvcCredentialHashes[member.id] = fingerprint;
    }
    return member;
  }

  Future<void> setMemberPin({
    required String memberId,
    required String pin,
  }) async {
    if (memberById(memberId) == null) {
      throw ArgumentError('Unknown member: $memberId');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('Member PIN must contain exactly 6 digits.');
    }
    final random = Random.secure();
    final saltBytes = List<int>.generate(
      16,
      (_) => random.nextInt(256),
      growable: false,
    );
    final hash = await _derivePin(pin, saltBytes);
    final credential = _MemberPinCredential(
      salt: base64UrlEncode(saltBytes),
      hash: base64UrlEncode(hash),
    );
    _memberPinCredentials[memberId] = credential;
    await _credentialStorage.write(
      key: _pinCredentialKey(memberId),
      value: jsonEncode({
        'salt': credential.salt,
        'hash': credential.hash,
      }),
    );
    notifyListeners();
  }


  Future<void> setMemberPassword({
    required String memberId,
    required String password,
  }) async {
    if (memberById(memberId) == null) {
      throw ArgumentError('Unknown member: $memberId');
    }
    if (password.length < 8) {
      throw ArgumentError('Password must contain at least 8 characters.');
    }
    final random = Random.secure();
    final saltBytes = List<int>.generate(
      16,
      (_) => random.nextInt(256),
      growable: false,
    );
    final hash = await _derivePin(password, saltBytes);
    final credential = _MemberPinCredential(
      salt: base64UrlEncode(saltBytes),
      hash: base64UrlEncode(hash),
    );
    _memberPasswordCredentials[memberId] = credential;
    await _credentialStorage.write(
      key: _passwordCredentialKey(memberId),
      value: jsonEncode({
        'salt': credential.salt,
        'hash': credential.hash,
      }),
    );
    notifyListeners();
  }

  Future<bool> verifyMemberPassword({
    required String memberId,
    required String password,
  }) async {
    if (password.isEmpty) return false;

    var credential = _memberPasswordCredentials[memberId];
    if (credential == null) {
      final stored = await _credentialStorage.read(
        key: _passwordCredentialKey(memberId),
      );
      if (stored != null && stored.isNotEmpty) {
        try {
          final decoded = jsonDecode(stored);
          if (decoded is Map &&
              decoded['salt'] is String &&
              decoded['hash'] is String) {
            credential = _MemberPinCredential(
              salt: decoded['salt'] as String,
              hash: decoded['hash'] as String,
            );
            _memberPasswordCredentials[memberId] = credential;
          }
        } catch (_) {
          return false;
        }
      }
    }

    if (credential != null) {
      final salt = base64Url.decode(credential.salt);
      final actual = base64UrlEncode(await _derivePin(password, salt));
      return _constantTimeEquals(credential.hash, actual);
    }

    // Development migration path for accounts created before password login.
    if (RegExp(r'^\d{6}$').hasMatch(password)) {
      return verifyMemberPin(memberId: memberId, pin: password);
    }
    return false;
  }

  Future<void> clearLocalCredentials() async {
    for (final member in _members) {
      final fingerprint = _memberPvcCredentialHashes[member.id] ??
          await _credentialStorage.read(
            key: _pvcMemberFingerprintKey(member.id),
          );
      if (fingerprint != null && fingerprint.isNotEmpty) {
        await _credentialStorage.delete(
          key: _pvcIndexKey(fingerprint),
        );
      }
      await _credentialStorage.delete(
        key: _pvcMemberFingerprintKey(member.id),
      );
      await _credentialStorage.delete(
        key: _pinCredentialKey(member.id),
      );
      await _credentialStorage.delete(
        key: _passwordCredentialKey(member.id),
      );
    }
    _memberPvcCredentialHashes.clear();
    _memberPinCredentials.clear();
    _memberPasswordCredentials.clear();
  }

  Future<bool> verifyMemberPin({
    required String memberId,
    required String pin,
  }) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) return false;

    var credential = _memberPinCredentials[memberId];
    if (credential == null) {
      final stored = await _credentialStorage.read(
        key: _pinCredentialKey(memberId),
      );
      if (stored != null && stored.isNotEmpty) {
        try {
          final decoded = jsonDecode(stored);
          if (decoded is Map &&
              decoded['salt'] is String &&
              decoded['hash'] is String) {
            credential = _MemberPinCredential(
              salt: decoded['salt'] as String,
              hash: decoded['hash'] as String,
            );
            _memberPinCredentials[memberId] = credential;
          }
        } catch (_) {
          return false;
        }
      }
    }
    if (credential == null) return false;

    final salt = base64Url.decode(credential.salt);
    final actual = base64UrlEncode(await _derivePin(pin, salt));
    return _constantTimeEquals(credential.hash, actual);
  }

  Future<TgcgMember> updateMemberContact({
    required String memberId,
    String? phoneNumber,
    String? email,
  }) async {
    final index = _members.indexWhere((item) => item.id == memberId);
    if (index < 0) throw ArgumentError('Unknown member: $memberId');
    final current = _members[index];

    final requestedEmail = email?.trim();
    if (current.emailVerified &&
        requestedEmail != null &&
        requestedEmail.toLowerCase() !=
            (current.email ?? '').trim().toLowerCase()) {
      throw StateError(
        'A verified email can only be changed by the backend System Admin.',
      );
    }

    final updated = _copyMember(
      current,
      phoneNumber: phoneNumber?.trim() ?? current.phoneNumber,
      email: requestedEmail == null || requestedEmail.isEmpty
          ? current.email
          : requestedEmail,
    );
    final scope = _memberScopes[memberId] ?? GeographicScope.kaduna;
    await _persistMemberState(
      updated,
      scope,
      _memberPollingUnits[memberId],
    );
    _members[index] = updated;
    notifyListeners();
    return updated;
  }

  Future<TgcgMember> markEmailVerified(String memberId) async {
    final index = _members.indexWhere((item) => item.id == memberId);
    if (index < 0) throw ArgumentError('Unknown member: $memberId');
    final current = _members[index];
    if ((current.email ?? '').trim().isEmpty) {
      throw StateError('Add an email address before verification.');
    }
    final updated = _copyMember(current, emailVerified: true);
    final scope = _memberScopes[memberId] ?? GeographicScope.kaduna;
    await _persistMemberState(
      updated,
      scope,
      _memberPollingUnits[memberId],
    );
    _members[index] = updated;
    notifyListeners();
    return updated;
  }

  /// Backend identity-review operation. A suspicious finding blocks the
  /// account immediately; a later verified finding reactivates the same member.
  Future<TgcgMember> setIdentityReview({
    required String memberId,
    required MemberIdentityReview review,
  }) async {
    final index = _members.indexWhere((item) => item.id == memberId);
    if (index < 0) throw ArgumentError('Unknown member: $memberId');
    final current = _members[index];
    final updated = _copyMember(
      current,
      identityReview: review,
      accountStatus: review == MemberIdentityReview.suspicious
          ? MemberAccountStatus.blocked
          : MemberAccountStatus.active,
    );
    final scope = _memberScopes[memberId] ?? GeographicScope.kaduna;
    await _persistMemberState(
      updated,
      scope,
      _memberPollingUnits[memberId],
    );
    _members[index] = updated;
    notifyListeners();
    return updated;
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

  Future<TgcgMember> createMember({
    required String fullName,
    String phoneNumber = '',
    String? email,
    bool emailVerified = false,
    String? pvcVin,
    String? selfieReference,
    GeographicScope registrationScope = GeographicScope.kaduna,
    String? homePollingUnitId,
    String? pvcPollingUnitCode,
    String? linkedBy,
  }) async {
    final normalizedVin = _normalizePvcCredential(pvcVin ?? '');
    if (normalizedVin.isNotEmpty) {
      final existing = await memberByPvcVin(normalizedVin);
      if (existing != null) {
        throw StateError('This PVC/VIN is already registered to a USESF member.');
      }
    }

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
      emailVerified: emailVerified,
      membershipNumber:
          'USESF-${(_members.length + 1).toString().padLeft(6, '0')}',
      pvcVin: normalizedVin.isEmpty ? null : normalizedVin,
      selfieReference:
          selfieReference?.trim().isEmpty == true ? null : selfieReference?.trim(),
      accountStatus: MemberAccountStatus.active,
      identityReview: MemberIdentityReview.pending,
      createdAt: DateTime.now().toUtc(),
      status: RecordStatus.submitted,
      origin: RecordOrigin.localEntry,
    );
    final scope = homePollingUnit?.scope ?? registrationScope;
    final homeLink = homePollingUnit == null
        ? null
        : MemberPollingUnitLink(
            memberId: member.id,
            pollingUnitId: homePollingUnit.scope.pollingUnitId!,
            linkedAt: DateTime.now().toUtc(),
            source: pvcPollingUnitCode?.trim().isNotEmpty == true
                ? MemberPollingUnitLinkSource.pvc
                : MemberPollingUnitLinkSource.manual,
            pvcPollingUnitCode: pvcPollingUnitCode?.trim().isEmpty == true
                ? null
                : pvcPollingUnitCode?.trim(),
            linkedBy:
                linkedBy?.trim().isEmpty == true ? null : linkedBy?.trim(),
          );

    await _persistMemberState(member, scope, homeLink);

    _members.insert(0, member);
    _memberScopes[member.id] = scope;
    if (homeLink != null) {
      _memberPollingUnits[member.id] = homeLink;
    }
    notifyListeners();
    return member;
  }

  Future<MemberPollingUnitLink> linkMemberToPollingUnit({
    required String memberId,
    required String pollingUnitId,
    MemberPollingUnitLinkSource source = MemberPollingUnitLinkSource.manual,
    String? pvcPollingUnitCode,
    String? linkedBy,
  }) async {
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
    final member = memberById(memberId)!;
    await _persistMemberState(member, unit.scope, link);
    _memberPollingUnits[memberId] = link;
    _memberScopes[memberId] = unit.scope;
    notifyListeners();
    return link;
  }

  Future<CanonicalPollingUnit> verifyPollingUnitCoordinate({
    required String pollingUnitId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required String verifiedBy,
    DateTime? verifiedAt,
  }) async {
    final updated = _geography.verifyPollingUnitCoordinate(
      pollingUnitId: pollingUnitId,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      verifiedBy: verifiedBy,
      verifiedAt: verifiedAt,
    );
    await _persistPollingUnitCoordinate(updated);
    notifyListeners();
    return updated;
  }

  Future<CanonicalPollingUnit> setPollingUnitReferenceCoordinate({
    required String pollingUnitId,
    required double latitude,
    required double longitude,
    required String source,
    String? officialCode,
  }) async {
    final updated = _geography.setPollingUnitReferenceCoordinate(
      pollingUnitId: pollingUnitId,
      latitude: latitude,
      longitude: longitude,
      source: source,
      officialCode: officialCode,
    );
    await _persistPollingUnitCoordinate(updated);
    notifyListeners();
    return updated;
  }

  Future<AccreditedAgent> accredit({
    required String memberId,
    required TgcgRole role,
    required GeographicScope scope,
    String? phoneNumber,
    String? deviceId,
    String? simFingerprint,
  }) async {
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
    await _persistAgent(agent);
    _agents.insert(0, agent);
    notifyListeners();
    return agent;
  }

  Future<void> updateAccreditationStatus(
    String id,
    AccreditationStatus status,
  ) async {
    final index = _agents.indexWhere((agent) => agent.id == id);
    if (index < 0) return;
    final updated = _copyAgent(_agents[index], status: status);
    await _persistAgent(updated);
    _agents[index] = updated;
    notifyListeners();
  }

  Future<void> updateReadiness(
    String id, {
    bool? trainingCompleted,
    bool? biometricEnrolled,
    String? deviceId,
    String? simFingerprint,
  }) async {
    final index = _agents.indexWhere((agent) => agent.id == id);
    if (index < 0) return;
    final current = _agents[index];
    final updated = AccreditedAgent(
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
    await _persistAgent(updated);
    _agents[index] = updated;
    notifyListeners();
  }

  Future<void> _persistAgent(AccreditedAgent agent) =>
      _persistence.persistMutation(
        entityType: 'accredited_agent',
        entityId: agent.id,
        mutationType: SyncMutationType.upsert,
        scopeKey: scopeStorageKey(agent.scope),
        ownerId: agent.memberId,
        payload: {
          'id': agent.id,
          'memberId': agent.memberId,
          'agentId': agent.agentId,
          'role': agent.role.name,
          'scope': geographicScopeToJson(agent.scope),
          'status': agent.status.name,
          'createdAt': agent.createdAt.toIso8601String(),
          'registeredPhoneNumber': agent.registeredPhoneNumber,
          'deviceId': agent.deviceId,
          'simFingerprint': agent.simFingerprint,
          'biometricEnrolled': agent.biometricEnrolled,
          'trainingCompleted': agent.trainingCompleted,
          'origin': agent.origin.name,
        },
      );

  Future<void> _persistMemberState(
    TgcgMember member,
    GeographicScope scope,
    MemberPollingUnitLink? homeLink,
  ) =>
      _persistence.persistMutation(
        entityType: 'usesf_member',
        entityId: member.id,
        mutationType: SyncMutationType.upsert,
        scopeKey: scopeStorageKey(scope),
        ownerId: member.id,
        payload: {
          'id': member.id,
          'fullName': member.fullName,
          'phoneNumber': member.phoneNumber,
          'email': member.email,
          'emailVerified': member.emailVerified,
          'membershipNumber': member.membershipNumber,
          'pvcVin': member.pvcVin,
          'selfieReference': member.selfieReference,
          'accountStatus': member.accountStatus.name,
          'identityReview': member.identityReview.name,
          'createdAt': member.createdAt.toIso8601String(),
          'status': member.status.name,
          'origin': member.origin.name,
          'registrationScope': geographicScopeToJson(scope),
          'homePollingUnit': homeLink == null
              ? null
              : {
                  'pollingUnitId': homeLink.pollingUnitId,
                  'linkedAt': homeLink.linkedAt.toIso8601String(),
                  'source': homeLink.source.name,
                  'pvcPollingUnitCode': homeLink.pvcPollingUnitCode,
                  'linkedBy': homeLink.linkedBy,
                },
        },
      );

  Future<void> _persistPollingUnitCoordinate(
    CanonicalPollingUnit unit,
  ) =>
      _persistence.persistMutation(
        entityType: 'polling_unit_coordinate',
        entityId: unit.code,
        mutationType: SyncMutationType.upsert,
        scopeKey: scopeStorageKey(unit.scope),
        payload: {
          'pollingUnitId': unit.code,
          'officialCode': unit.officialCode,
          'referenceLatitude': unit.referenceLatitude,
          'referenceLongitude': unit.referenceLongitude,
          'referenceSource': unit.referenceSource,
          'verifiedLatitude': unit.verifiedLatitude,
          'verifiedLongitude': unit.verifiedLongitude,
          'verificationAccuracyMeters': unit.verificationAccuracyMeters,
          'verifiedBy': unit.verifiedBy,
          'verifiedAt': unit.verifiedAt?.toIso8601String(),
          'coordinateStatus': unit.coordinateStatus.name,
          'geofenceRadiusMeters': unit.geofenceRadiusMeters,
        },
      );

  static TgcgMember _copyMember(
    TgcgMember current, {
    String? phoneNumber,
    String? email,
    bool? emailVerified,
    String? pvcVin,
    String? selfieReference,
    MemberAccountStatus? accountStatus,
    MemberIdentityReview? identityReview,
    RecordStatus? status,
  }) =>
      TgcgMember(
        id: current.id,
        fullName: current.fullName,
        phoneNumber: phoneNumber ?? current.phoneNumber,
        email: email ?? current.email,
        emailVerified: emailVerified ?? current.emailVerified,
        membershipNumber: current.membershipNumber,
        pvcVin: pvcVin ?? current.pvcVin,
        selfieReference: selfieReference ?? current.selfieReference,
        accountStatus: accountStatus ?? current.accountStatus,
        identityReview: identityReview ?? current.identityReview,
        createdAt: current.createdAt,
        status: status ?? current.status,
        origin: current.origin,
      );

  static TgcgRole? _role(Object? value) {
    final name = value?.toString();
    for (final item in TgcgRole.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static AccreditationStatus? _accreditationStatus(Object? value) {
    final name = value?.toString();
    for (final item in AccreditationStatus.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static RecordStatus? _recordStatus(Object? value) {
    final name = value?.toString();
    for (final item in RecordStatus.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static MemberAccountStatus? _memberAccountStatus(Object? value) {
    final name = value?.toString();
    for (final item in MemberAccountStatus.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static MemberIdentityReview? _memberIdentityReview(Object? value) {
    final name = value?.toString();
    for (final item in MemberIdentityReview.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static RecordOrigin? _recordOrigin(Object? value) {
    final name = value?.toString();
    for (final item in RecordOrigin.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static MemberPollingUnitLinkSource? _linkSource(Object? value) {
    final name = value?.toString();
    for (final item in MemberPollingUnitLinkSource.values) {
      if (item.name == name) return item;
    }
    return null;
  }

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    return value == null ? null : double.tryParse(value.toString());
  }

  static String _pinCredentialKey(String memberId) =>
      'usesf.member.$memberId.pin';

  static String _passwordCredentialKey(String memberId) =>
      'usesf.member.$memberId.password';

  static String _pvcMemberFingerprintKey(String memberId) =>
      'usesf.member.$memberId.pvc_fingerprint';

  static String _pvcIndexKey(String fingerprint) =>
      'usesf.pvc_index.$fingerprint';

  static String _normalizePvcCredential(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String _normalizePhone(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('2340')) {
      digits = '234${digits.substring(4)}';
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = '234${digits.substring(1)}';
    }
    return digits;
  }

  static Future<String> _sha256Base64(String value) async {
    final hash = await Sha256().hash(utf8.encode(value));
    return base64UrlEncode(hash.bytes);
  }

  static Future<List<int>> _derivePin(
    String pin,
    List<int> salt,
  ) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    );
    final secret = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return secret.extractBytes();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var index = 0; index < a.length; index++) {
      difference |= a.codeUnitAt(index) ^ b.codeUnitAt(index);
    }
    return difference == 0;
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
