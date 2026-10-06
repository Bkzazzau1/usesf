import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';
import 'package:usesf/tgcg/reports/report_store.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('production report lifecycle is durable and prototype-free', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final persistence = OfflinePersistenceController(
      openDatabase: () async => InMemoryOfflineDatabase(),
    );
    await persistence.initialize();
    final governance = GovernanceOperationsController.productionFoundation(
      persistence: persistence,
    );
    final reports = ReportOperationsController.productionFoundation(
      governance: governance,
      persistence: persistence,
    );

    expect(reports.jobs, isEmpty);

    final job = await reports.requestExport(
      kind: ReportKind.evidencePackage,
      format: ExportFormat.zip,
      targetScope: GeographicScope.kaduna,
      actorId: 'ADMIN-001',
      role: TgcgRole.stateAdministrator,
      userScope: GeographicScope.kaduna,
      recordCount: 3,
    );
    expect(job, isNotNull);
    expect(job!.status, ExportJobStatus.queued);

    await reports.markGenerating(job.id, actorId: 'WORKER-01');
    await reports.markCompleted(
      job.id,
      actorId: 'WORKER-01',
      fileName: 'evidence-package.zip',
      contentHash: 'sha256:test-hash',
    );

    final completed = reports.jobs.single;
    expect(completed.status, ExportJobStatus.completed);
    expect(completed.fileName, 'evidence-package.zip');
    expect(completed.contentHash, 'sha256:test-hash');

    final reportMutations = persistence.outbox
        .where(
          (item) =>
              item.entityType == 'report_export' && item.entityId == job.id,
        )
        .toList(growable: false);
    expect(reportMutations.length, 3);
    expect(reportMutations.every((item) => item.state == SyncState.queued), isTrue);

    final restored = ReportOperationsController.productionFoundation(
      governance: governance,
      persistence: persistence,
    );
    expect(restored.jobs, isEmpty);
    await restored.hydrateFromOffline();

    expect(restored.jobs, hasLength(1));
    expect(restored.jobs.single.id, job.id);
    expect(restored.jobs.single.status, ExportJobStatus.completed);
    expect(restored.jobs.single.fileName, 'evidence-package.zip');
    expect(restored.jobs.single.contentHash, 'sha256:test-hash');
    expect(
      restored.jobs.any(
        (item) => const {'EXP-0001', 'EXP-0002', 'EXP-0003'}.contains(item.id),
      ),
      isFalse,
    );
  });

  test('authorized export is queued and audited', () async {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);
    final beforeAudit = governance.auditEvents.length;

    final job = await reports.requestExport(
      kind: ReportKind.incidentSummary,
      format: ExportFormat.pdf,
      targetScope: GeographicScope.kaduna,
      actorId: 'ADMIN-001',
      role: TgcgRole.stateAdministrator,
      userScope: GeographicScope.kaduna,
      recordCount: 4,
    );

    expect(job, isNotNull);
    expect(job!.status, ExportJobStatus.queued);
    expect(job.recordCount, 4);
    expect(governance.auditEvents.length, beforeAudit + 1);
    expect(governance.auditEvents.first.action, 'report_export_requested');
  });

  test('polling unit agent cannot request privileged report export', () async {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);

    final job = await reports.requestExport(
      kind: ReportKind.auditTrail,
      format: ExportFormat.csv,
      targetScope: GeographicScope.kaduna,
      actorId: 'AG-001',
      role: TgcgRole.pollingUnitAgent,
      userScope: GeographicScope.kaduna,
    );

    expect(job, isNull);
  });

  test('report type requires its underlying capability', () async {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);

    final auditJob = await reports.requestExport(
      kind: ReportKind.auditTrail,
      format: ExportFormat.csv,
      targetScope: GeographicScope.kaduna,
      actorId: 'STATE-001',
      role: TgcgRole.stateCoordinator,
      userScope: GeographicScope.kaduna,
    );
    final incidentJob = await reports.requestExport(
      kind: ReportKind.incidentSummary,
      format: ExportFormat.pdf,
      targetScope: GeographicScope.kaduna,
      actorId: 'STATE-001',
      role: TgcgRole.stateCoordinator,
      userScope: GeographicScope.kaduna,
    );

    expect(auditJob, isNull);
    expect(incidentJob, isNotNull);
  });

  test('export target cannot escape operator geographic scope', () async {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);
    const kadunaCentral = GeographicScope(
      level: GeographyLevel.senatorialDistrict,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/053/KD',
      senatorialDistrictName: 'Kaduna Central',
    );
    const kadunaSouth = GeographicScope(
      level: GeographyLevel.senatorialDistrict,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/054/KD',
      senatorialDistrictName: 'Kaduna South',
    );

    final job = await reports.requestExport(
      kind: ReportKind.fieldActivity,
      format: ExportFormat.csv,
      targetScope: kadunaSouth,
      actorId: 'COORD-KC',
      role: TgcgRole.senatorialCoordinator,
      userScope: kadunaCentral,
    );

    expect(job, isNull);
  });

  test('scoped export history does not expose broader state-wide jobs', () async {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);
    const kadunaCentral = GeographicScope(
      level: GeographyLevel.senatorialDistrict,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/053/KD',
      senatorialDistrictName: 'Kaduna Central',
    );

    expect(reports.jobsForScope(GeographicScope.kaduna), isNotEmpty);
    expect(reports.jobsForScope(kadunaCentral), isEmpty);

    final job = await reports.requestExport(
      kind: ReportKind.incidentSummary,
      format: ExportFormat.pdf,
      targetScope: kadunaCentral,
      actorId: 'COORD-KC',
      role: TgcgRole.senatorialCoordinator,
      userScope: kadunaCentral,
    );

    expect(job, isNotNull);
    expect(
      reports.jobsForScope(kadunaCentral).map((item) => item.id),
      [job!.id],
    );
  });

  test('history hides report kinds the viewer cannot access', () async {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);
    const kaduna = GeographicScope(
      level: GeographyLevel.state,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
    );

    final auditJob = await reports.requestExport(
      kind: ReportKind.auditTrail,
      format: ExportFormat.csv,
      targetScope: kaduna,
      actorId: 'ADMIN-001',
      role: TgcgRole.stateAdministrator,
      userScope: GeographicScope.kaduna,
    );
    final incidentJob = await reports.requestExport(
      kind: ReportKind.incidentSummary,
      format: ExportFormat.pdf,
      targetScope: kaduna,
      actorId: 'ADMIN-001',
      role: TgcgRole.stateAdministrator,
      userScope: GeographicScope.kaduna,
    );

    expect(auditJob, isNotNull);
    expect(incidentJob, isNotNull);

    final visible = reports.jobsForScope(
      kaduna,
      role: TgcgRole.stateCoordinator,
    );

    expect(visible.map((job) => job.id), contains(incidentJob!.id));
    expect(visible.map((job) => job.id), isNot(contains(auditJob!.id)));
  });

  test('job lifecycle retains artifact provenance and creates audit events',
      () async {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);
    final job = (await reports.requestExport(
      kind: ReportKind.evidencePackage,
      format: ExportFormat.zip,
      targetScope: GeographicScope.kaduna,
      actorId: 'LEGAL-001',
      role: TgcgRole.stateAdministrator,
      userScope: GeographicScope.kaduna,
      recordCount: 3,
    ))!;

    await reports.markFailed(
      job.id,
      actorId: 'WORKER-01',
      error: 'Prototype worker failure.',
    );
    expect(reports.jobs.first.error, 'Prototype worker failure.');

    await reports.markGenerating(job.id, actorId: 'WORKER-01');
    expect(reports.jobs.first.status, ExportJobStatus.generating);
    expect(reports.jobs.first.error, isNull);

    await reports.markCompleted(
      job.id,
      actorId: 'WORKER-01',
      fileName: 'evidence-package.zip',
      contentHash: 'sha256:test-hash',
    );

    final completed = reports.jobs.first;
    expect(completed.status, ExportJobStatus.completed);
    expect(completed.fileName, 'evidence-package.zip');
    expect(completed.contentHash, 'sha256:test-hash');
    expect(completed.error, isNull);
    expect(
      governance.auditEvents.any(
        (event) => event.action == 'report_export_completed',
      ),
      isTrue,
    );
  });
}
