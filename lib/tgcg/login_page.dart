import 'package:flutter/material.dart';

import 'app.dart';
import 'geography/kaduna_map.dart';
import 'membership/membership_store.dart';
import 'session.dart';
import 'ui/tgcg_design.dart';

class TgcgLoginPage extends StatefulWidget {
  const TgcgLoginPage({super.key});

  @override
  State<TgcgLoginPage> createState() => _TgcgLoginPageState();
}

class _TgcgLoginPageState extends State<TgcgLoginPage> {
  final nameController = TextEditingController();
  final accessIdController = TextEditingController();
  final passwordController = TextEditingController();

  TgcgRole selectedRole = TgcgRole.situationRoomDirector;
  String? selectedDistrictId;
  bool obscurePassword = true;
  bool rememberDevice = true;
  bool showSignIn = false;

  @override
  void dispose() {
    nameController.dispose();
    accessIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _signIn() {
    final membership = MembershipOperations.of(context, listen: false);
    var scope = GeographicScope.kaduna;
    if (selectedRole == TgcgRole.senatorialCoordinator) {
      final districts = membership.geography.senatorialDistricts;
      final districtId = selectedDistrictId ?? districts.first.id;
      scope =
          membership.geography.senatorialDistrict(districtId)?.scope ?? scope;
    }

    TgcgSession.of(context, listen: false).signIn(
      role: selectedRole,
      operatorName: nameController.text,
      accessId: accessIdController.text,
      scope: scope,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TgcgColors.canvas,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          if (wide) {
            return Row(
              children: [
                Expanded(flex: 10, child: _brandPanel()),
                Expanded(
                  flex: 13,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const KadunaMapBackdrop(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: showSignIn ? _formPanel() : _mapPanel(),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              SizedBox(height: 300, child: _brandPanel(compact: true)),
              const SizedBox(height: 18),
              if (showSignIn)
                _formPanel(compact: true)
              else
                SizedBox(height: 540, child: _mapPanel(compact: true)),
            ],
          );
        },
      ),
    ),
  );

  static const _fullName = 'Uba Sani Engagement & Sensitization Forum';
  static const _motto = 'Engage • Sensitize • Empower • Transform';

  Widget _brandPanel({bool compact = false}) => Container(
    margin: EdgeInsets.all(compact ? 0 : 18),
    padding: EdgeInsets.all(compact ? 24 : 42),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(TgcgRadius.hero),
      gradient: TgcgGradients.brand,
      border: Border.all(color: TgcgColors.accent.withValues(alpha: .22)),
      boxShadow: TgcgShadows.elevated,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact)
          const Row(
            children: [
              TgcgLogo(size: 64),
              SizedBox(width: 12),
              Text(
                'USESF',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          )
        else
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: TgcgColors.accent.withValues(alpha: .16),
                        blurRadius: 60,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: TgcgLogo(size: box.biggest.shortestSide),
                ),
              ),
            ),
          ),
        if (compact) const Spacer() else const SizedBox(height: 28),
        Text(
          _fullName,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 22 : 29,
            height: 1.1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          _motto,
          style: TextStyle(
            color: TgcgColors.accent,
            fontWeight: FontWeight.w800,
            letterSpacing: .4,
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 10),
          const Text(
            'Member operations, field monitoring, incident management, evidence, result capture, collation and coordination across all 23 LGAs of Kaduna State.',
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
        ],
        const SizedBox(height: 22),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _Stat('3', 'Senatorial Zones'),
            _Stat('23', 'LGAs'),
            _Stat('255', 'Wards'),
            _Stat('8,012', 'Polling Units'),
          ],
        ),
      ],
    ),
  );

  Widget _mapPanel({bool compact = false}) => Container(
    key: const ValueKey('kaduna-map'),
    margin: compact
        ? EdgeInsets.zero
        : const EdgeInsets.fromLTRB(18, 18, 18, 84),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(TgcgRadius.hero),
      gradient: const RadialGradient(
        center: Alignment(0, -.42),
        radius: 1.05,
        colors: [Color(0xFFFFF8E7), TgcgColors.surface, TgcgColors.navy100],
        stops: [0, .52, 1],
      ),
      border: Border.all(color: TgcgColors.gold200),
      boxShadow: TgcgShadows.soft,
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        // Display-only map: no tap handler, so LGAs are not selectable here.
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 32,
            compact ? 16 : 28,
            compact ? 16 : 32,
            compact ? 110 : 130,
          ),
          child: const Center(child: KadunaMap()),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              compact ? 22 : 36,
              70,
              compact ? 22 : 36,
              compact ? 22 : 30,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  TgcgColors.primaryDark.withValues(alpha: 0),
                  TgcgColors.primaryDark.withValues(alpha: .85),
                  TgcgColors.primaryDark,
                ],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Kaduna State',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 20 : 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '23 LGAs across 3 senatorial zones',
                        style: TextStyle(
                          color: TgcgColors.accent,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          _ZoneKey('SD/052/KD', 'Kaduna North'),
                          _ZoneKey('SD/053/KD', 'Kaduna Central'),
                          _ZoneKey('SD/054/KD', 'Kaduna South'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: () => setState(() => showSignIn = true),
                  style: FilledButton.styleFrom(
                    backgroundColor: TgcgColors.accent,
                    foregroundColor: TgcgColors.primaryDark,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 16,
                    ),
                    side: const BorderSide(color: TgcgColors.gold400),
                  ),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Sign in'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _formPanel({bool compact = false}) => Center(
    key: const ValueKey('form'),
    child: SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 48,
        vertical: compact ? 8 : 30,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => showSignIn = false),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Back'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Secure Operations Access',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: TgcgApp.ink,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Sign in to your assigned operational workspace.',
              style: TextStyle(color: TgcgApp.muted, fontSize: 13),
            ),
            const SizedBox(height: 24),
            const Text(
              'Operational role',
              style: TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink),
            ),
            const SizedBox(height: 12),
            _roleGrid(),
            if (selectedRole == TgcgRole.senatorialCoordinator) ...[
              const SizedBox(height: 14),
              _roleScopeSelector(),
            ],
            if (selectedRole == TgcgRole.securityOfficer) ...[
              const SizedBox(height: 14),
              _agencySelector(),
            ],
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final stack = constraints.maxWidth < 540;
                final name = TextField(
                  controller: nameController,
                  decoration: _decoration(
                    'Operator name',
                    'Enter name',
                    Icons.person_outline_rounded,
                  ),
                );
                final access = TextField(
                  controller: accessIdController,
                  decoration: _decoration(
                    'Access ID / phone',
                    'Enter access ID',
                    Icons.badge_outlined,
                  ),
                );
                if (stack) {
                  return Column(
                    children: [name, const SizedBox(height: 12), access],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: name),
                    const SizedBox(width: 12),
                    Expanded(child: access),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: obscurePassword,
              onSubmitted: (_) => _signIn(),
              decoration:
                  _decoration(
                    'Password',
                    'Enter password',
                    Icons.lock_outline_rounded,
                  ).copyWith(
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => obscurePassword = !obscurePassword),
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: rememberDevice,
                  onChanged: (value) =>
                      setState(() => rememberDevice = value ?? false),
                ),
                const Text(
                  'Remember this device',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {},
                  child: const Text('Access support'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: _signIn,
                icon: const Icon(Icons.login_rounded),
                label: Text('Enter as ${roleLabel(selectedRole)}'),
                style: FilledButton.styleFrom(
                  backgroundColor: TgcgApp.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _roleScopeSelector() {
    final districts = MembershipOperations.of(
      context,
      listen: false,
    ).geography.senatorialDistricts;
    final value = selectedDistrictId ?? districts.first.id;
    selectedDistrictId ??= value;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Assigned senatorial zone',
        prefixIcon: Icon(Icons.hub_outlined),
      ),
      items: districts
          .map(
            (district) => DropdownMenuItem(
              value: district.id,
              child: Text(
                '${district.name} • ${district.lgaSlugs.length} LGAs',
              ),
            ),
          )
          .toList(),
      onChanged: (next) => setState(() => selectedDistrictId = next),
    );
  }

  Widget _roleGrid() => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth > 680
          ? 4
          : constraints.maxWidth > 430
          ? 3
          : 2;
      const gap = 9.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: TgcgRole.values
            .where(
              (role) =>
                  role != TgcgRole.member &&
                  role != TgcgRole.stateAdministrator &&
                  role != TgcgRole.securityOfficer,
            )
            .map((role) {
              final active = role == selectedRole;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() {
                  selectedRole = role;
                  if (role != TgcgRole.senatorialCoordinator) {
                    selectedDistrictId = null;
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: width,
                  constraints: const BoxConstraints(minHeight: 94),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: active ? TgcgColors.accentSoft : Colors.white,
                    borderRadius: BorderRadius.circular(TgcgRadius.md),
                    border: Border.all(
                      color: active ? TgcgColors.accent : TgcgColors.border,
                      width: active ? 1.6 : 1,
                    ),
                    boxShadow: active
                        ? const [
                            BoxShadow(
                              color: Color(0x12A97812),
                              blurRadius: 16,
                              offset: Offset(0, 5),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            roleIcon(role),
                            color: active
                                ? TgcgColors.primaryDark
                                : TgcgApp.muted,
                            size: 21,
                          ),
                          const Spacer(),
                          if (active)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: TgcgColors.accentStrong,
                              size: 18,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        roleLabel(role),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? TgcgColors.primaryDark : TgcgApp.ink,
                          fontSize: 11.5,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            })
            .toList(),
      );
    },
  );

  InputDecoration _decoration(String label, String hint, IconData icon) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDCDFE6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: TgcgColors.accentStrong,
            width: 1.6,
          ),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: TgcgColors.accent.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(TgcgRadius.sm),
      border: Border.all(color: TgcgColors.accent.withValues(alpha: .16)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: TgcgColors.gold200,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Colour key for a senatorial zone on the login map.
class _ZoneKey extends StatelessWidget {
  const _ZoneKey(this.districtCode, this.label);

  final String districtCode;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: kadunaZoneColors[districtCode],
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
}
