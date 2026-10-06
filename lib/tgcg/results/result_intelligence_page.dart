import 'package:flutter/material.dart';

import '../access/access_policy.dart';
import '../assignments/assignment_control_actions.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../geography/geography_registry.dart';
import '../membership/membership_store.dart';
import '../meeting/operational_call_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'result_operations_store.dart';

enum ResultAiState { clean, consistent, review, risk }

enum ResultAccountingState {
  missing,
  received,
  aiReview,
  conflict,
  disputed,
  verified,
}

enum ResultAiFindingSeverity { info, warning, critical }

class ResultAiFinding {
  const ResultAiFinding({
    required this.label,
    required this.detail,
    required this.severity,
  });

  final String label;
  final String detail;
  final ResultAiFindingSeverity severity;
}

class ResultAiAssessment {
  const ResultAiAssessment({
    required this.score,
    required this.state,
    required this.findings,
  });

  final int score;
  final ResultAiState state;
  final List<ResultAiFinding> findings;
}

class PollingUnitResultAccount {
  const PollingUnitResultAccount({
    required this.unit,
    required this.submissions,
    required this.state,
  });

  final CanonicalPollingUnit unit;
  final List<ElectionResultSubmission> submissions;
  final ResultAccountingState state;

  List<ElectionResultSubmission> get unresolvedCandidates => submissions
      .where(
        (item) =>
            item.status != RecordStatus.disputed &&
            item.status != RecordStatus.rejected &&
            item.status != RecordStatus.archived,
      )
      .toList(growable: false);

  bool get hasConflict => unresolvedCandidates.length > 1;
  bool get hasSubmission => submissions.isNotEmpty;
  bool get hasVerified =>
      submissions.any((item) => item.status == RecordStatus.verified);
}

class ResultLgaAccounting {
  const ResultLgaAccounting({
    required this.lgaId,
    required this.lgaName,
    required this.accounts,
  });

  final String lgaId;
  final String lgaName;
  final List<PollingUnitResultAccount> accounts;

  int get expected => accounts.length;
  int get received => accounts.where((item) => item.hasSubmission).length;
  int get missing =>
      accounts.where((item) => item.state == ResultAccountingState.missing).length;
  int get verified => accounts
      .where((item) => item.state == ResultAccountingState.verified)
      .length;
  int get review => accounts
      .where(
        (item) =>
            item.state == ResultAccountingState.aiReview ||
            item.state == ResultAccountingState.disputed,
      )
      .length;
  int get conflicts => accounts
      .where((item) => item.state == ResultAccountingState.conflict)
      .length;
}

ResultAiAssessment buildResultAiAssessment(
  ElectionResultSubmission submission, {
  bool accountConflict = false,
}) {
  var score = 100;
  final findings = <ResultAiFinding>[];
  final validation = submission.validation;
  final form = submission.resultForm;

  if (form == null) {
    score -= 18;
    findings.add(
      const ResultAiFinding(
        label: 'Result form unavailable',
        detail: 'No result-form image is attached to this submission.',
        severity: ResultAiFindingSeverity.warning,
      ),
    );
  } else {
    findings.add(
      const ResultAiFinding(
        label: 'Result form received',
        detail: 'Original form evidence is attached to the submission.',
        severity: ResultAiFindingSeverity.info,
      ),
    );
    if (form.contentHash == null || form.contentHash!.trim().isEmpty) {
      score -= 12;
      findings.add(
        const ResultAiFinding(
          label: 'Integrity hash unavailable',
          detail: 'The attached form has no stored content hash.',
          severity: ResultAiFindingSeverity.warning,
        ),
      );
    } else {
      findings.add(
        const ResultAiFinding(
          label: 'Evidence integrity recorded',
          detail: 'A content hash is stored for the result form.',
          severity: ResultAiFindingSeverity.info,
        ),
      );
    }

    if (form.latitude == null || form.longitude == null) {
      score -= 5;
      findings.add(
        const ResultAiFinding(
          label: 'Form GPS unavailable',
          detail: 'The result-form evidence has no capture GPS attached.',
          severity: ResultAiFindingSeverity.warning,
        ),
      );
    } else {
      findings.add(
        const ResultAiFinding(
          label: 'Form GPS attached',
          detail: 'Capture coordinates are attached to the result form.',
          severity: ResultAiFindingSeverity.info,
        ),
      );
    }
  }

  if (validation == null) {
    score -= 20;
    findings.add(
      const ResultAiFinding(
        label: 'Validation unavailable',
        detail: 'No automated result-integrity assessment is stored.',
        severity: ResultAiFindingSeverity.critical,
      ),
    );
  } else {
    if (validation.arithmeticValid) {
      findings.add(
        const ResultAiFinding(
          label: 'Arithmetic passed',
          detail: 'Party totals and voter-accounting checks are internally consistent.',
          severity: ResultAiFindingSeverity.info,
        ),
      );
    } else {
      score -= 30;
      findings.add(
        const ResultAiFinding(
          label: 'Arithmetic anomaly',
          detail: 'Submitted totals failed one or more arithmetic checks.',
          severity: ResultAiFindingSeverity.critical,
        ),
      );
    }

    if (!validation.pollingUnitMatched) {
      score -= 25;
      findings.add(
        const ResultAiFinding(
          label: 'Polling-unit mismatch',
          detail: 'Submitted polling-unit identity does not match master data.',
          severity: ResultAiFindingSeverity.critical,
        ),
      );
    }

    if (!validation.agentScopeMatched) {
      score -= 20;
      findings.add(
        const ResultAiFinding(
          label: 'Submitter scope mismatch',
          detail: 'The submitting agent is not matched to the polling-unit scope.',
          severity: ResultAiFindingSeverity.critical,
        ),
      );
    }

    if (validation.duplicateSuspected || accountConflict) {
      score -= 20;
      findings.add(
        const ResultAiFinding(
          label: 'Duplicate / conflict detected',
          detail: 'More than one unresolved result is associated with this polling unit.',
          severity: ResultAiFindingSeverity.critical,
        ),
      );
    }

    final ocrMatch = validation.ocrMatchedManualEntry;
    if (ocrMatch == false) {
      score -= 25;
      findings.add(
        const ResultAiFinding(
          label: 'AI OCR mismatch',
          detail: 'AI-extracted party figures differ from the submitted figures.',
          severity: ResultAiFindingSeverity.critical,
        ),
      );
    } else if (ocrMatch == true) {
      findings.add(
        const ResultAiFinding(
          label: 'AI OCR matched',
          detail: 'AI-extracted party figures match the submitted figures.',
          severity: ResultAiFindingSeverity.info,
        ),
      );
    } else {
      score -= 8;
      findings.add(
        const ResultAiFinding(
          label: 'AI OCR unavailable',
          detail: 'No OCR figure comparison is stored for this submission.',
          severity: ResultAiFindingSeverity.warning,
        ),
      );
    }

    final confidence = validation.ocrConfidence;
    if (confidence != null) {
      if (confidence < .70) {
        score -= 15;
        findings.add(
          ResultAiFinding(
            label: 'Low OCR confidence',
            detail: '${(confidence * 100).round()}% OCR confidence.',
            severity: ResultAiFindingSeverity.critical,
          ),
        );
      } else if (confidence < .85) {
        score -= 7;
        findings.add(
          ResultAiFinding(
            label: 'OCR confidence needs review',
            detail: '${(confidence * 100).round()}% OCR confidence.',
            severity: ResultAiFindingSeverity.warning,
          ),
        );
      }
    }
  }

  final normalized = score.clamp(0, 100).toInt();
  final hasCritical =
      findings.any((item) => item.severity == ResultAiFindingSeverity.critical);
  final state = normalized >= 90 && !hasCritical
      ? ResultAiState.clean
      : normalized >= 75 && !hasCritical
          ? ResultAiState.consistent
          : normalized >= 55
              ? ResultAiState.review
              : ResultAiState.risk;

  return ResultAiAssessment(
    score: normalized,
    state: state,
    findings: List.unmodifiable(findings),
  );
}

List<PollingUnitResultAccount> buildPollingUnitResultAccounts({
  required List<CanonicalPollingUnit> units,
  required List<ElectionResultSubmission> submissions,
}) {
  final byPollingUnit = <String, List<ElectionResultSubmission>>{};
  for (final submission in submissions) {
    final id = submission.pollingUnitScope.pollingUnitId;
    if (id == null || id.isEmpty) continue;
    byPollingUnit.putIfAbsent(id, () => []).add(submission);
  }

  final accounts = <PollingUnitResultAccount>[];
  for (final unit in units) {
    final id = unit.scope.pollingUnitId ?? unit.code;
    final records = List<ElectionResultSubmission>.from(
      byPollingUnit[id] ?? const [],
    )..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

    final unresolved = records.where(
      (item) =>
          item.status != RecordStatus.disputed &&
          item.status != RecordStatus.rejected &&
          item.status != RecordStatus.archived,
    );
    final unresolvedList = unresolved.toList(growable: false);

    final state = records.isEmpty
        ? ResultAccountingState.missing
        : unresolvedList.length > 1
            ? ResultAccountingState.conflict
            : records.any(
                (item) =>
                    item.status == RecordStatus.underReview ||
                    item.validation?.requiresHumanReview == true,
              )
                ? ResultAccountingState.aiReview
                : records.any((item) => item.status == RecordStatus.verified)
                    ? ResultAccountingState.verified
                    : records.any(
                        (item) => item.status == RecordStatus.disputed,
                      )
                        ? ResultAccountingState.disputed
                        : ResultAccountingState.received;

    accounts.add(
      PollingUnitResultAccount(
        unit: unit,
        submissions: List.unmodifiable(records),
        state: state,
      ),
    );
  }

  accounts.sort((a, b) => a.unit.scope.label.compareTo(b.unit.scope.label));
  return List.unmodifiable(accounts);
}

List<ResultLgaAccounting> buildResultLgaAccounting(
  List<PollingUnitResultAccount> accounts,
) {
  final groups = <String, List<PollingUnitResultAccount>>{};
  final names = <String, String>{};
  for (final account in accounts) {
    final id = account.unit.scope.lgaId;
    if (id == null) continue;
    groups.putIfAbsent(id, () => []).add(account);
    names[id] = account.unit.scope.lgaName ?? id;
  }
  final values = groups.entries
      .map(
        (entry) => ResultLgaAccounting(
          lgaId: entry.key,
          lgaName: names[entry.key] ?? entry.key,
          accounts: List.unmodifiable(entry.value),
        ),
      )
      .toList();
  values.sort((a, b) => a.lgaName.compareTo(b.lgaName));
  return List.unmodifiable(values);
}

class ResultIntelligencePage extends StatefulWidget {
  const ResultIntelligencePage({super.key});

  @override
  State<ResultIntelligencePage> createState() => _ResultIntelligencePageState();
}

class _ResultIntelligencePageState extends State<ResultIntelligencePage> {
  final _search = TextEditingController();
  ResultAccountingState? _status;
  String? _lgaId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final results = ResultOperations.of(context);
    final calls = OperationalCalls.of(context);
    final scope = TgcgAccessPolicy.authorizingScope(
          context,
          TgcgCapability.verifyElectionResult,
        ) ??
        GeographicScope.kaduna;

    final units = membership.geography.pollingUnitsWithin(scope);
    final submissions = results.submissionsForScope(scope);
    final accounts = buildPollingUnitResultAccounts(
      units: units,
      submissions: submissions,
    );
    final lgaAccounting = buildResultLgaAccounting(accounts);

    final received = accounts.where((item) => item.hasSubmission).length;
    final missing = accounts
        .where((item) => item.state == ResultAccountingState.missing)
        .length;
    final verified = accounts
        .where((item) => item.state == ResultAccountingState.verified)
        .length;
    final review = accounts
        .where(
          (item) =>
              item.state == ResultAccountingState.aiReview ||
              item.state == ResultAccountingState.disputed,
        )
        .length;
    final conflicts = accounts
        .where((item) => item.state == ResultAccountingState.conflict)
        .length;

    final query = _search.text.trim().toLowerCase();
    final filtered = accounts.where((account) {
      if (_status != null && account.state != _status) return false;
      if (_lgaId != null && account.unit.scope.lgaId != _lgaId) return false;
      if (query.isEmpty) return true;
      final haystack = [
        account.unit.code,
        account.unit.scope.label,
        account.unit.scope.lgaName,
        account.unit.scope.wardName,
        account.unit.scope.pollingUnitName,
        ...account.submissions.map((item) => item.id),
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);

    final aiQueue = submissions
        .where(
          (item) =>
              item.status != RecordStatus.verified &&
              item.status != RecordStatus.rejected &&
              item.status != RecordStatus.archived,
        )
        .map(
          (item) {
            final account = accounts
                .where(
                  (value) =>
                      value.unit.scope.pollingUnitId ==
                      item.pollingUnitScope.pollingUnitId,
                )
                .firstOrNull;
            return (
              item: item,
              assessment: buildResultAiAssessment(
                item,
                accountConflict: account?.hasConflict == true,
              ),
            );
          },
        )
        .where(
          (entry) =>
              entry.assessment.state == ResultAiState.review ||
              entry.assessment.state == ResultAiState.risk ||
              entry.item.validation?.requiresHumanReview == true,
        )
        .toList(growable: false)
      ..sort(
        (a, b) => a.assessment.score.compareTo(b.assessment.score),
      );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'STATE RESULT INTEGRITY',
          title: 'Result Intelligence',
          subtitle: scope.label,
          trailing: const TgcgStatusPill(
            label: 'UNOFFICIAL FIELD RESULTS',
            color: TgcgColors.warning,
            icon: Icons.info_outline_rounded,
          ),
        ),
        const SizedBox(height: 18),
        _ResultMetrics(
          expected: accounts.length,
          received: received,
          missing: missing,
          verified: verified,
          review: review,
          conflicts: conflicts,
        ),
        const SizedBox(height: 16),
        _LgaAccountingPanel(items: lgaAccounting),
        const SizedBox(height: 16),
        if (aiQueue.isNotEmpty) ...[
          _AiReviewPanel(
            entries: aiQueue.take(10).toList(growable: false),
            onOpen: (item) {
              final account = accounts.firstWhere(
                (value) =>
                    value.unit.scope.pollingUnitId ==
                    item.pollingUnitScope.pollingUnitId,
              );
              _showSubmissionReport(
                context,
                submission: item,
                account: account,
                membership: membership,
                results: results,
                calls: calls,
                session: session,
                stateScope: scope,
              );
            },
          ),
          const SizedBox(height: 16),
        ],
        _ResultFilters(
          search: _search,
          status: _status,
          lgaId: _lgaId,
          lgas: {
            for (final item in lgaAccounting) item.lgaId: item.lgaName,
          },
          onSearch: (_) => setState(() {}),
          onStatus: (value) => setState(() => _status = value),
          onLga: (value) => setState(() => _lgaId = value),
          onClear: () {
            _search.clear();
            setState(() {
              _status = null;
              _lgaId = null;
            });
          },
        ),
        const SizedBox(height: 16),
        TgcgSectionCard(
          title: 'Polling-unit result accounting',
          trailing: TgcgStatusPill(
            label: '${filtered.length} PUs',
            color: TgcgColors.primary,
            compact: true,
          ),
          child: filtered.isEmpty
              ? const TgcgEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matching polling units',
                  message: 'Change the current filters.',
                )
              : Column(
                  children: [
                    for (final account in filtered)
                      _PollingUnitAccountRow(
                        account: account,
                        onTap: () => _showPollingUnitAccount(
                          context,
                          account: account,
                          membership: membership,
                          results: results,
                          calls: calls,
                          session: session,
                          stateScope: scope,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ResultMetrics extends StatelessWidget {
  const _ResultMetrics({
    required this.expected,
    required this.received,
    required this.missing,
    required this.verified,
    required this.review,
    required this.conflicts,
  });

  final int expected;
  final int received;
  final int missing;
  final int verified;
  final int review;
  final int conflicts;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1100
              ? 6
              : constraints.maxWidth >= 720
                  ? 3
                  : constraints.maxWidth >= 460
                      ? 2
                      : 1;
          const gap = 10.0;
          final width =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Expected',
                value: '$expected',
                detail: 'Loaded PU catalogue',
                icon: Icons.how_to_vote_outlined,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Received',
                value: '$received',
                detail: 'PUs with a result',
                icon: Icons.inbox_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Missing',
                value: '$missing',
                detail: 'No result received',
                icon: Icons.hourglass_empty_rounded,
                tone: missing == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Verified',
                value: '$verified',
                detail: 'Human verified',
                icon: Icons.verified_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'AI review',
                value: '$review',
                detail: 'Needs attention',
                icon: Icons.psychology_alt_outlined,
                tone: review == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Conflicts',
                value: '$conflicts',
                detail: 'Multiple unresolved results',
                icon: Icons.compare_arrows_rounded,
                tone: conflicts == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.danger,
              ),
            ],
          );
        },
      );
}

class _LgaAccountingPanel extends StatelessWidget {
  const _LgaAccountingPanel({required this.items});

  final List<ResultLgaAccounting> items;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Geographic accounting',
        child: items.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.map_outlined,
                title: 'No polling-unit catalogue',
                message: 'Import the canonical polling-unit registry.',
              )
            : Column(
                children: [
                  for (final item in items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: TgcgColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(TgcgRadius.sm),
                        border: Border.all(color: TgcgColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.lgaName,
                              style: const TextStyle(
                                color: TgcgColors.ink,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          _MiniCount('EXP', item.expected, TgcgColors.primary),
                          _MiniCount('REC', item.received, TgcgColors.info),
                          _MiniCount('VER', item.verified, TgcgColors.success),
                          _MiniCount(
                            'REV',
                            item.review,
                            item.review == 0
                                ? TgcgColors.muted
                                : TgcgColors.ai,
                          ),
                          _MiniCount(
                            'CON',
                            item.conflicts,
                            item.conflicts == 0
                                ? TgcgColors.muted
                                : TgcgColors.danger,
                          ),
                          _MiniCount(
                            'MISS',
                            item.missing,
                            item.missing == 0
                                ? TgcgColors.muted
                                : TgcgColors.warning,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      );
}

class _MiniCount extends StatelessWidget {
  const _MiniCount(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

class _AiReviewPanel extends StatelessWidget {
  const _AiReviewPanel({
    required this.entries,
    required this.onOpen,
  });

  final List<
      ({
        ElectionResultSubmission item,
        ResultAiAssessment assessment,
      })> entries;
  final ValueChanged<ElectionResultSubmission> onOpen;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'AI review queue',
        trailing: TgcgStatusPill(
          label: '${entries.length} PRIORITY',
          color: TgcgColors.ai,
          icon: Icons.psychology_alt_outlined,
          compact: true,
        ),
        child: Column(
          children: [
            for (final entry in entries)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onOpen(entry.item),
                  borderRadius: BorderRadius.circular(TgcgRadius.sm),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: TgcgColors.ai.withValues(alpha: .04),
                      borderRadius: BorderRadius.circular(TgcgRadius.sm),
                      border: Border.all(
                        color: TgcgColors.ai.withValues(alpha: .16),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.psychology_alt_outlined,
                          color: TgcgColors.ai,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.item.pollingUnitScope.label,
                                style: const TextStyle(
                                  color: TgcgColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                entry.item.id,
                                style: const TextStyle(
                                  color: TgcgColors.muted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TgcgStatusPill(
                          label: 'AI ${entry.assessment.score}',
                          color: _aiColor(entry.assessment.state),
                          compact: true,
                        ),
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: TgcgColors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _ResultFilters extends StatelessWidget {
  const _ResultFilters({
    required this.search,
    required this.status,
    required this.lgaId,
    required this.lgas,
    required this.onSearch,
    required this.onStatus,
    required this.onLga,
    required this.onClear,
  });

  final TextEditingController search;
  final ResultAccountingState? status;
  final String? lgaId;
  final Map<String, String> lgas;
  final ValueChanged<String> onSearch;
  final ValueChanged<ResultAccountingState?> onStatus;
  final ValueChanged<String?> onLga;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final lgaEntries = lgas.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return TgcgSectionCard(
      title: 'Filters',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: TextField(
              controller: search,
              onChanged: onSearch,
              decoration: const InputDecoration(
                labelText: 'Search PU / result',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<ResultAccountingState?>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Accounting status'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All statuses'),
                ),
                for (final item in ResultAccountingState.values)
                  DropdownMenuItem(
                    value: item,
                    child: Text(_accountingLabel(item)),
                  ),
              ],
              onChanged: onStatus,
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              initialValue: lgaId,
              decoration: const InputDecoration(labelText: 'LGA'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All LGAs'),
                ),
                for (final entry in lgaEntries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              onChanged: onLga,
            ),
          ),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _PollingUnitAccountRow extends StatelessWidget {
  const _PollingUnitAccountRow({
    required this.account,
    required this.onTap,
  });

  final PollingUnitResultAccount account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _accountingColor(account.state);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: TgcgColors.surfaceRaised,
              borderRadius: BorderRadius.circular(TgcgRadius.sm),
              border: Border.all(color: TgcgColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  _accountingIcon(account.state),
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.unit.scope.label,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account.unit.code,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                TgcgStatusPill(
                  label: _accountingLabel(account.state).toUpperCase(),
                  color: color,
                  compact: true,
                ),
                const SizedBox(width: 7),
                TgcgStatusPill(
                  label: '${account.submissions.length} RESULT${account.submissions.length == 1 ? '' : 'S'}',
                  color: TgcgColors.info,
                  compact: true,
                ),
                const SizedBox(width: 5),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: TgcgColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showPollingUnitAccount(
  BuildContext context, {
  required PollingUnitResultAccount account,
  required MembershipOperationsController membership,
  required ResultOperationsController results,
  required OperationalCallController calls,
  required TgcgSessionController session,
  required GeographicScope stateScope,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(account.unit.scope.label),
      content: SizedBox(
        width: 820,
        child: SingleChildScrollView(
          child: account.submissions.isEmpty
              ? const TgcgEmptyState(
                  icon: Icons.hourglass_empty_rounded,
                  title: 'Result missing',
                  message: 'No field result has been received for this polling unit.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        TgcgStatusPill(
                          label: _accountingLabel(account.state).toUpperCase(),
                          color: _accountingColor(account.state),
                          compact: true,
                        ),
                        TgcgStatusPill(
                          label: '${account.submissions.length} SUBMISSION${account.submissions.length == 1 ? '' : 'S'}',
                          color: TgcgColors.info,
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    for (final submission in account.submissions)
                      _SubmissionAccountCard(
                        submission: submission,
                        assessment: buildResultAiAssessment(
                          submission,
                          accountConflict: account.hasConflict,
                        ),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          _showSubmissionReport(
                            context,
                            submission: submission,
                            account: account,
                            membership: membership,
                            results: results,
                            calls: calls,
                            session: session,
                            stateScope: stateScope,
                          );
                        },
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _SubmissionAccountCard extends StatelessWidget {
  const _SubmissionAccountCard({
    required this.submission,
    required this.assessment,
    required this.onTap,
  });

  final ElectionResultSubmission submission;
  final ResultAiAssessment assessment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(TgcgRadius.sm),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TgcgColors.surfaceRaised,
                borderRadius: BorderRadius.circular(TgcgRadius.sm),
                border: Border.all(color: TgcgColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${submission.id} • ${submission.submittedBy}',
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TgcgStatusPill(
                    label: submission.status.name.toUpperCase(),
                    color: _recordStatusColor(submission.status),
                    compact: true,
                  ),
                  const SizedBox(width: 6),
                  TgcgStatusPill(
                    label: 'AI ${assessment.score}',
                    color: _aiColor(assessment.state),
                    compact: true,
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: TgcgColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

Future<void> _showSubmissionReport(
  BuildContext context, {
  required ElectionResultSubmission submission,
  required PollingUnitResultAccount account,
  required MembershipOperationsController membership,
  required ResultOperationsController results,
  required OperationalCallController calls,
  required TgcgSessionController session,
  required GeographicScope stateScope,
}) async {
  final assessment = buildResultAiAssessment(
    submission,
    accountConflict: account.hasConflict,
  );
  final member = membership.memberById(submission.submittedBy);
  final callReady =
      member != null && calls.gpsActiveForMember(submission.submittedBy);
  var busy = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(submission.id),
        content: SizedBox(
          width: 900,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    TgcgStatusPill(
                      label: 'AI ${assessment.score}/100',
                      color: _aiColor(assessment.state),
                      icon: Icons.psychology_alt_outlined,
                    ),
                    TgcgStatusPill(
                      label: _aiLabel(assessment.state),
                      color: _aiColor(assessment.state),
                    ),
                    TgcgStatusPill(
                      label: submission.status.name.toUpperCase(),
                      color: _recordStatusColor(submission.status),
                    ),
                    if (account.hasConflict)
                      const TgcgStatusPill(
                        label: 'PU CONFLICT',
                        color: TgcgColors.danger,
                        icon: Icons.compare_arrows_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _ResultFactGrid(
                  submission: submission,
                  memberName: member?.fullName ?? submission.submittedBy,
                ),
                const SizedBox(height: 14),
                TgcgSectionCard(
                  title: 'AI assessment',
                  child: Column(
                    children: [
                      for (final finding in assessment.findings)
                        _FindingRow(finding: finding),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _ManualVsAiTable(submission: submission),
                const SizedBox(height: 14),
                _ResultEvidenceCard(submission: submission),
                if (account.hasConflict) ...[
                  const SizedBox(height: 14),
                  TgcgSectionCard(
                    title: 'Conflicting submissions',
                    child: Column(
                      children: [
                        for (final other in account.submissions)
                          if (other.id != submission.id)
                            _SubmissionAccountCard(
                              submission: other,
                              assessment: buildResultAiAssessment(
                                other,
                                accountConflict: true,
                              ),
                              onTap: () {},
                            ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (member != null)
            OutlinedButton.icon(
              onPressed: busy || !callReady
                  ? null
                  : () async {
                      try {
                        await startStateCoordinatorMemberCall(
                          context,
                          calls: calls,
                          session: session,
                          stateScope: stateScope,
                          member: member,
                          kind: OperationalCallKind.video,
                        );
                      } on StateError catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error.message)),
                        );
                      }
                    },
              icon: const Icon(Icons.videocam_outlined),
              label: Text(callReady ? 'Call submitter' : 'GPS inactive'),
            ),
          OutlinedButton.icon(
            onPressed: busy ||
                    submission.status == RecordStatus.disputed ||
                    submission.status == RecordStatus.rejected ||
                    submission.status == RecordStatus.archived
                ? null
                : () async {
                    final reason = await _askDisputeReason(dialogContext);
                    if (reason == null || !dialogContext.mounted) return;
                    setDialogState(() => busy = true);
                    final role = TgcgAccessPolicy.roleFor(
                      context,
                      TgcgCapability.disputeElectionResult,
                      targetScope: submission.pollingUnitScope,
                      listen: false,
                    );
                    final scope = TgcgAccessPolicy.authorizingScope(
                      context,
                      TgcgCapability.disputeElectionResult,
                      targetScope: submission.pollingUnitScope,
                      listen: false,
                    );
                    if (role != null && scope != null) {
                      await results.dispute(
                        submissionId: submission.id,
                        reviewerId: session.accessId.isEmpty
                            ? session.operatorName
                            : session.accessId,
                        reason: reason,
                        role: role,
                        userScope: scope,
                      );
                    }
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                  },
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Dispute'),
          ),
          FilledButton.icon(
            onPressed: busy || submission.status == RecordStatus.verified
                ? null
                : () async {
                    final confirmed = account.hasConflict
                        ? await _confirmConflictVerification(dialogContext)
                        : true;
                    if (confirmed != true || !dialogContext.mounted) return;
                    setDialogState(() => busy = true);
                    final role = TgcgAccessPolicy.roleFor(
                      context,
                      TgcgCapability.verifyElectionResult,
                      targetScope: submission.pollingUnitScope,
                      listen: false,
                    );
                    final scope = TgcgAccessPolicy.authorizingScope(
                      context,
                      TgcgCapability.verifyElectionResult,
                      targetScope: submission.pollingUnitScope,
                      listen: false,
                    );
                    if (role != null && scope != null) {
                      await results.verify(
                        submissionId: submission.id,
                        verifierId: session.accessId.isEmpty
                            ? session.operatorName
                            : session.accessId,
                        role: role,
                        userScope: scope,
                      );
                    }
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                  },
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Verify'),
          ),
        ],
      ),
    ),
  );
}

class _ResultFactGrid extends StatelessWidget {
  const _ResultFactGrid({
    required this.submission,
    required this.memberName,
  });

  final ElectionResultSubmission submission;
  final String memberName;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Submission',
        child: Wrap(
          spacing: 18,
          runSpacing: 10,
          children: [
            _Fact('Polling unit', submission.pollingUnitScope.label),
            _Fact('Submitted by', memberName),
            _Fact('Source', submission.source.name.toUpperCase()),
            _Fact('Total votes', '${submission.totalVotesRecorded}'),
            _Fact('Accredited', '${submission.accreditedVoters}'),
            _Fact('Rejected', '${submission.rejectedVotes ?? 0}'),
            _Fact(
              'OCR confidence',
              submission.validation?.ocrConfidence == null
                  ? 'N/A'
                  : '${(submission.validation!.ocrConfidence! * 100).round()}%',
            ),
          ],
        ),
      );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: TgcgColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final ResultAiFinding finding;

  @override
  Widget build(BuildContext context) {
    final color = switch (finding.severity) {
      ResultAiFindingSeverity.info => TgcgColors.success,
      ResultAiFindingSeverity.warning => TgcgColors.warning,
      ResultAiFindingSeverity.critical => TgcgColors.danger,
    };
    final icon = switch (finding.severity) {
      ResultAiFindingSeverity.info => Icons.check_circle_outline_rounded,
      ResultAiFindingSeverity.warning => Icons.warning_amber_rounded,
      ResultAiFindingSeverity.critical => Icons.crisis_alert_outlined,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  finding.label,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  finding.detail,
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualVsAiTable extends StatelessWidget {
  const _ManualVsAiTable({required this.submission});

  final ElectionResultSubmission submission;

  @override
  Widget build(BuildContext context) {
    final keys = <String>{
      ...submission.partyVotes.keys,
      ...?submission.ocrPartyVotes?.keys,
    }.toList()
      ..sort();
    return TgcgSectionCard(
      title: 'Submitted vs AI OCR',
      child: Column(
        children: [
          for (final key in keys)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: TgcgColors.border),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      key,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text(
                      'Submitted ${submission.partyVotes[key] ?? '-'}',
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text(
                      'AI ${submission.ocrPartyVotes?[key] ?? '-'}',
                    ),
                  ),
                  Icon(
                    submission.ocrPartyVotes == null
                        ? Icons.remove_rounded
                        : submission.partyVotes[key] ==
                                submission.ocrPartyVotes?[key]
                            ? Icons.check_circle_outline_rounded
                            : Icons.warning_amber_rounded,
                    color: submission.ocrPartyVotes == null
                        ? TgcgColors.muted
                        : submission.partyVotes[key] ==
                                submission.ocrPartyVotes?[key]
                            ? TgcgColors.success
                            : TgcgColors.danger,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultEvidenceCard extends StatelessWidget {
  const _ResultEvidenceCard({required this.submission});

  final ElectionResultSubmission submission;

  @override
  Widget build(BuildContext context) {
    final evidence = submission.resultForm;
    return TgcgSectionCard(
      title: 'Result-form evidence',
      child: evidence == null
          ? const TgcgStatusPill(
              label: 'NO RESULT FORM',
              color: TgcgColors.warning,
              icon: Icons.image_not_supported_outlined,
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TgcgStatusPill(
                  label: evidence.fileName,
                  color: TgcgColors.info,
                  icon: Icons.image_outlined,
                ),
                TgcgStatusPill(
                  label: evidence.contentHash == null
                      ? 'NO HASH'
                      : 'HASHED',
                  color: evidence.contentHash == null
                      ? TgcgColors.warning
                      : TgcgColors.success,
                  icon: Icons.verified_outlined,
                ),
                TgcgStatusPill(
                  label: evidence.latitude == null ||
                          evidence.longitude == null
                      ? 'NO GPS'
                      : 'GPS ATTACHED',
                  color: evidence.latitude == null ||
                          evidence.longitude == null
                      ? TgcgColors.warning
                      : TgcgColors.success,
                  icon: Icons.gps_fixed_rounded,
                ),
              ],
            ),
    );
  }
}

Future<String?> _askDisputeReason(BuildContext context) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Dispute result'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Reason'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            dialogContext,
            controller.text.trim(),
          ),
          child: const Text('Dispute'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (value == null || value.trim().isEmpty) return null;
  return value.trim();
}

Future<bool?> _confirmConflictVerification(BuildContext context) =>
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Conflicting submissions'),
        content: const Text(
          'This polling unit has multiple unresolved submissions. Verify this specific record anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Verify selected'),
          ),
        ],
      ),
    );

String _accountingLabel(ResultAccountingState state) => switch (state) {
      ResultAccountingState.missing => 'Missing',
      ResultAccountingState.received => 'Received',
      ResultAccountingState.aiReview => 'AI review',
      ResultAccountingState.conflict => 'Conflict',
      ResultAccountingState.disputed => 'Disputed',
      ResultAccountingState.verified => 'Verified',
    };

Color _accountingColor(ResultAccountingState state) => switch (state) {
      ResultAccountingState.missing => TgcgColors.warning,
      ResultAccountingState.received => TgcgColors.info,
      ResultAccountingState.aiReview => TgcgColors.ai,
      ResultAccountingState.conflict => TgcgColors.danger,
      ResultAccountingState.disputed => TgcgColors.warning,
      ResultAccountingState.verified => TgcgColors.success,
    };

IconData _accountingIcon(ResultAccountingState state) => switch (state) {
      ResultAccountingState.missing => Icons.hourglass_empty_rounded,
      ResultAccountingState.received => Icons.inbox_outlined,
      ResultAccountingState.aiReview => Icons.psychology_alt_outlined,
      ResultAccountingState.conflict => Icons.compare_arrows_rounded,
      ResultAccountingState.disputed => Icons.flag_outlined,
      ResultAccountingState.verified => Icons.verified_outlined,
    };

String _aiLabel(ResultAiState state) => switch (state) {
      ResultAiState.clean => 'AI CLEAN',
      ResultAiState.consistent => 'AI CONSISTENT',
      ResultAiState.review => 'AI REVIEW',
      ResultAiState.risk => 'AI RISK',
    };

Color _aiColor(ResultAiState state) => switch (state) {
      ResultAiState.clean => TgcgColors.success,
      ResultAiState.consistent => TgcgColors.info,
      ResultAiState.review => TgcgColors.ai,
      ResultAiState.risk => TgcgColors.danger,
    };

Color _recordStatusColor(RecordStatus status) => switch (status) {
      RecordStatus.verified => TgcgColors.success,
      RecordStatus.disputed => TgcgColors.warning,
      RecordStatus.rejected => TgcgColors.danger,
      RecordStatus.underReview => TgcgColors.ai,
      RecordStatus.submitted => TgcgColors.info,
      RecordStatus.draft => TgcgColors.muted,
      RecordStatus.archived => TgcgColors.muted,
    };

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
