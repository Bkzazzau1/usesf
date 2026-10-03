import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/permissions.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/security/emergency_response_store.dart';
import 'package:usesf/tgcg/session.dart';

void main() {
  group('Security Portal', () {
    test('security officer can only respond to dispatches', () {
      expect(
        TgcgPermissionPolicy.capabilitiesFor(TgcgRole.securityOfficer),
        {TgcgCapability.respondToDispatch},
      );
      expect(allowedModules(TgcgRole.securityOfficer), {TgcgModule.securityResponse});
    });

    test('session carries the agency and clears it on sign-out', () {
      final session = TgcgSessionController()
        ..signIn(
          role: TgcgRole.securityOfficer,
          operatorName: 'Insp. Musa Bello',
          accessId: 'AP/12345',
          agencyId: 'AGENCY-POLICE',
        );

      expect(session.agencyId, 'AGENCY-POLICE');
      expect(roleLabel(session.role!), 'Security Officer');

      session.signOut();
      expect(session.agencyId, isNull);
      expect(session.isAuthenticated, isFalse);
    });

    test('officer sees only own-agency dispatches in their command area', () {
      final emergency = EmergencyResponseController.prototypeSeed(
        GovernanceOperationsController.prototypeSeed(),
      );
      final jemaa = GeographyRegistry.prototypeSeed().lga('KD-JEMAA')!.scope;

      List<String> visible(String agencyId, GeographicScope scope) => emergency
          .dispatchesForScope(scope)
          .where((item) => item.agencyId == agencyId)
          .map((item) => item.id)
          .toList();

      expect(visible('AGENCY-POLICE', jemaa), ['DSP-0002']);
      expect(visible('AGENCY-NSCDC', jemaa), ['DSP-0003']);
      expect(visible('AGENCY-POLICE', GeographicScope.kaduna).toSet(), {'DSP-0001', 'DSP-0002'});
    });

    test('response updates are timestamped and audited', () {
      final governance = GovernanceOperationsController.prototypeSeed();
      final emergency = EmergencyResponseController.prototypeSeed(governance);
      final before = governance.auditEvents.length;

      emergency.updateStatus(
        dispatchId: 'DSP-0002',
        status: EmergencyDispatchStatus.acknowledged,
        actorId: 'AP/12345',
      );

      final updated = emergency.dispatches.firstWhere((item) => item.id == 'DSP-0002');
      expect(updated.status, EmergencyDispatchStatus.acknowledged);
      expect(updated.acknowledgedAt, isNotNull);
      expect(updated.lastUpdatedBy, 'AP/12345');
      expect(governance.auditEvents.length, before + 1);
    });
  });
}
