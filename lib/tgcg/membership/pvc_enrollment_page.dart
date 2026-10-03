import 'package:flutter/material.dart';

import '../domain/permissions.dart';
import '../geography/geography_registry.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'membership_store.dart';
import 'pvc_recognition_service.dart';

class PvcEnrollmentPage extends StatefulWidget {
  const PvcEnrollmentPage({super.key});

  @override
  State<PvcEnrollmentPage> createState() => _PvcEnrollmentPageState();
}

class _PvcEnrollmentPageState extends State<PvcEnrollmentPage> {
  final _recognizer = PvcRecognitionService();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _voterId = TextEditingController();
  PvcRecognitionResult? _scan;
  bool _reading = false;
  TgcgMember? _created;
  String? _selectedLgaId;
  String? _selectedPollingUnitId;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _voterId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = MembershipOperations.of(context);
    _selectedLgaId ??= store.geography.lgas.first.id;
    final lgaPollingUnits = store.geography.pollingUnits
        .where((unit) => unit.scope.lgaId == _selectedLgaId)
        .toList(growable: false);
    final canManage = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.manageMembership,
    );
    final canAccredit = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.accreditAgents,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'PVC IDENTITY ENROLMENT',
          title: 'Member Enrolment',
          subtitle:
              'Scan a Permanent Voter Card, match its polling-unit code to the canonical registry, confirm the member identity and create the home polling-unit relationship.',
          trailing: TgcgStatusPill(
            label: '${store.members.length} MEMBERS',
            color: TgcgColors.primary,
            icon: Icons.groups_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _Metrics(store: store),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final scanner = _ScannerPanel(
              scan: _scan,
              reading: _reading,
              canManage: canManage,
              onCamera: () => _scanPvc(camera: true),
              onGallery: () => _scanPvc(camera: false),
            );
            final form = _IdentityForm(
              name: _name,
              phone: _phone,
              email: _email,
              voterId: _voterId,
              lgas: store.geography.lgas,
              pollingUnits: lgaPollingUnits,
              selectedLgaId: _selectedLgaId!,
              selectedPollingUnitId: _selectedPollingUnitId,
              onLgaChanged: (value) => setState(() {
                _selectedLgaId = value;
                _selectedPollingUnitId = null;
              }),
              onPollingUnitChanged: (value) =>
                  setState(() => _selectedPollingUnitId = value),
              scan: _scan,
              created: _created,
              enabled: canManage && _scan != null,
              onCreate: () => _createMember(store),
              onReset: _reset,
            );
            if (constraints.maxWidth < 980) {
              return Column(
                children: [scanner, const SizedBox(height: 16), form],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: scanner),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: form),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _RecentMembers(store: store),
        const SizedBox(height: 16),
        _AgentAccreditationPanel(
          store: store,
          canAccredit: canAccredit,
          onAccredit: canAccredit ? () => _accredit(context, store) : null,
        ),
      ],
    );
  }

  Future<void> _scanPvc({required bool camera}) async {
    setState(() {
      _reading = true;
      _created = null;
    });
    try {
      final result = camera
          ? await _recognizer.captureAndRecognize()
          : await _recognizer.pickAndRecognize();
      if (!mounted || result == null) return;
      final store = MembershipOperations.of(context, listen: false);
      final matchedUnit = result.pollingUnitCode == null
          ? null
          : store.geography.pollingUnitByOfficialCode(
                  result.pollingUnitCode!,
                ) ??
              store.geography.pollingUnit(result.pollingUnitCode!);
      setState(() {
        _scan = result;
        _name.text = result.fullName ?? '';
        _voterId.text = result.voterId ?? '';
        if (matchedUnit != null) {
          _selectedLgaId = matchedUnit.scope.lgaId;
          _selectedPollingUnitId = matchedUnit.code;
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PVC scan could not be completed: $error')),
      );
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _createMember(MembershipOperationsController store) {
    if (_scan == null ||
        _name.text.trim().isEmpty ||
        _phone.text.trim().isEmpty ||
        _selectedPollingUnitId == null) {
      return;
    }
    final unit = store.geography.pollingUnit(_selectedPollingUnitId!);
    if (unit == null) return;
    final session = TgcgSession.of(context, listen: false);
    final member = store.createMember(
      fullName: _name.text.trim(),
      phoneNumber: _phone.text.trim(),
      email: _email.text.trim(),
      registrationScope: unit.scope,
      homePollingUnitId: unit.code,
      pvcPollingUnitCode: _scan?.pollingUnitCode,
      linkedBy:
          session.accessId.isEmpty ? session.operatorName : session.accessId,
    );
    setState(() => _created = member);
  }

  void _reset() {
    setState(() {
      _scan = null;
      _created = null;
      _name.clear();
      _phone.clear();
      _email.clear();
      _voterId.clear();
      _selectedPollingUnitId = null;
    });
  }

  Future<void> _accredit(
    BuildContext context,
    MembershipOperationsController store,
  ) async {
    if (store.members.isEmpty || store.geography.pollingUnits.isEmpty) return;
    var memberId = store.members.first.id;
    var scope = store.homePollingUnitForMember(memberId)?.scope ??
        store.geography.pollingUnits.first.scope;
    final phone = TextEditingController(text: store.members.first.phoneNumber);
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Accredit field agent'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: memberId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Member'),
                  items: store.members
                      .map(
                        (member) => DropdownMenuItem(
                          value: member.id,
                          child: Text(
                            '${member.fullName} • ${member.membershipNumber ?? member.id}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    final member = store.memberById(value)!;
                    setDialogState(() {
                      memberId = value;
                      phone.text = member.phoneNumber;
                      scope =
                          store.homePollingUnitForMember(value)?.scope ?? scope;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<GeographicScope>(
                  initialValue: scope,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Polling unit assignment'),
                  items: store.geography.pollingUnits
                      .map(
                        (unit) => DropdownMenuItem(
                          value: unit.scope,
                          child: Text(
                            unit.scope.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => scope = value ?? scope),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phone,
                  decoration:
                      const InputDecoration(labelText: 'Registered phone number'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                store.accredit(
                  memberId: memberId,
                  role: TgcgRole.pollingUnitAgent,
                  scope: scope,
                  phoneNumber: phone.text.trim(),
                );
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.badge_outlined),
              label: const Text('Create accreditation'),
            ),
          ],
        ),
      ),
    );
    phone.dispose();
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agent accreditation created.')),
      );
    }
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.store});
  final MembershipOperationsController store;

  @override
  Widget build(BuildContext context) {
    final approved = store.agents
        .where((a) => a.status == AccreditationStatus.approved)
        .length;
    final pending = store.agents
        .where((a) => a.status == AccreditationStatus.pending)
        .length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 520
                ? 2
                : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            TgcgMetricCard(
              width: width,
              label: 'Members',
              value: '${store.members.length}',
              detail: 'Enrolled identities',
              icon: Icons.groups_outlined,
              tone: TgcgMetricTone.info,
            ),
            TgcgMetricCard(
              width: width,
              label: 'PU linked',
              value: '${store.membersWithHomePollingUnit}',
              detail: '${store.membersWithoutHomePollingUnit} without home PU',
              icon: Icons.location_on_outlined,
              tone: store.membersWithoutHomePollingUnit == 0
                  ? TgcgMetricTone.success
                  : TgcgMetricTone.warning,
            ),
            TgcgMetricCard(
              width: width,
              label: 'Approved',
              value: '$approved',
              detail: 'Cleared accreditations',
              icon: Icons.verified_user_outlined,
              tone: TgcgMetricTone.success,
            ),
            TgcgMetricCard(
              width: width,
              label: 'Pending',
              value: '$pending',
              detail: 'Awaiting review',
              icon: Icons.schedule_outlined,
              tone: TgcgMetricTone.warning,
            ),
          ],
        );
      },
    );
  }
}

class _ScannerPanel extends StatelessWidget {
  const _ScannerPanel({
    required this.scan,
    required this.reading,
    required this.canManage,
    required this.onCamera,
    required this.onGallery,
  });
  final PvcRecognitionResult? scan;
  final bool reading;
  final bool canManage;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'PVC recognition',
        subtitle: 'Capture the card and extract the identity before enrolment.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 220,
              decoration: BoxDecoration(
                gradient: TgcgGradients.navigation,
                borderRadius: BorderRadius.circular(TgcgRadius.lg),
                border: Border.all(
                  color: TgcgColors.accent.withValues(alpha: .18),
                ),
              ),
              child: Center(
                child: reading
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            scan == null
                                ? Icons.credit_card_rounded
                                : Icons.verified_rounded,
                            color: scan == null
                                ? TgcgColors.accent
                                : TgcgColors.success,
                            size: 52,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            scan == null
                                ? 'Scan Permanent Voter Card'
                                : scan!.imageName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (scan != null) ...[
                            const SizedBox(height: 5),
                            Text(
                              scan!.hasRecognizedText
                                  ? 'Identity text recognized'
                                  : 'Card captured',
                              style: const TextStyle(
                                color: TgcgColors.gold200,
                                fontSize: 11,
                              ),
                            ),
                            if (scan!.pollingUnitCode != null) ...[
                              const SizedBox(height: 5),
                              Text(
                                'PU CODE • ${scan!.pollingUnitCode}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canManage && !reading ? onCamera : null,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Scan PVC'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canManage && !reading ? onGallery : null,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Upload image'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _IdentityForm extends StatelessWidget {
  const _IdentityForm({
    required this.name,
    required this.phone,
    required this.email,
    required this.voterId,
    required this.lgas,
    required this.pollingUnits,
    required this.selectedLgaId,
    required this.selectedPollingUnitId,
    required this.onLgaChanged,
    required this.onPollingUnitChanged,
    required this.scan,
    required this.created,
    required this.enabled,
    required this.onCreate,
    required this.onReset,
  });

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController voterId;
  final List<CanonicalLga> lgas;
  final List<CanonicalPollingUnit> pollingUnits;
  final String selectedLgaId;
  final String? selectedPollingUnitId;
  final ValueChanged<String> onLgaChanged;
  final ValueChanged<String?> onPollingUnitChanged;
  final PvcRecognitionResult? scan;
  final TgcgMember? created;
  final bool enabled;
  final VoidCallback onCreate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Confirm identity',
        subtitle:
            'Review the recognized identity and confirm the home polling unit before creating the membership record.',
        child: Column(
          children: [
            TextField(
              controller: name,
              enabled: enabled,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: voterId,
              enabled: enabled,
              decoration: const InputDecoration(labelText: 'PVC / Voter ID'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: selectedLgaId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Registration LGA'),
              items: lgas
                  .map(
                    (lga) => DropdownMenuItem(
                      value: lga.id,
                      child: Text('${lga.name} • ${lga.senatorialDistrictName}'),
                    ),
                  )
                  .toList(),
              onChanged: enabled && created == null
                  ? (value) {
                      if (value != null) onLgaChanged(value);
                    }
                  : null,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('pu-$selectedLgaId-$selectedPollingUnitId'),
              initialValue: pollingUnits.any(
                (unit) => unit.code == selectedPollingUnitId,
              )
                  ? selectedPollingUnitId
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Home polling unit',
                helperText: scan?.pollingUnitCode == null
                    ? 'Select the member polling unit'
                    : 'PVC code detected: ${scan!.pollingUnitCode}',
                prefixIcon: const Icon(Icons.location_on_outlined),
              ),
              items: pollingUnits
                  .map(
                    (unit) => DropdownMenuItem(
                      value: unit.code,
                      child: Text(
                        '${unit.displayCode} • ${unit.scope.pollingUnitName ?? unit.scope.label}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: enabled && created == null
                  ? onPollingUnitChanged
                  : null,
            ),
            if (scan?.pollingUnitCode != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TgcgStatusPill(
                  label: selectedPollingUnitId == null
                      ? 'PVC PU CODE NOT YET MATCHED'
                      : 'PVC PU MATCHED',
                  color: selectedPollingUnitId == null
                      ? TgcgColors.warning
                      : TgcgColors.success,
                  icon: selectedPollingUnitId == null
                      ? Icons.manage_search_rounded
                      : Icons.verified_outlined,
                  compact: true,
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              enabled: enabled,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: email,
              enabled: enabled,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
            ),
            if (scan?.rawText.trim().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'Recognized PVC text',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      scan!.rawText,
                      style: const TextStyle(
                        fontSize: 11,
                        color: TgcgColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: enabled &&
                            created == null &&
                            selectedPollingUnitId != null
                        ? onCreate
                        : null,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Create member'),
                  ),
                ),
                if (created != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReset,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Next enrolment'),
                    ),
                  ),
                ],
              ],
            ),
            if (created != null) ...[
              const SizedBox(height: 12),
              TgcgStatusPill(
                label: created!.membershipNumber ?? created!.id,
                color: TgcgColors.success,
                icon: Icons.verified_rounded,
              ),
            ],
          ],
        ),
      );
}

class _RecentMembers extends StatelessWidget {
  const _RecentMembers({required this.store});
  final MembershipOperationsController store;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Member registry',
        subtitle: 'Recently enrolled USESF identities.',
        child: Column(
          children: store.members.take(6).map((member) {
            final scope = store.registrationScopeForMember(member.id);
            final homePu = store.homePollingUnitForMember(member.id);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(
                  member.fullName.isEmpty
                      ? '?'
                      : member.fullName[0].toUpperCase(),
                ),
              ),
              title: Text(
                member.fullName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                homePu == null
                    ? '${member.membershipNumber ?? member.id} • ${scope?.label ?? 'Kaduna State'} • ${member.phoneNumber}'
                    : '${member.membershipNumber ?? member.id} • HOME PU: ${homePu.displayCode}\n'
                        '${homePu.scope.label} • ${member.phoneNumber}',
              ),
              isThreeLine: homePu != null,
              trailing: TgcgStatusPill(
                label: member.status.name.toUpperCase(),
                color: member.status == RecordStatus.verified
                    ? TgcgColors.success
                    : TgcgColors.info,
                compact: true,
              ),
            );
          }).toList(),
        ),
      );
}

class _AgentAccreditationPanel extends StatelessWidget {
  const _AgentAccreditationPanel({
    required this.store,
    required this.canAccredit,
    required this.onAccredit,
  });
  final MembershipOperationsController store;
  final bool canAccredit;
  final VoidCallback? onAccredit;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Agent accreditation',
        subtitle:
            'Convert enrolled members into geographically assigned field agents.',
        trailing: canAccredit
            ? FilledButton.icon(
                onPressed: onAccredit,
                icon: const Icon(Icons.badge_outlined),
                label: const Text('Accredit agent'),
              )
            : null,
        child: Column(
          children: store.agents.map((agent) {
            final member = store.memberById(agent.memberId);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
              title: Text(
                member?.fullName ?? agent.agentId,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('${agent.agentId} • ${agent.scope.label}'),
              trailing: TgcgStatusPill(
                label: agent.status.name.toUpperCase(),
                color: agent.status == AccreditationStatus.approved
                    ? TgcgColors.success
                    : TgcgColors.warning,
                compact: true,
              ),
            );
          }).toList(),
        ),
      );
}
