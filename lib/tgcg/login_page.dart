import 'package:flutter/material.dart';

import 'app.dart';
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
  String? selectedZoneId;
  String? selectedStateId;
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
    var scope = GeographicScope.nigeria;

    if (selectedRole == TgcgRole.zonalCoordinator) {
      final zoneId = selectedZoneId ?? membership.geography.zones.first.id;
      scope = membership.geography.zone(zoneId)?.scope ?? scope;
    } else if (selectedRole == TgcgRole.stateCoordinator) {
      final stateId = selectedStateId ?? membership.geography.states.first.id;
      scope = membership.geography.state(stateId)?.scope ?? scope;
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
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: showSignIn ? _formPanel() : _governorPanel(),
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
                    SizedBox(height: 540, child: _governorPanel(compact: true)),
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
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [Color(0xFF0B1F4B), Color(0xFF17377A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
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
                    child: TgcgLogo(size: box.biggest.shortestSide),
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
                'Accreditation, field monitoring, incident management, evidence, result capture, collation and nationwide coordination.',
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
            ],
            const SizedBox(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _Stat('36 + FCT', 'States'),
                _Stat('774', 'LGAs'),
                _Stat('176,846', 'Polling Units'),
              ],
            ),
          ],
        ),
      );

  Widget _governorPanel({bool compact = false}) => Container(
        key: const ValueKey('governor'),
        margin: compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(18, 18, 18, 84),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const RadialGradient(
            center: Alignment(0, -.35),
            radius: .95,
            colors: [TgcgColors.accentSoft, TgcgColors.canvas],
          ),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: EdgeInsets.only(top: compact ? 24 : 40),
              child: Image.asset(
                'assets/brand/governor.png',
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
                filterQuality: FilterQuality.medium,
                semanticLabel: 'Senator Uba Sani, Executive Governor of Kaduna State',
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(compact ? 22 : 36, 70, compact ? 22 : 36, compact ? 22 : 30),
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
                            'Senator Uba Sani',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 20 : 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Executive Governor, Kaduna State',
                            style: TextStyle(
                              color: TgcgColors.accent,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .3,
                            ),
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
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
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
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: TgcgApp.ink,
                  ),
                ),
                const SizedBox(height: 12),
                _roleGrid(),
                if (selectedRole == TgcgRole.zonalCoordinator ||
                    selectedRole == TgcgRole.stateCoordinator) ...[
                  const SizedBox(height: 14),
                  _roleScopeSelector(),
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
                        children: [
                          name,
                          const SizedBox(height: 12),
                          access,
                        ],
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
                  decoration: _decoration(
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
    final geography =
        MembershipOperations.of(context, listen: false).geography;

    if (selectedRole == TgcgRole.zonalCoordinator) {
      final value = selectedZoneId ?? geography.zones.first.id;
      selectedZoneId ??= value;
      return DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Assigned geopolitical zone',
          prefixIcon: Icon(Icons.public_outlined),
        ),
        items: geography.zones
            .map(
              (zone) => DropdownMenuItem(
                value: zone.id,
                child: Text(zone.name),
              ),
            )
            .toList(),
        onChanged: (next) => setState(() => selectedZoneId = next),
      );
    }

    final value = selectedStateId ?? geography.states.first.id;
    selectedStateId ??= value;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Assigned state / FCT',
        prefixIcon: Icon(Icons.map_outlined),
      ),
      items: geography.states
          .map(
            (state) => DropdownMenuItem(
              value: state.id,
              child: Text('${state.name} • ${state.zoneName}'),
            ),
          )
          .toList(),
      onChanged: (next) => setState(() => selectedStateId = next),
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
            children: TgcgRole.values.map((role) {
              final active = role == selectedRole;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() {
                  selectedRole = role;
                  if (role != TgcgRole.zonalCoordinator) selectedZoneId = null;
                  if (role != TgcgRole.stateCoordinator) selectedStateId = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: width,
                  constraints: const BoxConstraints(minHeight: 94),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFFE6EAF2) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: active
                          ? TgcgApp.primary
                          : const Color(0xFFDCDFE6),
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            roleIcon(role),
                            color: active ? TgcgApp.primary : TgcgApp.muted,
                            size: 21,
                          ),
                          const Spacer(),
                          if (active)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: TgcgApp.primary,
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
                          color: active ? TgcgApp.primary : TgcgApp.ink,
                          fontSize: 11.5,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
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
          borderSide: const BorderSide(color: TgcgApp.primary, width: 1.5),
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
          color: Colors.white.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
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
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      );
}
