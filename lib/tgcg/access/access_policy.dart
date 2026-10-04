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

  /// Chooses a concrete scope that authorizes an operation. For member
  /// sessions, the narrowest matching grant is preferred when a target is
  /// supplied; otherwise the broadest available grant is used.
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
