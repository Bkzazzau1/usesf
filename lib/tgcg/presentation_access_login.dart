import 'package:flutter/material.dart';

import 'login_page.dart';
import 'membership/member_access_page.dart';
import 'membership/self_registration_page.dart';
import 'security/security_portal_login_page.dart';
import 'ui/tgcg_design.dart';

class PresentationAccessLogin extends StatefulWidget {
  const PresentationAccessLogin({
    super.key,
    required this.onResetPresentation,
  });

  final Future<void> Function() onResetPresentation;

  @override
  State<PresentationAccessLogin> createState() => _PresentationAccessLoginState();
}

class _PresentationAccessLoginState extends State<PresentationAccessLogin> {
  bool resetting = false;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          const Positioned.fill(child: TgcgLoginPage()),
          Positioned(
            right: 18,
            bottom: 18,
            child: SafeArea(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  Material(
                    elevation: 8,
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: FilledButton.icon(
                      onPressed: resetting
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const MemberAccessPage(),
                                ),
                              ),
                      icon: const Icon(Icons.person_pin_circle_outlined),
                      label: const Text('Member Access'),
                      style: FilledButton.styleFrom(
                        backgroundColor: TgcgColors.primaryMid,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        side: const BorderSide(color: TgcgColors.navy700),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(TgcgRadius.md),
                        ),
                      ),
                    ),
                  ),
                  Material(
                    elevation: 8,
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: FilledButton.icon(
                      onPressed: resetting
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const SelfRegistrationPage(),
                                ),
                              ),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Register as Member'),
                      style: FilledButton.styleFrom(
                        backgroundColor: TgcgColors.accent,
                        foregroundColor: TgcgColors.primaryDark,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        side: const BorderSide(color: TgcgColors.gold400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(TgcgRadius.md),
                        ),
                      ),
                    ),
                  ),
                  Material(
                    elevation: 4,
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: OutlinedButton.icon(
                      onPressed: resetting ? null : () => _reset(context),
                      icon: resetting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.restart_alt_rounded),
                      label: Text(
                        resetting ? 'Restoring...' : 'Reset Presentation',
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: TgcgColors.surface.withValues(alpha: .96),
                        foregroundColor: TgcgColors.primaryDark,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        side: const BorderSide(color: TgcgColors.gold200),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(TgcgRadius.md),
                        ),
                      ),
                    ),
                  ),
                  Material(
                    elevation: 8,
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: FilledButton.icon(
                      onPressed: resetting
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const SecurityPortalLoginPage(),
                                ),
                              ),
                      icon: const Icon(Icons.local_police_rounded),
                      label: const Text('Security Portal'),
                      style: FilledButton.styleFrom(
                        backgroundColor: TgcgColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        side: const BorderSide(color: TgcgColors.navy700),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(TgcgRadius.md),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Future<void> _reset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset presentation?'),
        content: const Text(
          'Restore the original presentation data and clear actions made during this run?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => resetting = true);
    try {
      await widget.onResetPresentation();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Presentation restored and ready.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to reset presentation data.')),
      );
    } finally {
      if (mounted) setState(() => resetting = false);
    }
  }

}
