import 'package:flutter/widgets.dart';

import '../domain/models.dart';
import '../geography/geography_registry.dart';
import '../membership/membership_store.dart';
import '../offline/offline_persistence.dart';

enum ManagedDeviceStatus {
  available,
  assigned,
  maintenance,
  revoked,
}

class ManagedDevice {
  const ManagedDevice({
    required this.id,
    required this.label,
    required this.status,
    required this.registeredAt,
    this.serialReference,
    this.imeiReference,
    this.assignedMemberId,
    this.assignedAt,
    this.lastSeenAt,
    this.lastLatitude,
    this.lastLongitude,
    this.lastAccuracyMeters,
    this.batteryPercent,
    this.appVersion,
    this.syncState,
  });

  final String id;
  final String label;
  final ManagedDeviceStatus status;
  final DateTime registeredAt;
  final String? serialReference;
  final String? imeiReference;
  final String? assignedMemberId;
  final DateTime? assignedAt;
  final DateTime? lastSeenAt;
  final double? lastLatitude;
  final double? lastLongitude;
  final double? lastAccuracyMeters;
  final int? batteryPercent;
  final String? appVersion;
  final String? syncState;

  bool get isOperational =>
      status == ManagedDeviceStatus.available ||
      status == ManagedDeviceStatus.assigned;

  bool get hasLocation =>
      lastLatitude != null && lastLongitude != null;

  ManagedDevice copyWith({
    String? label,
    ManagedDeviceStatus? status,
    String? serialReference,
    String? imeiReference,
    String? assignedMemberId,
    bool clearAssignedMember = false,
    DateTime? assignedAt,
    bool clearAssignedAt = false,
    DateTime? lastSeenAt,
    double? lastLatitude,
    double? lastLongitude,
    double? lastAccuracyMeters,
    int? batteryPercent,
    String? appVersion,
    String? syncState,
  }) =>
      ManagedDevice(
        id: id,
        label: label ?? this.label,
        status: status ?? this.status,
        registeredAt: registeredAt,
        serialReference: serialReference ?? this.serialReference,
        imeiReference: imeiReference ?? this.imeiReference,
        assignedMemberId:
            clearAssignedMember ? null : assignedMemberId ?? this.assignedMemberId,
        assignedAt: clearAssignedAt ? null : assignedAt ?? this.assignedAt,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        lastLatitude: lastLatitude ?? this.lastLatitude,
        lastLongitude: lastLongitude ?? this.lastLongitude,
        lastAccuracyMeters: lastAccuracyMeters ?? this.lastAccuracyMeters,
        batteryPercent: batteryPercent ?? this.batteryPercent,
        appVersion: appVersion ?? this.appVersion,
        syncState: syncState ?? this.syncState,
      );
}

class ManagedDeviceController extends ChangeNotifier {
  ManagedDeviceController({
    required MembershipOperationsController membership,
    required OfflinePersistenceController persistence,
    List<ManagedDevice> devices = const [],
  })  : _membership = membership,
        _persistence = persistence,
        _devices = List<ManagedDevice>.of(devices);

  factory ManagedDeviceController.prototypeSeed({
    required MembershipOperationsController membership,
    required OfflinePersistenceController persistence,
  }) {
    final now = DateTime.utc(2026, 9, 27, 8);
    final devices = <ManagedDevice>[];

    for (final agent in membership.agents) {
      final deviceId = agent.deviceId;
      if (deviceId == null || deviceId.trim().isEmpty) continue;
      if (devices.any((item) => item.id == deviceId)) continue;
      devices.add(
        ManagedDevice(
          id: deviceId,
          label: 'USESF Field Phone • ${agent.agentId}',
          status: ManagedDeviceStatus.assigned,
          registeredAt: now.subtract(const Duration(days: 15)),
          assignedMemberId: agent.memberId,
          assignedAt: now.subtract(const Duration(days: 14)),
          appVersion: '0.1.0',
          syncState: 'prototype',
        ),
      );
    }

    return ManagedDeviceController(
      membership: membership,
      persistence: persistence,
      devices: devices,
    );
  }

  final MembershipOperationsController _membership;
  final OfflinePersistenceController _persistence;
  final List<ManagedDevice> _devices;

  List<ManagedDevice> get devices => List.unmodifiable(_devices);

  ManagedDevice? deviceById(String id) {
    for (final device in _devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  ManagedDevice? deviceForMember(String memberId) {
    for (final device in _devices) {
      if (device.assignedMemberId == memberId &&
          device.status == ManagedDeviceStatus.assigned) {
        return device;
      }
    }
    return null;
  }

  int get assignedCount => _devices
      .where((item) => item.status == ManagedDeviceStatus.assigned)
      .length;

  int get availableCount => _devices
      .where((item) => item.status == ManagedDeviceStatus.available)
      .length;

  int get revokedCount => _devices
      .where((item) => item.status == ManagedDeviceStatus.revoked)
      .length;

  Future<void> hydrateFromOffline() async {
    final rows = await _persistence.readEntities(
      entityType: 'managed_device',
    );
    var changed = false;
    for (final row in rows) {
      final id = row['id']?.toString();
      final label = row['label']?.toString();
      final statusName = row['status']?.toString();
      final registeredAtText = row['registeredAt']?.toString();
      if (id == null ||
          id.isEmpty ||
          label == null ||
          statusName == null ||
          registeredAtText == null) {
        continue;
      }

      final status = ManagedDeviceStatus.values
          .where((item) => item.name == statusName)
          .firstOrNull;
      final registeredAt = DateTime.tryParse(registeredAtText);
      if (status == null || registeredAt == null) continue;

      final restored = ManagedDevice(
        id: id,
        label: label,
        status: status,
        registeredAt: registeredAt.toUtc(),
        serialReference: row['serialReference']?.toString(),
        imeiReference: row['imeiReference']?.toString(),
        assignedMemberId: row['assignedMemberId']?.toString(),
        assignedAt: _date(row['assignedAt']),
        lastSeenAt: _date(row['lastSeenAt']),
        lastLatitude: _double(row['lastLatitude']),
        lastLongitude: _double(row['lastLongitude']),
        lastAccuracyMeters: _double(row['lastAccuracyMeters']),
        batteryPercent: _int(row['batteryPercent']),
        appVersion: row['appVersion']?.toString(),
        syncState: row['syncState']?.toString(),
      );

      final index = _devices.indexWhere((item) => item.id == id);
      if (index < 0) {
        _devices.add(restored);
      } else {
        _devices[index] = restored;
      }
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<ManagedDevice> registerDevice({
    required String label,
    String? serialReference,
    String? imeiReference,
    String? registeredBy,
  }) async {
    final now = DateTime.now().toUtc();
    final device = ManagedDevice(
      id: 'DEV-${now.microsecondsSinceEpoch}',
      label: label.trim().isEmpty ? 'USESF Managed Device' : label.trim(),
      status: ManagedDeviceStatus.available,
      registeredAt: now,
      serialReference: _clean(serialReference),
      imeiReference: _clean(imeiReference),
    );
    _devices.insert(0, device);
    notifyListeners();
    await _persist(
      device,
      action: 'register',
      actorId: registeredBy,
    );
    return device;
  }

  Future<ManagedDevice> assignToMember({
    required String deviceId,
    required String memberId,
    String? assignedBy,
    GeographicScope? authorizedScope,
  }) async {
    final deviceIndex = _devices.indexWhere((item) => item.id == deviceId);
    if (deviceIndex < 0) {
      throw ArgumentError('Unknown managed device: $deviceId');
    }
    if (_membership.memberById(memberId) == null) {
      throw ArgumentError('Unknown USESF member: $memberId');
    }
    final memberScope = _membership.registrationScopeForMember(memberId);
    if (authorizedScope != null &&
        memberScope != null &&
        !GeographyRegistry.scopeContains(authorizedScope, memberScope)) {
      throw StateError(
        'The selected member is outside the coordinator authorization scope.',
      );
    }
    if (_devices.any(
      (item) =>
          item.id != deviceId &&
          item.assignedMemberId == memberId &&
          item.status == ManagedDeviceStatus.assigned,
    )) {
      throw StateError(
        'This member already has an active managed device.',
      );
    }

    final current = _devices[deviceIndex];
    if (current.status == ManagedDeviceStatus.revoked) {
      throw StateError('A revoked device cannot be assigned.');
    }
    final updated = current.copyWith(
      status: ManagedDeviceStatus.assigned,
      assignedMemberId: memberId,
      assignedAt: DateTime.now().toUtc(),
    );
    _devices[deviceIndex] = updated;
    notifyListeners();
    await _persist(
      updated,
      action: 'assign',
      actorId: assignedBy,
    );
    return updated;
  }

  Future<ManagedDevice> releaseDevice({
    required String deviceId,
    String? releasedBy,
  }) async {
    final index = _devices.indexWhere((item) => item.id == deviceId);
    if (index < 0) throw ArgumentError('Unknown managed device: $deviceId');
    final updated = _devices[index].copyWith(
      status: ManagedDeviceStatus.available,
      clearAssignedMember: true,
      clearAssignedAt: true,
    );
    _devices[index] = updated;
    notifyListeners();
    await _persist(
      updated,
      action: 'release',
      actorId: releasedBy,
    );
    return updated;
  }

  Future<ManagedDevice> revokeDevice({
    required String deviceId,
    String? revokedBy,
  }) async {
    final index = _devices.indexWhere((item) => item.id == deviceId);
    if (index < 0) throw ArgumentError('Unknown managed device: $deviceId');
    final updated = _devices[index].copyWith(
      status: ManagedDeviceStatus.revoked,
      clearAssignedMember: true,
      clearAssignedAt: true,
    );
    _devices[index] = updated;
    notifyListeners();
    await _persist(
      updated,
      action: 'revoke',
      actorId: revokedBy,
    );
    return updated;
  }

  void recordHeartbeat({
    required String deviceId,
    required DateTime capturedAt,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    int? batteryPercent,
    String? appVersion,
    String? syncState,
  }) {
    final index = _devices.indexWhere((item) => item.id == deviceId);
    if (index < 0) return;
    _devices[index] = _devices[index].copyWith(
      lastSeenAt: capturedAt.toUtc(),
      lastLatitude: latitude,
      lastLongitude: longitude,
      lastAccuracyMeters: accuracyMeters,
      batteryPercent: batteryPercent == null
          ? null
          : batteryPercent.clamp(0, 100).toInt(),
      appVersion: appVersion,
      syncState: syncState,
    );
    notifyListeners();
  }

  Future<void> _persist(
    ManagedDevice device, {
    required String action,
    String? actorId,
  }) async {
    await _persistence.persistMutation(
      entityType: 'managed_device',
      entityId: device.id,
      mutationType: SyncMutationType.upsert,
      ownerId: device.assignedMemberId,
      payload: {
        'id': device.id,
        'label': device.label,
        'status': device.status.name,
        'registeredAt': device.registeredAt.toIso8601String(),
        'serialReference': device.serialReference,
        'imeiReference': device.imeiReference,
        'assignedMemberId': device.assignedMemberId,
        'assignedAt': device.assignedAt?.toIso8601String(),
        'lastSeenAt': device.lastSeenAt?.toIso8601String(),
        'lastLatitude': device.lastLatitude,
        'lastLongitude': device.lastLongitude,
        'lastAccuracyMeters': device.lastAccuracyMeters,
        'batteryPercent': device.batteryPercent,
        'appVersion': device.appVersion,
        'syncState': device.syncState,
        'action': action,
        'actorId': actorId,
      },
    );
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return value == null ? null : double.tryParse(value.toString());
  }

  static int? _int(Object? value) {
    if (value is num) return value.toInt();
    return value == null ? null : int.tryParse(value.toString());
  }

  static String? _clean(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class ManagedDevices extends InheritedNotifier<ManagedDeviceController> {
  const ManagedDevices({
    super.key,
    required ManagedDeviceController controller,
    required super.child,
  }) : super(notifier: controller);

  static ManagedDeviceController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value =
          context.dependOnInheritedWidgetOfExactType<ManagedDevices>();
      assert(value != null, 'ManagedDevices is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<ManagedDevices>();
    final value = element?.widget as ManagedDevices?;
    assert(value != null, 'ManagedDevices is missing above this context.');
    return value!.notifier!;
  }
}
