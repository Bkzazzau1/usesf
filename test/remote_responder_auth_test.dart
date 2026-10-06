import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/domain/permissions.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';
import 'package:usesf/tgcg/security/emergency_response_store.dart';
import 'package:usesf/tgcg/security/remote_responder_auth.dart';

class _FakeRemoteResponderAuth implements RemoteResponderAuthGateway {
  RemoteResponderAuthenticationResult authenticationResult =
      const RemoteResponderAuthenticationResult(
    status: RemoteResponderAuthenticationStatus.unavailable,
  );

  int authenticationCalls = 0;
  int validationCalls = 0;
  RemoteResponderSessionResult validationResult =
      const RemoteResponderSessionResult(
    status: RemoteResponderSessionStatus.active,
  );

  @override
  Future<RemoteResponderAuthenticationResult> authenticate({
    required String agencyId,
    required String serviceNumber,
    required String accessCode,
    required GeographicScope requestedScope,
  }) async {
    authenticationCalls += 1;
    return authenticationResult;
  }

  @override
  Future<RemoteResponderSessionResult> validateSession({
    required String sessionToken,
  }) async {
    validationCalls += 1;
    return validationResult;
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<({
    EmergencyResponseController emergency,
    EmergencyAgency agency,
    EmergencyResponderProfile responder,
    _FakeRemoteResponderAuth remote,
  })> buildFixture() async {
    final persistence = OfflinePersistenceController(
      openDatabase: () async => InMemoryOfflineDatabase(),
    );
    await persistence.initialize();
    final governance = GovernanceOperationsController.productionFoundation(
      persistence: persistence,
    );
    final remote = _FakeRemoteResponderAuth();
    final emergency = EmergencyResponseController.productionFoundation(
      governance: governance,
      persistence: persistence,
      remoteAuth: remote,
    );
    final agency = await emergency.upsertAgency(
      id: 'AGENCY-CENTRAL-POLICE',
      name: 'Central Police Response Desk',
      shortName: 'Police',
      type: EmergencyAgencyType.police,
      coverage: GeographicScope.kaduna,
      commandDesk: 'Central Response Desk',
      contactPhone: '+2348000000111',
      actorId: 'SYSTEM-ADMIN',
      actorRole: TgcgRole.stateAdministrator,
      authorizedScope: GeographicScope.kaduna,
    );
    final responder = await emergency.provisionResponder(
      agencyId: agency.id,
      serviceNumber: 'AP/CENTRAL-001',
      displayName: 'Insp. Central Officer',
      accessCode: 'CentralAccess123!',
      responderScope: GeographicScope.kaduna,
      actorId: 'SYSTEM-ADMIN',
      actorRole: TgcgRole.stateAdministrator,
      authorizedScope: GeographicScope.kaduna,
    );
    return (
      emergency: emergency,
      agency: agency,
      responder: responder,
      remote: remote,
    );
  }

  test('central lockout overrides a correct local credential', () async {
    final fixture = await buildFixture();
    final lockedUntil =
        DateTime.now().toUtc().add(const Duration(minutes: 15));
    fixture.remote.authenticationResult =
        RemoteResponderAuthenticationResult(
      status: RemoteResponderAuthenticationStatus.locked,
      lockedUntil: lockedUntil,
    );

    final result =
        await fixture.emergency.authenticateResponderCredential(
      agencyId: fixture.agency.id,
      serviceNumber: fixture.responder.serviceNumber,
      accessCode: 'CentralAccess123!',
      requestedScope: GeographicScope.kaduna,
    );

    expect(result.status, ResponderAuthenticationStatus.locked);
    expect(result.lockedUntil, isNotNull);
    expect(fixture.remote.authenticationCalls, 1);
  });

  test('central server errors fail closed instead of falling back',
      () async {
    final fixture = await buildFixture();
    fixture.remote.authenticationResult =
        const RemoteResponderAuthenticationResult(
      status: RemoteResponderAuthenticationStatus.serverError,
      message: 'HTTP 500',
    );

    final result =
        await fixture.emergency.authenticateResponderCredential(
      agencyId: fixture.agency.id,
      serviceNumber: fixture.responder.serviceNumber,
      accessCode: 'CentralAccess123!',
      requestedScope: GeographicScope.kaduna,
    );

    expect(result.status, ResponderAuthenticationStatus.rejected);
    expect(fixture.remote.authenticationCalls, 1);
  });

  test('network unavailability falls back to secure local authentication',
      () async {
    final fixture = await buildFixture();
    fixture.remote.authenticationResult =
        const RemoteResponderAuthenticationResult(
      status: RemoteResponderAuthenticationStatus.unavailable,
      message: 'offline',
    );

    final result =
        await fixture.emergency.authenticateResponderCredential(
      agencyId: fixture.agency.id,
      serviceNumber: fixture.responder.serviceNumber,
      accessCode: 'CentralAccess123!',
      requestedScope: GeographicScope.kaduna,
    );

    expect(result.status, ResponderAuthenticationStatus.authenticated);
    expect(result.responder?.id, fixture.responder.id);
    expect(fixture.remote.authenticationCalls, 1);
  });

  test('revoked central session invalidates connected responder session',
      () async {
    final fixture = await buildFixture();
    fixture.remote.validationResult =
        const RemoteResponderSessionResult(
      status: RemoteResponderSessionStatus.revoked,
    );

    final result = await fixture.emergency.validateConnectedSession(
      sessionToken: 'server-session-token',
      agencyId: fixture.agency.id,
      serviceNumber: fixture.responder.serviceNumber,
    );

    expect(result, ResponderSessionValidationStatus.revoked);
    expect(fixture.remote.validationCalls, 1);
  });

  test('network loss does not revoke an already authenticated offline session',
      () async {
    final fixture = await buildFixture();
    fixture.remote.validationResult =
        const RemoteResponderSessionResult(
      status: RemoteResponderSessionStatus.unavailable,
    );

    final result = await fixture.emergency.validateConnectedSession(
      sessionToken: 'server-session-token',
      agencyId: fixture.agency.id,
      serviceNumber: fixture.responder.serviceNumber,
    );

    expect(result, ResponderSessionValidationStatus.unavailable);
  });

  test('confirmed central revocation blocks later offline reauthentication',
      () async {
    final fixture = await buildFixture();
    fixture.remote.validationResult =
        const RemoteResponderSessionResult(
      status: RemoteResponderSessionStatus.revoked,
    );

    final validation = await fixture.emergency.validateConnectedSession(
      sessionToken: 'server-session-token',
      agencyId: fixture.agency.id,
      serviceNumber: fixture.responder.serviceNumber,
    );
    expect(validation, ResponderSessionValidationStatus.revoked);

    fixture.remote.authenticationResult =
        const RemoteResponderAuthenticationResult(
      status: RemoteResponderAuthenticationStatus.unavailable,
    );

    final offlineAttempt =
        await fixture.emergency.authenticateResponderCredential(
      agencyId: fixture.agency.id,
      serviceNumber: fixture.responder.serviceNumber,
      accessCode: 'CentralAccess123!',
      requestedScope: GeographicScope.kaduna,
    );

    expect(offlineAttempt.status, ResponderAuthenticationStatus.rejected);
  });

  test('central rejection is never overridden by a valid local secret',
      () async {
    final fixture = await buildFixture();
    fixture.remote.authenticationResult =
        const RemoteResponderAuthenticationResult(
      status: RemoteResponderAuthenticationStatus.rejected,
    );

    final result =
        await fixture.emergency.authenticateResponderCredential(
      agencyId: fixture.agency.id,
      serviceNumber: fixture.responder.serviceNumber,
      accessCode: 'CentralAccess123!',
      requestedScope: GeographicScope.kaduna,
    );

    expect(result.status, ResponderAuthenticationStatus.rejected);
  });
}
