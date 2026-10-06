# USESF central responder authentication

This service is the authoritative connected-mode authentication and lockout
authority for Security Portal responders. The Flutter client keeps its local
PBKDF2 verifier and device-local lockout for offline operation, but when the
remote service is reachable its decision is authoritative across devices.

## Policy

- 5 failed credential attempts inside 15 minutes
- 15-minute lockout after the fifth failure
- counters are keyed by agency + normalized service/force number
- lockout state is stored centrally in SQLite and survives process restarts
- successful authentication clears the central counter
- re-provisioning a responder clears the central lockout
- unknown service numbers use the same PBKDF2 workload and failure policy
- responder scopes are checked server-side before authentication succeeds

For a horizontally scaled deployment, move the two tables in
`security_responder_auth_server.py` to a shared transactional database such as
PostgreSQL. Do not run independent SQLite files behind a load balancer.

## Server deployment

Run the service behind TLS/reverse proxy. It binds to loopback by default.

Required server-side secret:

```bash
export USESF_ADMIN_PROVISION_TOKEN='replace-with-a-long-random-server-secret'
```

Optional settings:

```bash
export USESF_SECURITY_AUTH_DB=/var/lib/usesf/security_auth.sqlite3
export USESF_SECURITY_AUTH_HOST=127.0.0.1
export USESF_SECURITY_AUTH_PORT=8088
python3 -m server.security_responder_auth_server
```

The provisioning token is **server-side only**. Never compile it into the
Flutter application.

## Provision a responder

Provisioning is an administrative backend action. From a trusted admin host:

```bash
curl -X POST https://api.example.org/v1/security/responders/provision \
  -H "Authorization: Bearer $USESF_ADMIN_PROVISION_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "responderId": "RESP-001",
    "agencyId": "AGENCY-POLICE",
    "serviceNumber": "AP/12345",
    "displayName": "Insp. Musa Bello",
    "accessCode": "replace-with-issued-secret",
    "authorizedScope": {
      "level": "state",
      "country": "Nigeria",
      "zoneId": "NW",
      "stateId": "KD"
    }
  }'
```

## Flutter connected mode

Compile the client with only the public API base URL:

```bash
flutter build apk \
  --dart-define=USESF_API_BASE_URL=https://api.example.org/
```

No admin token is required or accepted by the client.

When the endpoint is configured:

- authenticated / rejected / locked server decisions are authoritative;
- TLS errors, malformed responses and HTTP server errors fail closed;
- DNS/refused-connection/socket unavailability and request timeouts fall back to
  the existing secure local verifier so emergency response can continue
  offline.

## Tests

From the repository root:

```bash
python3 -m unittest -v server.test_security_responder_auth_server
```
