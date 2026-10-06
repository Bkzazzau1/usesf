"""Central responder authentication service for USESF.

Standard-library implementation so the repository has a runnable reference
server without adding application dependencies. Deploy behind TLS/reverse proxy
and set USESF_ADMIN_PROVISION_TOKEN before enabling provisioning.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

PBKDF2_ITERATIONS = 120_000
MAX_FAILURES = 5
FAILURE_WINDOW = timedelta(minutes=15)
LOCKOUT_DURATION = timedelta(minutes=15)
DUMMY_SALT = b"USESF-SECURITY-1"
DUMMY_HASH = hashlib.pbkdf2_hmac(
    "sha256",
    b"invalid-responder-credential",
    DUMMY_SALT,
    PBKDF2_ITERATIONS,
    dklen=32,
)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _iso(value: datetime | None) -> str | None:
    return value.astimezone(timezone.utc).isoformat() if value else None


def _parse_time(value: str | None) -> datetime | None:
    if not value:
        return None
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _normalize_service_number(value: str) -> str:
    return "".join(value.upper().split())


def _derive_access_code(access_code: str, salt: bytes) -> bytes:
    return hashlib.pbkdf2_hmac(
        "sha256",
        access_code.encode("utf-8"),
        salt,
        PBKDF2_ITERATIONS,
        dklen=32,
    )


def _scope_within(parent: dict[str, Any], child: dict[str, Any]) -> bool:
    if parent.get("country") != child.get("country"):
        return False
    level = parent.get("level")
    if level == "country":
        return True
    for key, terminal_level in (
        ("zoneId", "geopoliticalZone"),
        ("stateId", "state"),
        ("senatorialDistrictId", "senatorialDistrict"),
        ("lgaId", "lga"),
        ("wardId", "ward"),
        ("pollingUnitId", "pollingUnit"),
    ):
        parent_value = parent.get(key)
        if parent_value is not None and parent_value != child.get(key):
            return False
        if level == terminal_level:
            return True
    return False


@dataclass(frozen=True)
class AuthenticationResult:
    status: str
    responder: dict[str, Any] | None = None
    locked_until: datetime | None = None


class ResponderAuthService:
    def __init__(self, database_path: str | Path):
        self.database_path = str(database_path)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(
            self.database_path,
            timeout=10,
            isolation_level=None,
        )
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        return connection

    def _initialize(self) -> None:
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS security_responders (
                    responder_id TEXT PRIMARY KEY,
                    agency_id TEXT NOT NULL,
                    service_number TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    authorized_scope_json TEXT NOT NULL,
                    credential_salt TEXT NOT NULL,
                    credential_hash TEXT NOT NULL,
                    active INTEGER NOT NULL DEFAULT 1,
                    updated_at TEXT NOT NULL,
                    UNIQUE (agency_id, service_number)
                );

                CREATE TABLE IF NOT EXISTS security_login_attempts (
                    agency_id TEXT NOT NULL,
                    service_number TEXT NOT NULL,
                    failed_attempts INTEGER NOT NULL,
                    window_started_at TEXT NOT NULL,
                    locked_until TEXT,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY (agency_id, service_number)
                );
                """
            )

    def provision(
        self,
        *,
        responder_id: str,
        agency_id: str,
        service_number: str,
        display_name: str,
        access_code: str,
        authorized_scope: dict[str, Any],
    ) -> None:
        normalized_service = _normalize_service_number(service_number)
        if not responder_id.strip() or not agency_id.strip():
            raise ValueError("Responder and agency identifiers are required.")
        if len(normalized_service) < 4:
            raise ValueError("Invalid service number.")
        if len(display_name.strip()) < 3:
            raise ValueError("Invalid responder name.")
        if len(access_code) < 8:
            raise ValueError("Access code must contain at least 8 characters.")
        if not isinstance(authorized_scope, dict) or not authorized_scope.get("level"):
            raise ValueError("Authorized scope is required.")

        salt = secrets.token_bytes(16)
        credential_hash = _derive_access_code(access_code, salt)
        now = _utcnow()
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute(
                """
                INSERT INTO security_responders (
                    responder_id, agency_id, service_number, display_name,
                    authorized_scope_json, credential_salt, credential_hash,
                    active, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)
                ON CONFLICT(agency_id, service_number) DO UPDATE SET
                    responder_id = excluded.responder_id,
                    display_name = excluded.display_name,
                    authorized_scope_json = excluded.authorized_scope_json,
                    credential_salt = excluded.credential_salt,
                    credential_hash = excluded.credential_hash,
                    active = 1,
                    updated_at = excluded.updated_at
                """,
                (
                    responder_id.strip(),
                    agency_id.strip(),
                    normalized_service,
                    display_name.strip(),
                    json.dumps(authorized_scope, separators=(",", ":")),
                    base64.urlsafe_b64encode(salt).decode("ascii"),
                    base64.urlsafe_b64encode(credential_hash).decode("ascii"),
                    _iso(now),
                ),
            )
            connection.execute(
                """
                DELETE FROM security_login_attempts
                WHERE agency_id = ? AND service_number = ?
                """,
                (agency_id.strip(), normalized_service),
            )
            connection.commit()

    def authenticate(
        self,
        *,
        agency_id: str,
        service_number: str,
        access_code: str,
        requested_scope: dict[str, Any],
        now: datetime | None = None,
    ) -> AuthenticationResult:
        current_time = (now or _utcnow()).astimezone(timezone.utc)
        normalized_service = _normalize_service_number(service_number)
        agency_id = agency_id.strip()

        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            attempt = connection.execute(
                """
                SELECT failed_attempts, window_started_at, locked_until
                FROM security_login_attempts
                WHERE agency_id = ? AND service_number = ?
                """,
                (agency_id, normalized_service),
            ).fetchone()

            if attempt:
                locked_until = _parse_time(attempt["locked_until"])
                if locked_until and current_time < locked_until:
                    connection.commit()
                    return AuthenticationResult(
                        status="locked",
                        locked_until=locked_until,
                    )
                if locked_until and current_time >= locked_until:
                    connection.execute(
                        """
                        DELETE FROM security_login_attempts
                        WHERE agency_id = ? AND service_number = ?
                        """,
                        (agency_id, normalized_service),
                    )
                    attempt = None

            responder = connection.execute(
                """
                SELECT responder_id, agency_id, service_number, display_name,
                       authorized_scope_json, credential_salt, credential_hash,
                       active
                FROM security_responders
                WHERE agency_id = ? AND service_number = ?
                """,
                (agency_id, normalized_service),
            ).fetchone()

            if responder and responder["active"]:
                salt = base64.urlsafe_b64decode(responder["credential_salt"])
                expected_hash = base64.urlsafe_b64decode(
                    responder["credential_hash"]
                )
            else:
                salt = DUMMY_SALT
                expected_hash = DUMMY_HASH

            actual_hash = _derive_access_code(access_code, salt)
            credential_valid = bool(responder and responder["active"]) and hmac.compare_digest(
                expected_hash,
                actual_hash,
            )

            if not credential_valid:
                locked_until = self._register_failure(
                    connection,
                    agency_id=agency_id,
                    service_number=normalized_service,
                    previous=attempt,
                    now=current_time,
                )
                connection.commit()
                if locked_until:
                    return AuthenticationResult(
                        status="locked",
                        locked_until=locked_until,
                    )
                return AuthenticationResult(status="rejected")

            authorized_scope = json.loads(responder["authorized_scope_json"])
            if not _scope_within(authorized_scope, requested_scope):
                connection.commit()
                return AuthenticationResult(status="rejected")

            connection.execute(
                """
                DELETE FROM security_login_attempts
                WHERE agency_id = ? AND service_number = ?
                """,
                (agency_id, normalized_service),
            )
            connection.commit()
            return AuthenticationResult(
                status="authenticated",
                responder={
                    "responderId": responder["responder_id"],
                    "agencyId": responder["agency_id"],
                    "serviceNumber": responder["service_number"],
                    "displayName": responder["display_name"],
                    "authorizedScope": authorized_scope,
                },
            )

    @staticmethod
    def _register_failure(
        connection: sqlite3.Connection,
        *,
        agency_id: str,
        service_number: str,
        previous: sqlite3.Row | None,
        now: datetime,
    ) -> datetime | None:
        if previous:
            window_started = _parse_time(previous["window_started_at"]) or now
            within_window = now - window_started < FAILURE_WINDOW
            failed_attempts = (
                int(previous["failed_attempts"]) + 1 if within_window else 1
            )
            if not within_window:
                window_started = now
        else:
            window_started = now
            failed_attempts = 1

        locked_until = (
            now + LOCKOUT_DURATION if failed_attempts >= MAX_FAILURES else None
        )
        connection.execute(
            """
            INSERT INTO security_login_attempts (
                agency_id, service_number, failed_attempts,
                window_started_at, locked_until, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(agency_id, service_number) DO UPDATE SET
                failed_attempts = excluded.failed_attempts,
                window_started_at = excluded.window_started_at,
                locked_until = excluded.locked_until,
                updated_at = excluded.updated_at
            """,
            (
                agency_id,
                service_number,
                failed_attempts,
                _iso(window_started),
                _iso(locked_until),
                _iso(now),
            ),
        )
        return locked_until


class ResponderAuthHttpHandler(BaseHTTPRequestHandler):
    server_version = "USESFResponderAuth/1.0"

    @property
    def service(self) -> ResponderAuthService:
        return self.server.service  # type: ignore[attr-defined]

    @property
    def admin_token(self) -> str:
        return self.server.admin_token  # type: ignore[attr-defined]

    def do_POST(self) -> None:  # noqa: N802
        if self.path == "/v1/security/responders/provision":
            self._handle_provision()
            return
        if self.path == "/v1/security/responders/authenticate":
            self._handle_authenticate()
            return
        self._json(HTTPStatus.NOT_FOUND, {"message": "Not found."})

    def _handle_provision(self) -> None:
        authorization = self.headers.get("Authorization", "")
        expected = f"Bearer {self.admin_token}"
        if not self.admin_token or not hmac.compare_digest(authorization, expected):
            self._json(HTTPStatus.FORBIDDEN, {"message": "Forbidden."})
            return
        try:
            payload = self._read_json()
            self.service.provision(
                responder_id=str(payload["responderId"]),
                agency_id=str(payload["agencyId"]),
                service_number=str(payload["serviceNumber"]),
                display_name=str(payload["displayName"]),
                access_code=str(payload["accessCode"]),
                authorized_scope=dict(payload["authorizedScope"]),
            )
            self._json(HTTPStatus.CREATED, {"status": "provisioned"})
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
            self._json(HTTPStatus.BAD_REQUEST, {"message": str(error)})

    def _handle_authenticate(self) -> None:
        try:
            payload = self._read_json()
            result = self.service.authenticate(
                agency_id=str(payload["agencyId"]),
                service_number=str(payload["serviceNumber"]),
                access_code=str(payload["accessCode"]),
                requested_scope=dict(payload["requestedScope"]),
            )
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
            self._json(HTTPStatus.BAD_REQUEST, {"message": str(error)})
            return

        if result.status == "authenticated":
            self._json(HTTPStatus.OK, result.responder or {})
        elif result.status == "locked":
            self._json(
                HTTPStatus.LOCKED,
                {
                    "message": "Too many failed attempts.",
                    "lockedUntil": _iso(result.locked_until),
                },
            )
        else:
            self._json(
                HTTPStatus.UNAUTHORIZED,
                {"message": "Invalid responder credential."},
            )

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 65_536:
            raise ValueError("Invalid request body size.")
        raw = self.rfile.read(length)
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            raise ValueError("Expected a JSON object.")
        return payload

    def _json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format: str, *args: Any) -> None:
        return


class ResponderAuthHttpServer(ThreadingHTTPServer):
    def __init__(
        self,
        address: tuple[str, int],
        service: ResponderAuthService,
        admin_token: str,
    ):
        super().__init__(address, ResponderAuthHttpHandler)
        self.service = service
        self.admin_token = admin_token


def main() -> None:
    database_path = os.environ.get(
        "USESF_SECURITY_AUTH_DB",
        "./usesf_security_auth.sqlite3",
    )
    admin_token = os.environ.get("USESF_ADMIN_PROVISION_TOKEN", "")
    if len(admin_token) < 24:
        raise SystemExit(
            "USESF_ADMIN_PROVISION_TOKEN must be configured with at least 24 characters."
        )
    host = os.environ.get("USESF_SECURITY_AUTH_HOST", "127.0.0.1")
    port = int(os.environ.get("USESF_SECURITY_AUTH_PORT", "8088"))
    service = ResponderAuthService(database_path)
    server = ResponderAuthHttpServer((host, port), service, admin_token)
    server.serve_forever()


if __name__ == "__main__":
    main()
