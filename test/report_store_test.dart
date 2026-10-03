import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/domain/models.dart';
import 'package:usesf/tgcg/governance/governance_store.dart';
import 'package:usesf/tgcg/reports/report_store.dart';

void main() {
  test('authorized export is queued and audited', () {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);
    final beforeAudit = governance.auditEvents.length;

    final job = reports.requestExport(
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

  test('polling unit agent cannot request privileged report export', () {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);

    final job = reports.requestExport(
      kind: ReportKind.auditTrail,
      format: ExportFormat.csv,
      targetScope: GeographicScope.kaduna,
      actorId: 'AG-001',
      role: TgcgRole.pollingUnitAgent,
      userScope: GeographicScope.kaduna,
    );

    expect(job, isNull);
  });

  test('report type requires its underlying capability', () {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);

    final auditJob = reports.requestExport(
      kind: ReportKind.auditTrail,
      format: ExportFormat.csv,
      targetScope: GeographicScope.kaduna,
      actorId: 'STATE-001',
      role: TgcgRole.stateCoordinator,
      userScope: GeographicScope.kaduna,
    );
    final incidentJob = reports.requestExport(
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

  test('export target cannot escape operator geographic scope', () {
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

    final job = reports.requestExport(
      kind: ReportKind.fieldActivity,
      format: ExportFormat.csv,
      targetScope: kadunaSouth,
      actorId: 'COORD-KC',
      role: TgcgRole.senatorialCoordinator,
      userScope: kadunaCentral,
    );

    expect(job, isNull);
  });

  test('scoped export history does not expose broader state-wide jobs', () {
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

    final job = reports.requestExport(
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

  test('history hides report kinds the viewer cannot access', () {
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

    final auditJob = reports.requestExport(
      kind: ReportKind.auditTrail,
      format: ExportFormat.csv,
      targetScope: kaduna,
      actorId: 'ADMIN-001',
      role: TgcgRole.stateAdministrator,
      userScope: GeographicScope.kaduna,
    );
    final incidentJob = reports.requestExport(
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

  test('job lifecycle retains artifact provenance and creates audit events', () {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);
    final job = reports.requestExport(
      kind: ReportKind.evidencePackage,
      format: ExportFormat.zip,
      targetScope: GeographicScope.kaduna,
      actorId: 'LEGAL-001',
      role: TgcgRole.stateAdministrator,
      userScope: GeographicScope.kaduna,
      recordCount: 3,
    )!;

    reports.markFailed(
      job.id,
      actorId: 'WORKER-01',
      error: 'Prototype worker failure.',
    );
    expect(reports.jobs.first.error, 'Prototype worker failure.');

    reports.markGenerating(job.id, actorId: 'WORKER-01');
    expect(reports.jobs.first.status, ExportJobStatus.generating);
    expect(reports.jobs.first.error, isNull);

    reports.markCompleted(
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
      governance.auditEvents.any((event) => event.action == 'report_export_completed'),
      isTrue,
    );
  });
}
