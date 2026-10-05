import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usesf/tgcg/assignments/assignment_store.dart';
import 'package:usesf/tgcg/devices/managed_device_store.dart';
import 'package:usesf/tgcg/geography/geography_registry.dart';
import 'package:usesf/tgcg/membership/membership_store.dart';
import 'package:usesf/tgcg/offline/offline_database_memory.dart';
import 'package:usesf/tgcg/offline/offline_persistence.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('presentation seed contains submitted work that grants no access', () {
    final persistence = OfflinePersistenceController(
      openDatabase: () async => InMemoryOfflineDatabase(),
    );
    final membership = MembershipOperationsController.prototypeSeed(
      GeographyRegistry.prototypeSeed(),
      persistence: persistence,
    );
    final assignments = AssignmentController.prototypeSeed(
      membership: membership,
      devices: ManagedDeviceController.prototypeSeed(
        membership: membership,
        persistence: persistence,
      ),
      persistence: persistence,
    );

    final individual = assignments.assignments
        .where((item) => item.groupAssignmentId == null)
        .toList();
    expect(individual, hasLength(3));
    expect(
      individual.every((item) => item.status == AssignmentStatus.completed),
      isTrue,
    );

    final group = assignments.groupAssignments.single;
    expect(group.status, GroupAssignmentStatus.submitted);
    expect(assignments.assignmentsForGroup(group.id), hasLength(3));
    expect(
      assignments.assignmentsForGroup(group.id).every(
            (item) => item.status == AssignmentStatus.completed,
          ),
      isTrue,
    );

    for (final member in membership.members) {
      expect(assignments.activeAssignmentsForMember(member.id), isEmpty);
    }
    expect(
      assignments.assignments.every((item) => item.evidence.isNotEmpty),
      isTrue,
    );
  });
}
