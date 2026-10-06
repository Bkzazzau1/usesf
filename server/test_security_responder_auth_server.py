import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from security_responder_auth_server import (
    ResponderAuthService,
)


STATE_SCOPE = {
    "level": "state",
    "country": "Nigeria",
    "zoneId": "NW",
    "stateId": "KD",
}

ZARIA_SCOPE = {
    "level": "lga",
    "country": "Nigeria",
    "zoneId": "NW",
    "stateId": "KD",
    "senatorialDistrictId": "SD/052/KD",
    "lgaId": "KD-ZARIA",
}


class ResponderAuthServiceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.database = Path(self.temp.name) / "security.sqlite3"
        self.service = ResponderAuthService(self.database)
        self.service.provision(
            responder_id="RESP-CENTRAL-001",
            agency_id="AGENCY-POLICE",
            service_number="AP/12345",
            display_name="Insp. Musa Bello",
            access_code="CorrectAccess123!",
            authorized_scope=STATE_SCOPE,
        )

    def tearDown(self):
        self.temp.cleanup()

    def test_correct_credential_authenticates(self):
        result = self.service.authenticate(
            agency_id="AGENCY-POLICE",
            service_number="ap/12345",
            access_code="CorrectAccess123!",
            requested_scope=ZARIA_SCOPE,
        )

        self.assertEqual(result.status, "authenticated")
        self.assertEqual(result.responder["responderId"], "RESP-CENTRAL-001")

    def test_fifth_failure_locks_identity_across_service_instances(self):
        now = datetime(2026, 10, 6, 17, 0, tzinfo=timezone.utc)
        for offset in range(4):
            result = self.service.authenticate(
                agency_id="AGENCY-POLICE",
                service_number="AP/12345",
                access_code="WrongAccess123!",
                requested_scope=STATE_SCOPE,
                now=now + timedelta(seconds=offset),
            )
            self.assertEqual(result.status, "rejected")

        fifth = self.service.authenticate(
            agency_id="AGENCY-POLICE",
            service_number="AP/12345",
            access_code="WrongAccess123!",
            requested_scope=STATE_SCOPE,
            now=now + timedelta(seconds=4),
        )
        self.assertEqual(fifth.status, "locked")
        self.assertIsNotNone(fifth.locked_until)

        second_instance = ResponderAuthService(self.database)
        correct_during_lock = second_instance.authenticate(
            agency_id="AGENCY-POLICE",
            service_number="AP/12345",
            access_code="CorrectAccess123!",
            requested_scope=STATE_SCOPE,
            now=now + timedelta(minutes=1),
        )
        self.assertEqual(correct_during_lock.status, "locked")

    def test_reprovision_clears_global_lockout(self):
        now = datetime(2026, 10, 6, 17, 0, tzinfo=timezone.utc)
        for offset in range(5):
            self.service.authenticate(
                agency_id="AGENCY-POLICE",
                service_number="AP/12345",
                access_code="WrongAccess123!",
                requested_scope=STATE_SCOPE,
                now=now + timedelta(seconds=offset),
            )

        self.service.provision(
            responder_id="RESP-CENTRAL-001",
            agency_id="AGENCY-POLICE",
            service_number="AP/12345",
            display_name="Insp. Musa Bello",
            access_code="NewAccess123!",
            authorized_scope=STATE_SCOPE,
        )
        recovered = self.service.authenticate(
            agency_id="AGENCY-POLICE",
            service_number="AP/12345",
            access_code="NewAccess123!",
            requested_scope=STATE_SCOPE,
        )
        self.assertEqual(recovered.status, "authenticated")

    def test_scope_escalation_is_rejected(self):
        self.service.provision(
            responder_id="RESP-ZARIA-001",
            agency_id="AGENCY-NSCDC",
            service_number="NSCDC/45821",
            display_name="ASC Grace Danjuma",
            access_code="ScopedAccess123!",
            authorized_scope=ZARIA_SCOPE,
        )

        result = self.service.authenticate(
            agency_id="AGENCY-NSCDC",
            service_number="NSCDC/45821",
            access_code="ScopedAccess123!",
            requested_scope=STATE_SCOPE,
        )
        self.assertEqual(result.status, "rejected")

    def test_unknown_identity_uses_same_failure_lockout_policy(self):
        now = datetime(2026, 10, 6, 17, 0, tzinfo=timezone.utc)
        result = None
        for offset in range(5):
            result = self.service.authenticate(
                agency_id="AGENCY-POLICE",
                service_number="AP/UNKNOWN",
                access_code="WrongAccess123!",
                requested_scope=STATE_SCOPE,
                now=now + timedelta(seconds=offset),
            )
        self.assertEqual(result.status, "locked")


if __name__ == "__main__":
    unittest.main()
