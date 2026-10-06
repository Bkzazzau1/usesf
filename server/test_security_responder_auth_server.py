import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from server.security_responder_auth_server import (
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

    def test_authenticated_session_is_revocable_across_service_instances(self):
        authenticated = self.service.authenticate(
            agency_id="AGENCY-POLICE",
            service_number="AP/12345",
            access_code="CorrectAccess123!",
            requested_scope=STATE_SCOPE,
        )
        self.assertEqual(authenticated.status, "authenticated")
        token = authenticated.responder["sessionToken"]
        expires_at = authenticated.responder["sessionExpiresAt"]
        self.assertTrue(token)
        self.assertTrue(expires_at)

        second_instance = ResponderAuthService(self.database)
        active = second_instance.validate_session(token)
        self.assertEqual(active.status, "active")
        self.assertEqual(
            active.responder["responderId"],
            "RESP-CENTRAL-001",
        )

        disabled = second_instance.disable_responder(
            agency_id="AGENCY-POLICE",
            service_number="AP/12345",
        )
        self.assertTrue(disabled)

        revoked = self.service.validate_session(token)
        self.assertEqual(revoked.status, "revoked")

    def test_session_expires_after_absolute_lifetime(self):
        issued_at = datetime(2026, 10, 6, 8, 0, tzinfo=timezone.utc)
        authenticated = self.service.authenticate(
            agency_id="AGENCY-POLICE",
            service_number="AP/12345",
            access_code="CorrectAccess123!",
            requested_scope=STATE_SCOPE,
            now=issued_at,
        )
        token = authenticated.responder["sessionToken"]

        before_expiry = self.service.validate_session(
            token,
            now=issued_at + timedelta(hours=7, minutes=59),
        )
        self.assertEqual(before_expiry.status, "active")

        expired = self.service.validate_session(
            token,
            now=issued_at + timedelta(hours=8),
        )
        self.assertEqual(expired.status, "revoked")

    def test_reprovision_revokes_existing_sessions(self):
        authenticated = self.service.authenticate(
            agency_id="AGENCY-POLICE",
            service_number="AP/12345",
            access_code="CorrectAccess123!",
            requested_scope=STATE_SCOPE,
        )
        old_token = authenticated.responder["sessionToken"]

        self.service.provision(
            responder_id="RESP-CENTRAL-001",
            agency_id="AGENCY-POLICE",
            service_number="AP/12345",
            display_name="Insp. Musa Bello",
            access_code="NewAccess123!",
            authorized_scope=STATE_SCOPE,
        )

        self.assertEqual(
            self.service.validate_session(old_token).status,
            "revoked",
        )

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
