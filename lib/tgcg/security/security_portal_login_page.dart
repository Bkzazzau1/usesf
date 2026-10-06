// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../geography/geography_registry.dart';
import '../geography/kaduna_map.dart';
import '../governance/governance_store.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'emergency_response_store.dart';

/// Restricted sign-in for accredited security and emergency agency personnel.
/// Officers land in the agency-only Security Response workspace and only see dispatches assigned to
/// their own agency within their command area.
class SecurityPortalLoginPage extends StatefulWidget {
  const SecurityPortalLoginPage({super.key});

  @override
  State<SecurityPortalLoginPage> createState() =>
      _SecurityPortalLoginPageState();
}

class _SecurityPortalLoginPageState extends State<SecurityPortalLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _serviceNumber = TextEditingController();
  final _accessCode = TextEditingController();

  String? _agencyId;
  String _commandId = _stateCommand;
  bool _obscure = true;
  bool _signingIn = false;

  static const _stateCommand = 'KD';

  @override
  void dispose() {
    _serviceNumber.dispose();
    _accessCode.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_signingIn) return;
    if (_agencyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select your agency to continue.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final emergency = EmergencyResponse.of(context, listen: false);
    final geography = MembershipOperations.of(context, listen: false).geography;
    final agency = emergency.agencyById(_agencyId!);
    if (agency == null || !agency.active) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This response agency is unavailable.')),
      );
      return;
    }
    final scope = _commandId == _stateCommand
        ? GeographicScope.kaduna
        : geography.lga(_commandId)?.scope ?? GeographicScope.kaduna;
    final serviceNumber = _serviceNumber.text.trim().toUpperCase();

    setState(() => _signingIn = true);
    try {
      final authentication =
          await emergency.authenticateResponderCredential(
        agencyId: agency.id,
        serviceNumber: serviceNumber,
        accessCode: _accessCode.text,
        requestedScope: scope,
      );
      if (!context.mounted) return;

      final governance = GovernanceOperations.of(context, listen: false);
      final responder = authentication.responder;
      if (authentication.status !=
              ResponderAuthenticationStatus.authenticated ||
          responder == null) {
        final locked =
            authentication.status == ResponderAuthenticationStatus.locked;
        governance.recordAudit(
          actorId: serviceNumber,
          action: locked
              ? 'security_portal_sign_in_locked'
              : 'security_portal_sign_in_rejected',
          entityType: 'emergency_agency',
          entityId: agency.id,
          detail: locked
              ? 'Security portal sign-in temporarily locked after repeated failed credentials for ${agency.shortName} within ${scope.label}.'
              : 'Rejected security portal sign-in for ${agency.shortName} within ${scope.label}.',
          scope: scope,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              locked
                  ? 'Too many failed attempts. Security Portal access is temporarily locked.'
                  : 'Invalid responder credential or unauthorized command area.',
            ),
          ),
        );
        return;
      }

      governance.recordAudit(
        actorId: responder.serviceNumber,
        action: 'security_portal_sign_in',
        entityType: 'emergency_responder',
        entityId: responder.id,
        detail:
            '${responder.displayName} (${agency.shortName}) signed in for ${scope.label}.',
        scope: scope,
      );

      Navigator.of(context).pop();
      TgcgSession.of(context, listen: false).signIn(
        role: TgcgRole.securityOfficer,
        operatorName: responder.displayName,
        accessId: responder.serviceNumber,
        scope: scope,
        agencyId: agency.id,
        securitySessionToken: authentication.remoteSessionToken,
        securitySessionExpiresAt: authentication.remoteSessionExpiresAt,
      );
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emergency = EmergencyResponse.of(context);
    final geography = MembershipOperations.of(context).geography;
    final agencies = emergency.agenciesForScope(GeographicScope.kaduna);

    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final form = _form(agencies, geography.lgas);
            if (constraints.maxWidth < 960) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const _PortalBrandPanel(compact: true),
                  const SizedBox(height: 16),
                  form,
                ],
              );
            }
            return Row(
              children: [
                const Expanded(flex: 10, child: _PortalBrandPanel()),
                Expanded(
                  flex: 13,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const KadunaMapBackdrop(),
                      Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 30,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: form,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _form(List<EmergencyAgency> agencies, List<CanonicalLga> lgas) => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Back to staff sign-in'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Security Agency Sign-in',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: TgcgColors.ink,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'For accredited security and emergency personnel responding to incidents dispatched by the USESF Situation Room.',
          style: TextStyle(color: TgcgColors.muted, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 22),
        const Text(
          'Agency',
          style: TextStyle(fontWeight: FontWeight.w900, color: TgcgColors.ink),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 600 ? 3 : 2;
            const gap = 10.0;
            final width = (box.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: agencies
                  .map(
                    (agency) => _AgencyCard(
                      width: width,
                      agency: agency,
                      selected: agency.id == _agencyId,
                      onTap: () => setState(() => _agencyId = agency.id),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          key: ValueKey(_commandId),
          initialValue: _commandId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Command area',
            prefixIcon: Icon(Icons.location_city_outlined),
          ),
          items: [
            const DropdownMenuItem(
              value: _stateCommand,
              child: Text('Kaduna State Command • all 23 LGAs'),
            ),
            ...lgas.map(
              (lga) => DropdownMenuItem<String>(
                value: lga.id,
                child: Text('${lga.name} LGA • ${lga.senatorialDistrictName}'),
              ),
            ),
          ],
          onChanged: (value) =>
              setState(() => _commandId = value ?? _stateCommand),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _serviceNumber,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Service / force number',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          validator: (value) => (value ?? '').trim().length < 4
              ? 'Enter a valid service number'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _accessCode,
          obscureText: _obscure,
          onFieldSubmitted: (_) => _signIn(),
          decoration: InputDecoration(
            labelText: 'Portal access code',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show code' : 'Hide code',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          validator: (value) => (value ?? '').length < 8
              ? 'Access code must be at least 8 characters'
              : null,
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _signingIn ? null : _signIn,
            icon: _signingIn
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.shield_outlined),
            label: Text(
              _signingIn ? 'Verifying credential...' : 'Enter Security Portal',
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 17),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Row(
          children: [
            Icon(Icons.policy_outlined, size: 16, color: TgcgColors.muted),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Restricted system. Every sign-in and response update is recorded in the audit trail.',
                style: TextStyle(color: TgcgColors.muted, fontSize: 11),
              ),
            ),
          ],
        ),

      ],
    ),
  );
}

class _PortalBrandPanel extends StatelessWidget {
  const _PortalBrandPanel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.all(compact ? 0 : 18),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      gradient: TgcgGradients.brand,
      borderRadius: BorderRadius.circular(TgcgRadius.hero),
      image: const DecorationImage(
        image: AssetImage('assets/brand/governor.png'),
        fit: BoxFit.cover,
        alignment: Alignment(0, -.4),
        opacity: .5,
        filterQuality: FilterQuality.medium,
      ),
    ),
    // Navy wash over the photo keeps the logo and copy legible.
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .3, .62, 1],
          colors: [
            TgcgColors.navy950.withValues(alpha: .82),
            TgcgColors.navy950.withValues(alpha: .25),
            TgcgColors.navy950.withValues(alpha: .55),
            TgcgColors.navy950.withValues(alpha: .96),
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 24 : 42),
        child: _content(),
      ),
    ),
  );

  Widget _content() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          TgcgLogo(size: compact ? 52 : 64),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'USESF',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  'Kaduna State',
                  style: TextStyle(color: TgcgColors.gold400, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      if (compact)
        const SizedBox(height: 20)
      else
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: LayoutBuilder(
              builder: (context, box) =>
                  Center(child: TgcgLogo(size: box.biggest.shortestSide)),
            ),
          ),
        ),
      Container(
        width: compact ? 44 : 60,
        height: compact ? 44 : 60,
        decoration: BoxDecoration(
          color: TgcgColors.accent.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          border: Border.all(color: TgcgColors.accent.withValues(alpha: .5)),
        ),
        child: Icon(
          Icons.local_police_rounded,
          color: TgcgColors.accent,
          size: compact ? 24 : 32,
        ),
      ),
      SizedBox(height: compact ? 12 : 18),
      Text(
        'Security Portal',
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 24 : 34,
          fontWeight: FontWeight.w900,
          height: 1.05,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Receive dispatches, confirm deployment and report on-scene status to the Situation Room in real time.',
        style: TextStyle(color: Colors.white70, height: 1.5),
      ),
      if (!compact) ...[
        const SizedBox(height: 22),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PortalChip(Icons.notifications_active_outlined, 'Live dispatches'),
            _PortalChip(Icons.route_outlined, 'Response tracking'),
            _PortalChip(Icons.fact_check_outlined, 'Audited actions'),
          ],
        ),
      ],
    ],
  );
}

class _PortalChip extends StatelessWidget {
  const _PortalChip(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(TgcgRadius.sm),
      border: Border.all(color: Colors.white12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: TgcgColors.gold400),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _AgencyCard extends StatelessWidget {
  const _AgencyCard({
    required this.width,
    required this.agency,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final EmergencyAgency agency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TgcgRadius.md),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? TgcgColors.primarySoft : TgcgColors.surface,
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          border: Border.all(
            color: selected ? TgcgColors.primary : TgcgColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  agencyIcon(agency.type),
                  color: TgcgColors.primary,
                  size: 20,
                ),
                const Spacer(),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: TgcgColors.primary,
                    size: 18,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              agency.shortName,
              style: const TextStyle(
                color: TgcgColors.ink,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              agency.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: TgcgColors.muted, fontSize: 10),
            ),
          ],
        ),
      ),
    ),
  );
}

IconData agencyIcon(EmergencyAgencyType type) => switch (type) {
  EmergencyAgencyType.police => Icons.local_police_rounded,
  EmergencyAgencyType.civilDefence => Icons.shield_rounded,
  EmergencyAgencyType.roadSafety => Icons.traffic_rounded,
  EmergencyAgencyType.fireRescue => Icons.local_fire_department_rounded,
  EmergencyAgencyType.medical => Icons.medical_services_rounded,
  EmergencyAgencyType.other => Icons.support_rounded,
};
