import 'package:flutter/widgets.dart';

import '../assignments/assignment_store.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../governance/governance_store.dart';
import '../session.dart';
import 'effective_member_access.dart';

/// Context-aware authorization facade.
///
/// Legacy operational sessions continue to use the static role policy. Member
/// sessions resolve every active role plus every active assignment grant.
/// This lets one permanent member identity operate with several roles/scopes
/// without pretending that the member has one global role.
class TgcgAccessPolicy {
  const TgcgAccessPolicy._();

  static EffectiveMemberAccess? memberAccess(
    BuildContext context, {
    bool listen = true,
  }) {
    final session = TgcgSession.of(context, listen: listen);
    if (session.role != TgcgRole.member || session.accessId.isEmpty) {
      return null;
    }
    final governance = GovernanceOperations.of(context, listen: listen);
    final assignments = Assignments.of(context, listen: listen);
    return EffectiveMemberAccess.resolve(
      memberId: session.accessId,
      governance: governance,
      assignments: assignments,
    );
  }

  static Set<TgcgCapability> capabilities(
    BuildContext context, {
    bool listen = true,
  }) {
    final session = TgcgSession.of(context, listen: listen);
    final member = memberAccess(context, listen: listen);
    if (member != null) return member.capabilities;
    final role = session.role;
    if (role == null) return const {};
    return TgcgPermissionPolicy.capabilitiesFor(role);
  }

  static bool allows(
    BuildContext context,
    TgcgCapability capability, {
    GeographicScope? targetScope,
    bool listen = true,
  }) {
    final session = TgcgSession.of(context, listen: listen);
    final member = memberAccess(context, listen: listen);
    if (member != null) {
      return member.allows(
        capability,
        targetScope: targetScope,
      );
    }

    final role = session.role;
    if (role == null) return false;
    return TgcgPermissionPolicy.may(
      role,
      session.scope,
      capability,
      targetScope: targetScope,
    );
  }

  static List<GeographicScope> scopesFor(
    BuildContext context,
    TgcgCapability capability, {
    bool listen = true,
  }) {
    final session = TgcgSession.of(context, listen: listen);
    final member = memberAccess(context, listen: listen);
    if (member != null) return member.scopesFor(capability);

    final role = session.role;
    if (role == null || !TgcgPermissionPolicy.allows(role, capability)) {
      return const [];
    }
    return [session.scope];
  }

  static bool scopeVisible(
    BuildContext context,
    TgcgCapability capability,
    GeographicScope targetScope, {
    bool listen = true,
  }) =>
      allows(
        context,
        capability,
        targetScope: targetScope,
        listen: listen,
      );

  static List<GeographicScope> scopesForAny(
    BuildContext context,
    Iterable<TgcgCapability> capabilities, {
    bool listen = true,
  }) {
    final result = <GeographicScope>[];
    final seen = <String>{};
    for (final capability in capabilities) {
      for (final scope in scopesFor(
        context,
        capability,
        listen: listen,
      )) {
        final key = _scopeKey(scope);
        if (seen.add(key)) result.add(scope);
      }
    }
    return List.unmodifiable(result);
  }

  static String accessSummary(
    BuildContext context, {
    bool listen = true,
  }) {
    final session = TgcgSession.of(context, listen: listen);
    final member = memberAccess(context, listen: listen);
    if (member == null) {
      final role = session.role;
      return role == null ? 'No access' : roleLabel(role);
    }

    final roleCount = member.grants
        .where((grant) => grant.source == EffectiveGrantSource.role)
        .length;
    final assignmentCount = member.grants
        .where((grant) => grant.source == EffectiveGrantSource.assignment)
        .length;
    if (roleCount == 0 && assignmentCount == 0) return 'Member';
    if (roleCount == 0) {
      return '$assignmentCount active assignment${assignmentCount == 1 ? '' : 's'}';
    }
    if (assignmentCount == 0) {
      return '$roleCount active role${roleCount == 1 ? '' : 's'}';
    }
    return '$roleCount role${roleCount == 1 ? '' : 's'} • '
        '$assignmentCount assignment${assignmentCount == 1 ? '' : 's'}';
  }

  static String actorLabelFor(
    BuildContext context,
    TgcgCapability capability, {
    GeographicScope? targetScope,
    bool listen = false,
  }) {
    final role = roleFor(
      context,
      capability,
      targetScope: targetScope,
      listen: listen,
    );
    if (role != null) return roleLabel(role);

    final member = memberAccess(context, listen: listen);
    if (member != null) {
      final grants = member.grantsFor(capability);
      if (grants.isNotEmpty) return grants.first.label;
    }
    return 'Member';
  }

  /// Chooses a concrete scope that authorizes an operation. For member
  /// sessions, the narrowest matching grant is preferred when a target is
  /// supplied; otherwise the broadest available grant is used.
  static TgcgRole? roleFor(
    BuildContext context,
    TgcgCapability capability, {
    GeographicScope? targetScope,
    bool listen = false,
  }) {
    final session = TgcgSession.of(context, listen: listen);
    final member = memberAccess(context, listen: listen);
    if (member == null) {
      final role = session.role;
      return role != null &&
              TgcgPermissionPolicy.may(
                role,
                session.scope,
                capability,
                targetScope: targetScope,
              )
          ? role
          : null;
    }

    final roles = member.grants
        .where(
          (grant) =>
              grant.role != null &&
              grant.allows(
                capability,
                targetScope: targetScope,
              ),
        )
        .map((grant) => grant.role!)
        .toList(growable: false);
    if (roles.isEmpty) return null;
    roles.sort((a, b) => _roleRank(b).compareTo(_roleRank(a)));
    return roles.first;
  }

  static GeographicScope? authorizingScope(
    BuildContext context,
    TgcgCapability capability, {
    GeographicScope? targetScope,
    bool listen = false,
  }) {
    final scopes = scopesFor(
      context,
      capability,
      listen: listen,
    ).where((scope) {
      if (targetScope == null) return true;
      return TgcgPermissionPolicy.scopeAllows(scope, targetScope);
    }).toList();

    if (scopes.isEmpty) return null;
    scopes.sort(
      (a, b) => targetScope == null
          ? _rank(a.level).compareTo(_rank(b.level))
          : _rank(b.level).compareTo(_rank(a.level)),
    );
    return scopes.first;
  }

  static String _scopeKey(GeographicScope scope) =>
      '${scope.level.name}:${scope.country}:${scope.zoneId ?? ''}:'
      '${scope.stateId ?? ''}:${scope.senatorialDistrictId ?? ''}:'
      '${scope.lgaId ?? ''}:${scope.wardId ?? ''}:'
      '${scope.pollingUnitId ?? ''}';

  static int _roleRank(TgcgRole role) => switch (role) {
        TgcgRole.stateAdministrator => 100,
        TgcgRole.stateCoordinator => 90,
        TgcgRole.senatorialCoordinator => 80,
        TgcgRole.lgaCoordinator => 70,
        TgcgRole.wardCoordinator => 60,
        TgcgRole.pollingUnitCoordinator => 50,
        TgcgRole.pollingUnitAgent => 40,
        _ => 10,
      };

  static int _rank(GeographyLevel level) => switch (level) {
        GeographyLevel.country => 0,
        GeographyLevel.geopoliticalZone => 1,
        GeographyLevel.state => 2,
        GeographyLevel.senatorialDistrict => 3,
        GeographyLevel.lga => 4,
        GeographyLevel.ward => 5,
        GeographyLevel.pollingUnit => 6,
      };
}
