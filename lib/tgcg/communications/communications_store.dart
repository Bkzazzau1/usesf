import 'package:flutter/widgets.dart';

import '../domain/local_id.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../governance/governance_store.dart';
import '../offline/offline_payloads.dart';
import '../offline/offline_persistence.dart';

enum CommunicationRoomType {
  stateCommand,
  situationRoom,
  zone,
  state,
  lga,
  ward,
  technicalSupport,
}

enum MessageDeliveryState { localQueued, sending, sent, delivered, failed }

enum BroadcastDeliveryState { queued, sent, partiallyDelivered, failed }

class OperationalRoom {
  const OperationalRoom({
    required this.id,
    required this.name,
    required this.type,
    required this.scope,
    this.description,
  });

  final String id;
  final String name;
  final CommunicationRoomType type;
  final GeographicScope scope;
  final String? description;
}

class OperationalMessage {
  const OperationalMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    required this.deliveryState,
    this.replyToMessageId,
  });

  final String id;
  final String roomId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final MessageDeliveryState deliveryState;
  final String? replyToMessageId;
}

class OperationalBroadcast {
  const OperationalBroadcast({
    required this.id,
    required this.title,
    required this.body,
    required this.scope,
    required this.senderId,
    required this.createdAt,
    required this.deliveryState,
  });

  final String id;
  final String title;
  final String body;
  final GeographicScope scope;
  final String senderId;
  final DateTime createdAt;
  final BroadcastDeliveryState deliveryState;
}

class CommunicationsController extends ChangeNotifier {
  CommunicationsController._({
    required GovernanceOperationsController governance,
    required List<OperationalRoom> rooms,
    required List<OperationalMessage> messages,
    required List<OperationalBroadcast> broadcasts,
    OfflinePersistenceController? persistence,
  })  : _governance = governance,
        _rooms = rooms,
        _messages = messages,
        _broadcasts = broadcasts,
        _persistence = persistence;

  factory CommunicationsController.productionFoundation({
    required GovernanceOperationsController governance,
    required OfflinePersistenceController persistence,
  }) =>
      CommunicationsController._(
        governance: governance,
        rooms: _operationalRooms(),
        messages: <OperationalMessage>[],
        broadcasts: <OperationalBroadcast>[],
        persistence: persistence,
      );

  static List<OperationalRoom> _operationalRooms() {
    final kadunaState = GeographicScope(
      level: GeographyLevel.state,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
    );
    final kadunaNorth = GeographicScope(
      level: GeographyLevel.lga,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/053/KD',
      senatorialDistrictName: 'Kaduna Central',
      lgaId: 'KD-KADUNA-NORTH',
      lgaName: 'Kaduna North',
    );
    final kadunaWard01 = GeographicScope(
      level: GeographyLevel.ward,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/053/KD',
      senatorialDistrictName: 'Kaduna Central',
      lgaId: 'KD-KADUNA-NORTH',
      lgaName: 'Kaduna North',
      wardId: 'KD-KN-W01',
      wardName: 'Ward 01',
    );
    final zaria = GeographicScope(
      level: GeographyLevel.lga,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/052/KD',
      senatorialDistrictName: 'Kaduna North',
      lgaId: 'KD-ZARIA',
      lgaName: 'Zaria',
    );
    final makurdiWard01 = GeographicScope(
      level: GeographyLevel.ward,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      senatorialDistrictId: 'SD/052/KD',
      senatorialDistrictName: 'Kaduna North',
      lgaId: 'KD-ZARIA',
      lgaName: 'Zaria',
      wardId: 'KD-ZA-W01',
      wardName: 'Ward 01',
    );

    return [
        const OperationalRoom(
          id: 'ROOM-STATE',
          name: 'Kaduna State Operations',
          type: CommunicationRoomType.stateCommand,
          scope: GeographicScope.kaduna,
          description: 'State-wide operational coordination and command notices.',
        ),
        const OperationalRoom(
          id: 'ROOM-SITUATION',
          name: 'Situation Room',
          type: CommunicationRoomType.situationRoom,
          scope: GeographicScope.kaduna,
          description: 'Live operational coordination for incidents and verification.',
        ),
        OperationalRoom(
          id: 'ROOM-KD',
          name: 'Kaduna State Operations',
          type: CommunicationRoomType.state,
          scope: kadunaState,
          description: 'Kaduna state coordination room.',
        ),
        OperationalRoom(
          id: 'ROOM-KD-KN',
          name: 'Kaduna North Field Desk',
          type: CommunicationRoomType.lga,
          scope: kadunaNorth,
          description: 'Kaduna North field coordination.',
        ),
        OperationalRoom(
          id: 'ROOM-KD-KN-W01',
          name: 'Ward 01 Field Team',
          type: CommunicationRoomType.ward,
          scope: kadunaWard01,
          description: 'Ward 01 polling-unit agents and ward coordination.',
        ),
        OperationalRoom(
          id: 'ROOM-KD-ZA',
          name: 'Zaria Field Desk',
          type: CommunicationRoomType.lga,
          scope: zaria,
          description: 'Zaria field coordination room.',
        ),
        OperationalRoom(
          id: 'ROOM-KD-ZA-W01',
          name: 'Ward 01 Field Team',
          type: CommunicationRoomType.ward,
          scope: makurdiWard01,
          description: 'Ward 01 polling-unit agents and ward coordination.',
        ),
        const OperationalRoom(
          id: 'ROOM-SUPPORT',
          name: 'Technical Support',
          type: CommunicationRoomType.technicalSupport,
          scope: GeographicScope.kaduna,
          description: 'Device, sync and application support desk.',
        ),
      ];
  }

  factory CommunicationsController.prototypeSeed(
    GovernanceOperationsController governance,
  ) {
    final now = DateTime.utc(2026, 9, 27, 8, 25);

    return CommunicationsController._(
      governance: governance,
      rooms: _operationalRooms(),
      messages: [
        OperationalMessage(
          id: 'MSG-0001',
          roomId: 'ROOM-SITUATION',
          senderId: 'SITUATION-DESK',
          body: 'Confirm acknowledgement of all high-priority incidents and maintain evidence provenance.',
          createdAt: now.subtract(const Duration(minutes: 28)),
          deliveryState: MessageDeliveryState.delivered,
        ),
        OperationalMessage(
          id: 'MSG-0002',
          roomId: 'ROOM-KD',
          senderId: 'KD-COORD',
          body: 'Polling-unit assignment review is in progress. Escalate any unassigned unit to the LGA coordinator for assignment.',
          createdAt: now.subtract(const Duration(minutes: 19)),
          deliveryState: MessageDeliveryState.delivered,
        ),
        OperationalMessage(
          id: 'MSG-0003',
          roomId: 'ROOM-SUPPORT',
          senderId: 'TECH-SUPPORT',
          body: 'Offline records remain locally queued when connectivity is unavailable. Do not duplicate submissions.',
          createdAt: now.subtract(const Duration(minutes: 12)),
          deliveryState: MessageDeliveryState.sent,
        ),
        OperationalMessage(
          id: 'MSG-0004',
          roomId: 'ROOM-KD-KN-W01',
          senderId: 'WARD-01-COORD',
          body: 'Ward 01 team, confirm your assigned polling unit and keep incident updates inside this room.',
          createdAt: now.subtract(const Duration(minutes: 10)),
          deliveryState: MessageDeliveryState.delivered,
        ),
        OperationalMessage(
          id: 'MSG-0005',
          roomId: 'ROOM-KD-KN',
          senderId: 'KD-KN-DESK',
          body: 'Kaduna North field desk is available for local escalation and coordination.',
          createdAt: now.subtract(const Duration(minutes: 7)),
          deliveryState: MessageDeliveryState.delivered,
        ),
        OperationalMessage(
          id: 'MSG-0006',
          roomId: 'ROOM-KD-ZA-W01',
          senderId: 'WARD-01-COORD',
          body: 'Zaria Ward 01 team, use this room for local field coordination and polling-unit updates.',
          createdAt: now.subtract(const Duration(minutes: 8)),
          deliveryState: MessageDeliveryState.delivered,
        ),
      ],
      broadcasts: [
        OperationalBroadcast(
          id: 'BCAST-0001',
          title: 'Operational readiness notice',
          body: 'Use only assigned accounts and devices for field workflows. Report access or synchronization issues through the support channel.',
          scope: GeographicScope.kaduna,
          senderId: 'STATE-OPS',
          createdAt: now.subtract(const Duration(hours: 1)),
          deliveryState: BroadcastDeliveryState.sent,
        ),
      ],
    );
  }

  final GovernanceOperationsController _governance;
  final List<OperationalRoom> _rooms;
  final List<OperationalMessage> _messages;
  final List<OperationalBroadcast> _broadcasts;
  final OfflinePersistenceController? _persistence;

  List<OperationalRoom> get rooms => List.unmodifiable(_rooms);
  List<OperationalMessage> get messages => List.unmodifiable(_messages);
  List<OperationalBroadcast> get broadcasts => List.unmodifiable(_broadcasts);

  Future<void> hydrateFromOffline() async {
    final persistence = _persistence;
    if (persistence == null) return;

    final messageRows =
        await persistence.readEntities(entityType: 'communication_message');
    final broadcastRows =
        await persistence.readEntities(entityType: 'operational_broadcast');
    var changed = false;

    for (final row in messageRows) {
      final restored = _messageFromJson(row);
      if (restored == null ||
          !_rooms.any((room) => room.id == restored.roomId)) {
        continue;
      }
      final index = _messages.indexWhere((item) => item.id == restored.id);
      if (index < 0) {
        _messages.add(restored);
      } else {
        _messages[index] = restored;
      }
      changed = true;
    }

    for (final row in broadcastRows) {
      final restored = _broadcastFromJson(row);
      if (restored == null) continue;
      final index = _broadcasts.indexWhere((item) => item.id == restored.id);
      if (index < 0) {
        _broadcasts.add(restored);
      } else {
        _broadcasts[index] = restored;
      }
      changed = true;
    }

    if (changed) {
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _broadcasts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }
  }

  List<OperationalRoom> roomsForScope(GeographicScope userScope) =>
      _rooms.where((room) => _overlaps(userScope, room.scope)).toList(growable: false);

  List<OperationalRoom> localRoomsForFieldAgent(GeographicScope userScope) {
    if (userScope.lgaId == null) return const [];
    return _rooms.where((room) => _isLocalFieldRoom(userScope, room)).toList(growable: false);
  }

  List<OperationalMessage> messagesForRoom(String roomId) => _messages
      .where((message) => message.roomId == roomId)
      .toList(growable: false)
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<OperationalBroadcast> broadcastsForScope(GeographicScope userScope) =>
      _broadcasts.where((item) => _overlaps(userScope, item.scope)).toList(growable: false)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<bool> sendMessage({
    required String roomId,
    required String senderId,
    required String body,
    required TgcgRole role,
    required GeographicScope userScope,
    bool capabilityAuthorized = false,
  }) async {
    final roomIndex = _rooms.indexWhere((room) => room.id == roomId);
    if (roomIndex < 0 || body.trim().isEmpty) return false;
    final room = _rooms[roomIndex];
    if (!capabilityAuthorized &&
        !TgcgPermissionPolicy.allows(
          role,
          TgcgCapability.sendOperationalMessage,
        )) {
      return false;
    }

    if (role == TgcgRole.pollingUnitAgent) {
      if (!_isLocalFieldRoom(userScope, room)) return false;
    } else if (!_overlaps(userScope, room.scope)) {
      return false;
    }

    final createdAt = DateTime.now().toUtc();
    final message = OperationalMessage(
      id: newLocalId('MSG', createdAt),
      roomId: room.id,
      senderId: senderId,
      body: body.trim(),
      createdAt: createdAt,
      deliveryState: MessageDeliveryState.localQueued,
    );
    await _persistence?.persistMutation(
      entityType: 'communication_message',
      entityId: message.id,
      mutationType: SyncMutationType.create,
      payload: _messageToJson(message),
      scopeKey: scopeStorageKey(room.scope),
      ownerId: senderId,
    );
    _messages.add(message);
    _governance.recordAudit(
      actorId: senderId,
      action: 'operational_message_created',
      entityType: 'communication_message',
      entityId: message.id,
      detail: 'Queued local message for room ${room.name}.',
      scope: room.scope,
    );
    notifyListeners();
    return true;
  }

  Future<bool> sendBroadcast({
    required String title,
    required String body,
    required GeographicScope targetScope,
    required String senderId,
    required TgcgRole role,
    required GeographicScope userScope,
    bool capabilityAuthorized = false,
  }) async {
    if (title.trim().isEmpty || body.trim().isEmpty) return false;
    if (!capabilityAuthorized &&
        !TgcgPermissionPolicy.allows(role, TgcgCapability.sendBroadcast)) {
      return false;
    }
    if (!_within(userScope, targetScope)) return false;

    final createdAt = DateTime.now().toUtc();
    final broadcast = OperationalBroadcast(
      id: newLocalId('BCAST', createdAt),
      title: title.trim(),
      body: body.trim(),
      scope: targetScope,
      senderId: senderId,
      createdAt: createdAt,
      deliveryState: BroadcastDeliveryState.queued,
    );
    await _persistence?.persistMutation(
      entityType: 'operational_broadcast',
      entityId: broadcast.id,
      mutationType: SyncMutationType.create,
      payload: _broadcastToJson(broadcast),
      scopeKey: scopeStorageKey(targetScope),
      ownerId: senderId,
    );
    _broadcasts.insert(0, broadcast);
    _governance.recordAudit(
      actorId: senderId,
      action: 'broadcast_created',
      entityType: 'operational_broadcast',
      entityId: broadcast.id,
      detail: 'Operational broadcast queued for ${targetScope.label}.',
      scope: targetScope,
    );
    notifyListeners();
    return true;
  }

  static Map<String, Object?> _messageToJson(
    OperationalMessage message,
  ) =>
      {
        'id': message.id,
        'roomId': message.roomId,
        'senderId': message.senderId,
        'body': message.body,
        'createdAt': message.createdAt.toUtc().toIso8601String(),
        'deliveryState': message.deliveryState.name,
        'replyToMessageId': message.replyToMessageId,
      };

  static OperationalMessage? _messageFromJson(Map<String, Object?> row) {
    final id = row['id']?.toString();
    final roomId = row['roomId']?.toString();
    final senderId = row['senderId']?.toString();
    final body = row['body']?.toString();
    final createdAt =
        DateTime.tryParse(row['createdAt']?.toString() ?? '')?.toUtc();
    final deliveryState = _enumValue(
      MessageDeliveryState.values,
      row['deliveryState'],
    );
    if (id == null ||
        roomId == null ||
        senderId == null ||
        body == null ||
        createdAt == null ||
        deliveryState == null) {
      return null;
    }
    return OperationalMessage(
      id: id,
      roomId: roomId,
      senderId: senderId,
      body: body,
      createdAt: createdAt,
      deliveryState: deliveryState,
      replyToMessageId: row['replyToMessageId']?.toString(),
    );
  }

  static Map<String, Object?> _broadcastToJson(
    OperationalBroadcast broadcast,
  ) =>
      {
        'id': broadcast.id,
        'title': broadcast.title,
        'body': broadcast.body,
        'scope': geographicScopeToJson(broadcast.scope),
        'senderId': broadcast.senderId,
        'createdAt': broadcast.createdAt.toUtc().toIso8601String(),
        'deliveryState': broadcast.deliveryState.name,
      };

  static OperationalBroadcast? _broadcastFromJson(
    Map<String, Object?> row,
  ) {
    final id = row['id']?.toString();
    final title = row['title']?.toString();
    final body = row['body']?.toString();
    final scope = geographicScopeFromJson(row['scope']);
    final senderId = row['senderId']?.toString();
    final createdAt =
        DateTime.tryParse(row['createdAt']?.toString() ?? '')?.toUtc();
    final deliveryState = _enumValue(
      BroadcastDeliveryState.values,
      row['deliveryState'],
    );
    if (id == null ||
        title == null ||
        body == null ||
        scope == null ||
        senderId == null ||
        createdAt == null ||
        deliveryState == null) {
      return null;
    }
    return OperationalBroadcast(
      id: id,
      title: title,
      body: body,
      scope: scope,
      senderId: senderId,
      createdAt: createdAt,
      deliveryState: deliveryState,
    );
  }

  static T? _enumValue<T extends Enum>(List<T> values, Object? raw) {
    final name = raw?.toString();
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static bool _isLocalFieldRoom(
    GeographicScope userScope,
    OperationalRoom room,
  ) {
    if (userScope.stateId == null || userScope.lgaId == null) return false;
    if (room.type != CommunicationRoomType.lga &&
        room.type != CommunicationRoomType.ward) {
      return false;
    }
    if (room.scope.stateId != userScope.stateId ||
        room.scope.lgaId != userScope.lgaId) {
      return false;
    }
    if (room.type == CommunicationRoomType.ward) {
      return userScope.wardId != null && room.scope.wardId == userScope.wardId;
    }
    return true;
  }

  static bool _overlaps(GeographicScope a, GeographicScope b) =>
      _within(a, b) || _within(b, a);

  static bool _within(GeographicScope parent, GeographicScope child) {
    if (parent.country != child.country) return false;
    if (parent.level == GeographyLevel.country) return true;
    if (parent.zoneId != null && parent.zoneId != child.zoneId) return false;
    if (parent.level == GeographyLevel.geopoliticalZone) return true;
    if (parent.stateId != null && parent.stateId != child.stateId) return false;
    if (parent.level == GeographyLevel.state) return true;
    if (parent.senatorialDistrictId != null &&
        parent.senatorialDistrictId != child.senatorialDistrictId) {
      return false;
    }
    if (parent.level == GeographyLevel.senatorialDistrict) return true;
    if (parent.lgaId != null && parent.lgaId != child.lgaId) return false;
    if (parent.level == GeographyLevel.lga) return true;
    if (parent.wardId != null && parent.wardId != child.wardId) return false;
    if (parent.level == GeographyLevel.ward) return true;
    return parent.pollingUnitId == child.pollingUnitId;
  }
}

class Communications extends InheritedNotifier<CommunicationsController> {
  const Communications({
    super.key,
    required CommunicationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static CommunicationsController of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final value = context.dependOnInheritedWidgetOfExactType<Communications>();
      assert(value != null, 'Communications is missing above this context.');
      return value!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<Communications>();
    final value = element?.widget as Communications?;
    assert(value != null, 'Communications is missing above this context.');
    return value!.notifier!;
  }
}
