import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import 'assignment_store.dart';

class AssignmentTrackingController extends ChangeNotifier {
  AssignmentTrackingController({
    required AssignmentController assignments,
  }) : _assignments = assignments;

  final AssignmentController _assignments;

  StreamSubscription<Position>? _subscription;
  String? _assignmentId;
  String? _deviceId;
  DateTime? _lastAcceptedAt;
  String? _lastError;
  bool _starting = false;

  bool get isTracking => _subscription != null;
  bool get isStarting => _starting;
  String? get assignmentId => _assignmentId;
  String? get deviceId => _deviceId;
  String? get lastError => _lastError;

  bool isTrackingAssignment(String assignmentId) =>
      isTracking && _assignmentId == assignmentId;

  Future<void> start({
    required String assignmentId,
    required String deviceId,
  }) async {
    if (_starting) return;
    if (isTrackingAssignment(assignmentId) && _deviceId == deviceId) return;

    final assignment = _assignments.assignmentById(assignmentId);
    if (assignment == null) {
      throw ArgumentError('Unknown assignment: $assignmentId');
    }
    if (assignment.isTerminal) {
      throw StateError('A closed assignment cannot start GPS tracking.');
    }
    if (assignment.deviceId != null && assignment.deviceId != deviceId) {
      throw StateError(
        'This assignment is bound to a different managed device.',
      );
    }

    _starting = true;
    _lastError = null;
    notifyListeners();
    try {
      await _ensureLocationPermission();
      await _subscription?.cancel();

      _assignmentId = assignmentId;
      _deviceId = deviceId;
      _lastAcceptedAt = null;

      _subscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 20,
        ),
      ).listen(
        _handlePosition,
        onError: (Object error) {
          _lastError = error.toString();
          notifyListeners();
        },
      );
      notifyListeners();
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _assignmentId = null;
    _deviceId = null;
    _lastAcceptedAt = null;
    notifyListeners();
  }

  Future<void> _handlePosition(Position position) async {
    final assignmentId = _assignmentId;
    final deviceId = _deviceId;
    if (assignmentId == null || deviceId == null) return;

    final assignment = _assignments.assignmentById(assignmentId);
    if (assignment == null || assignment.isTerminal) {
      await stop();
      return;
    }

    final capturedAt = position.timestamp.toUtc();
    final previous = _lastAcceptedAt;
    final isMoving = position.speed.isFinite && position.speed >= 0.5;
    final minimumInterval =
        isMoving ? const Duration(minutes: 1) : const Duration(minutes: 5);

    if (previous != null &&
        capturedAt.difference(previous).abs() < minimumInterval) {
      return;
    }

    _lastAcceptedAt = capturedAt;
    _assignments.recordLocationHeartbeat(
      assignmentId: assignmentId,
      deviceId: deviceId,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      capturedAt: capturedAt,
    );
  }

  Future<void> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError('Location services are disabled on this device.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw StateError('Location permission was not granted.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError(
        'Location permission is permanently disabled for USESF.',
      );
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

class AssignmentTracking
    extends InheritedNotifier<AssignmentTrackingController> {
  const AssignmentTracking({
    super.key,
    required AssignmentTrackingController controller,
    required super.child,
  }) : super(notifier: controller);

  static AssignmentTrackingController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value =
          context.dependOnInheritedWidgetOfExactType<AssignmentTracking>();
      assert(value != null, 'AssignmentTracking is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<AssignmentTracking>();
    final value = element?.widget as AssignmentTracking?;
    assert(value != null, 'AssignmentTracking is missing above this context.');
    return value!.notifier!;
  }
}
