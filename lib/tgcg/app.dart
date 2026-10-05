import 'dart:async';

import 'package:flutter/material.dart';

import 'access/effective_member_access.dart';
import 'assignments/assignment_store.dart';
import 'assignments/assignment_tracking_store.dart';
import 'communications/bulk_communications_store.dart';
import 'communications/communications_store.dart';
import 'devices/managed_device_store.dart';
import 'field/field_operations_store.dart';
import 'geography/geography_registry.dart';
import 'governance/governance_store.dart';
import 'membership/member_shell.dart';
import 'membership/membership_store.dart';
import 'meeting/operational_call_store.dart';
import 'media/device_media.dart';
import 'offline/offline_persistence.dart';
import 'presentation_access_login.dart';
import 'reports/report_store.dart';
import 'results/result_operations_store.dart';
import 'security/emergency_response_store.dart';
import 'session.dart';
import 'shell.dart';
import 'ui/tgcg_design.dart';

class TgcgApp extends StatefulWidget {
  const TgcgApp({super.key});

  static const Color primary = TgcgColors.primary;
  static const Color accent = TgcgColors.accent;
  static const Color canvas = TgcgColors.canvas;
  static const Color ink = TgcgColors.ink;
  static const Color muted = TgcgColors.muted;

  @override
  State<TgcgApp> createState() => _TgcgAppState();
}

class _TgcgAppState extends State<TgcgApp> {
  late TgcgSessionController sessionController;
  late OfflinePersistenceController offlinePersistenceController;
  late MembershipOperationsController membershipOperationsController;
  late ManagedDeviceController managedDeviceController;
  late AssignmentController assignmentController;
  late AssignmentTrackingController assignmentTrackingController;
  late OperationalCallController operationalCallController;
  late GovernanceOperationsController governanceOperationsController;
  late FieldOperationsController fieldOperationsController;
  late ResultOperationsController resultOperationsController;
  late CommunicationsController communicationsController;
  late BulkCommunicationsController bulkCommunicationsController;
  late ReportOperationsController reportOperationsController;
  late EmergencyResponseController emergencyResponseController;

  @override
  void initState() {
    super.initState();
    _createControllers();
    unawaited(_initializePersistenceAndHydrate());
  }

  Future<void> _initializePersistenceAndHydrate() async {
    await offlinePersistenceController.initialize();
    if (!offlinePersistenceController.isReady) return;

    try {
      await membershipOperationsController.hydrateFromOffline();
      await managedDeviceController.hydrateFromOffline();
      await assignmentController.hydrateFromOffline();
      await operationalCallController.hydrateFromOffline();
    } catch (_) {
      // Keep the prototype-seeded in-memory state available if a persisted
      // record is corrupt or from an incompatible development build.
    }
  }

  void _createControllers() {
    sessionController = TgcgSessionController();
    offlinePersistenceController = OfflinePersistenceController();
    membershipOperationsController = MembershipOperationsController.prototypeSeed(
      GeographyRegistry.prototypeSeed(),
      persistence: offlinePersistenceController,
    );
    managedDeviceController = ManagedDeviceController.prototypeSeed(
      membership: membershipOperationsController,
      persistence: offlinePersistenceController,
    );
    assignmentController = AssignmentController.prototypeSeed(
      membership: membershipOperationsController,
      devices: managedDeviceController,
      persistence: offlinePersistenceController,
    );
    assignmentTrackingController = AssignmentTrackingController(
      assignments: assignmentController,
    );
    operationalCallController = OperationalCallController(
      membership: membershipOperationsController,
      persistence: offlinePersistenceController,
    );
    governanceOperationsController = GovernanceOperationsController.prototypeSeed();
    fieldOperationsController = FieldOperationsController.prototypeSeed(
      persistence: offlinePersistenceController,
    );
    resultOperationsController = ResultOperationsController.prototypeSeed(
      persistence: offlinePersistenceController,
    );
    communicationsController =
        CommunicationsController.prototypeSeed(governanceOperationsController);
    bulkCommunicationsController =
        BulkCommunicationsController.productionFoundation(
      membership: membershipOperationsController,
      devices: managedDeviceController,
      governance: governanceOperationsController,
      persistence: offlinePersistenceController,
    );
    reportOperationsController =
        ReportOperationsController.prototypeSeed(governanceOperationsController);
    emergencyResponseController =
        EmergencyResponseController.prototypeSeed(governanceOperationsController);
  }

  Future<void> _resetPresentation() async {
    final oldSession = sessionController;
    final oldOffline = offlinePersistenceController;
    final oldMembership = membershipOperationsController;
    final oldDevices = managedDeviceController;
    final oldAssignments = assignmentController;
    final oldAssignmentTracking = assignmentTrackingController;
    final oldCalls = operationalCallController;
    final oldGovernance = governanceOperationsController;
    final oldField = fieldOperationsController;
    final oldResults = resultOperationsController;
    final oldCommunications = communicationsController;
    final oldBulkCommunications = bulkCommunicationsController;
    final oldReports = reportOperationsController;
    final oldEmergency = emergencyResponseController;

    try {
      await oldMembership.clearLocalCredentials();
      await oldOffline.clearPresentationData();
    } catch (_) {
      // Recreating all in-memory controllers still restores the presentation
      // even if local persistence is unavailable on this platform.
    }
    await oldOffline.close();
    if (!mounted) return;

    setState(_createControllers);
    unawaited(_initializePersistenceAndHydrate());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldSession.dispose();
      oldField.dispose();
      oldResults.dispose();
      oldAssignmentTracking.dispose();
      oldCalls.dispose();
      oldAssignments.dispose();
      oldDevices.dispose();
      oldMembership.dispose();
      oldCommunications.dispose();
      oldBulkCommunications.dispose();
      oldReports.dispose();
      oldEmergency.dispose();
      oldGovernance.dispose();
      oldOffline.dispose();
    });
  }

  @override
  void dispose() {
    sessionController.dispose();
    fieldOperationsController.dispose();
    resultOperationsController.dispose();
    assignmentTrackingController.dispose();
    operationalCallController.dispose();
    assignmentController.dispose();
    managedDeviceController.dispose();
    membershipOperationsController.dispose();
    communicationsController.dispose();
    bulkCommunicationsController.dispose();
    reportOperationsController.dispose();
    emergencyResponseController.dispose();
    governanceOperationsController.dispose();
    unawaited(offlinePersistenceController.close());
    offlinePersistenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TgcgSession(
        controller: sessionController,
        child: OfflinePersistence(
          controller: offlinePersistenceController,
          child: GovernanceOperations(
            controller: governanceOperationsController,
            child: EmergencyResponse(
              controller: emergencyResponseController,
              child: ReportOperations(
                controller: reportOperationsController,
                child: Communications(
                  controller: communicationsController,
                  child: BulkCommunications(
                    controller: bulkCommunicationsController,
                    child: MembershipOperations(
                      controller: membershipOperationsController,
                      child: ManagedDevices(
                        controller: managedDeviceController,
                        child: Assignments(
                          controller: assignmentController,
                          child: OperationalCalls(
                            controller: operationalCallController,
                            child: AssignmentTracking(
                              controller: assignmentTrackingController,
                              child: FieldOperations(
                                controller: fieldOperationsController,
                                child: ResultOperations(
                                  controller: resultOperationsController,
                                  child: MaterialApp(
                                    navigatorKey: tgcgNavigatorKey,
                                    debugShowCheckedModeBanner: false,
                                    title: 'USESF',
                                    theme: _theme(),
                                    home: _AuthenticationGate(
                                      onResetPresentation: _resetPresentation,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  ThemeData _theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: TgcgColors.primary,
      brightness: Brightness.light,
      primary: TgcgColors.primary,
      secondary: TgcgColors.accent,
      tertiary: TgcgColors.primaryMid,
      surface: TgcgColors.surface,
      error: TgcgColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: TgcgColors.canvas,
      canvasColor: TgcgColors.canvas,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: TgcgColors.ink,
          fontWeight: FontWeight.w900,
          letterSpacing: -.7,
        ),
        headlineMedium: TextStyle(
          color: TgcgColors.ink,
          fontWeight: FontWeight.w900,
          letterSpacing: -.4,
        ),
        titleLarge: TextStyle(
          color: TgcgColors.ink,
          fontWeight: FontWeight.w900,
        ),
        titleMedium: TextStyle(
          color: TgcgColors.ink,
          fontWeight: FontWeight.w800,
        ),
        bodyLarge: TextStyle(color: TgcgColors.ink),
        bodyMedium: TextStyle(color: TgcgColors.ink),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: TgcgColors.primaryDark,
        centerTitle: false,
        iconTheme: IconThemeData(color: TgcgColors.primaryDark),
        titleTextStyle: TextStyle(
          color: TgcgColors.primaryDark,
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: -.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TgcgRadius.lg),
          side: const BorderSide(color: TgcgColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: TgcgColors.border,
        thickness: 1,
        space: 24,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TgcgColors.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        labelStyle: const TextStyle(color: TgcgColors.muted, fontSize: 12),
        hintStyle: const TextStyle(color: Color(0xFF979BA4), fontSize: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          borderSide: const BorderSide(color: TgcgColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          borderSide: const BorderSide(color: TgcgColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          borderSide: const BorderSide(color: TgcgColors.primaryMid, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: TgcgColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgcgRadius.sm)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: .1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: TgcgColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          backgroundColor: TgcgColors.surface,
          side: const BorderSide(color: TgcgColors.borderStrong),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgcgRadius.sm)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: TgcgColors.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? TgcgColors.accent
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(TgcgColors.primaryDark),
        side: const BorderSide(color: TgcgColors.borderStrong, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: TgcgColors.accent,
        linearTrackColor: TgcgColors.primarySoft,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: TgcgColors.accentSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          side: const BorderSide(color: TgcgColors.gold200),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? TgcgColors.primaryDark
                : TgcgColors.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? TgcgColors.primaryDark
                : TgcgColors.muted,
            fontSize: 10.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w900
                : FontWeight.w700,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: TgcgColors.accent,
        foregroundColor: TgcgColors.primaryDark,
        elevation: 2,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: TgcgColors.navy50,
        selectedColor: TgcgColors.accentSoft,
        disabledColor: TgcgColors.surfaceSoft,
        side: const BorderSide(color: TgcgColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        labelStyle: const TextStyle(
          color: TgcgColors.primaryDark,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
        secondaryLabelStyle: const TextStyle(
          color: TgcgColors.primaryDark,
          fontWeight: FontWeight.w900,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: TgcgColors.primaryDark,
        unselectedLabelColor: TgcgColors.muted,
        indicatorColor: TgcgColors.accent,
        dividerColor: TgcgColors.border,
        labelStyle: TextStyle(fontWeight: FontWeight.w900),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: const WidgetStatePropertyAll(TgcgColors.navy50),
        dataRowColor: const WidgetStatePropertyAll(TgcgColors.surface),
        dividerThickness: 1,
        headingTextStyle: const TextStyle(
          color: TgcgColors.primaryDark,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .2,
        ),
        dataTextStyle: const TextStyle(
          color: TgcgColors.ink,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: TgcgColors.border),
          borderRadius: BorderRadius.circular(TgcgRadius.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TgcgRadius.xl),
          side: const BorderSide(color: TgcgColors.border),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: TgcgColors.gold400,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: TgcgColors.primaryDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TgcgColors.accent.withValues(alpha: .18)),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: TgcgColors.primaryDark,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
        ),
      ),
    );
  }
}

class _AuthenticationGate extends StatelessWidget {
  const _AuthenticationGate({required this.onResetPresentation});

  final Future<void> Function() onResetPresentation;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (!session.isAuthenticated) {
      return PresentationAccessLogin(
        key: const ValueKey('presentation-access-login'),
        onResetPresentation: onResetPresentation,
      );
    }
    if (session.role == TgcgRole.member) {
      final membership = MembershipOperations.of(context);
      final member = membership.memberById(session.accessId);
      if (member == null || member.isBlocked) {
        return const MemberShell(key: ValueKey('member-shell'));
      }

      final access = EffectiveMemberAccess.resolve(
        memberId: member.id,
        governance: GovernanceOperations.of(context),
        assignments: Assignments.of(context),
      );
      if (!access.hasOperationalAccess) {
        return const MemberShell(key: ValueKey('member-shell'));
      }
      return const TgcgShell(key: ValueKey('member-operational-shell'));
    }
    return const TgcgShell(key: ValueKey('tgcg-shell'));
  }
}
