import '../assignments/assignment_store.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../governance/governance_store.dart';

enum EffectiveGrantSource {
  role,
  assignment,
}

class EffectiveAccessGrant {
  const EffectiveAccessGrant({
    required this.source,
    required this.sourceId,
    required this.label,
    required this.scope,
    required this.capabilities,
    this.role,
  });

  final EffectiveGrantSource source;
  final String sourceId;
  final String label;
  final GeographicScope scope;
  final Set<TgcgCapability> capabilities;
  final TgcgRole? role;

  bool allows(
    TgcgCapability capability, {
    GeographicScope? targetScope,
  }) {
    if (!capabilities.contains(capability)) return false;
    if (targetScope == null) return true;
    return TgcgPermissionPolicy.scopeAllows(scope, targetScope);
  }
}

/// Resolves the operational authority attached to one permanent member
/// identity. Membership by itself grants no operational capability.
///
/// Access is the union of:
/// - every active role assignment, each constrained to that role's scope; and
/// - every active job/assignment capability grant, constrained to the
///   assignment's authorization/target scope.
///
/// Because this snapshot is rebuilt from active records, assignment-only
/// access disappears automatically as soon as the assignment becomes terminal.
class EffectiveMemberAccess {
  EffectiveMemberAccess._({
    required this.memberId,
    required List<EffectiveAccessGrant> grants,
  }) : grants = List.unmodifiable(grants);

  factory EffectiveMemberAccess.resolve({
    required String memberId,
    required GovernanceOperationsController governance,
    required AssignmentController assignments,
  }) {
    final grants = <EffectiveAccessGrant>[];

    for (final record in governance.activeRolesForMember(memberId)) {
      grants.add(
        EffectiveAccessGrant(
          source: EffectiveGrantSource.role,
          sourceId: record.id,
          label: record.role.name,
          scope: record.scope,
          capabilities:
              TgcgPermissionPolicy.capabilitiesFor(record.role),
          role: record.role,
        ),
      );
    }

    for (final assignment in assignments.activeAssignmentsForMember(memberId)) {
      if (!assignment.confersAccess || assignment.grantedCapabilities.isEmpty) {
        continue;
      }
      grants.add(
        EffectiveAccessGrant(
          source: EffectiveGrantSource.assignment,
          sourceId: assignment.id,
          label: assignment.title,
          scope: assignment.targetScope,
          capabilities: assignment.grantedCapabilities,
        ),
      );
    }

    return EffectiveMemberAccess._(
      memberId: memberId,
      grants: grants,
    );
  }

  final String memberId;
  final List<EffectiveAccessGrant> grants;

  bool get hasOperationalAccess =>
      grants.any((grant) => grant.capabilities.isNotEmpty);

  Set<TgcgCapability> get capabilities => grants
      .expand((grant) => grant.capabilities)
      .toSet();

  List<GeographicScope> scopesFor(TgcgCapability capability) {
    final scopes = <GeographicScope>[];
    final keys = <String>{};
    for (final grant in grants) {
      if (!grant.capabilities.contains(capability)) continue;
      final key = _scopeKey(grant.scope);
      if (keys.add(key)) scopes.add(grant.scope);
    }
    return List.unmodifiable(scopes);
  }

  bool allows(
    TgcgCapability capability, {
    GeographicScope? targetScope,
  }) =>
      grants.any(
        (grant) => grant.allows(
          capability,
          targetScope: targetScope,
        ),
      );

  List<EffectiveAccessGrant> grantsFor(TgcgCapability capability) =>
      grants
          .where((grant) => grant.capabilities.contains(capability))
          .toList(growable: false);

  static String _scopeKey(GeographicScope scope) =>
      '${scope.level.name}:${scope.country}:${scope.zoneId ?? ''}:'
      '${scope.stateId ?? ''}:${scope.senatorialDistrictId ?? ''}:'
      '${scope.lgaId ?? ''}:${scope.wardId ?? ''}:'
      '${scope.pollingUnitId ?? ''}';
}
