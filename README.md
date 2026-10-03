# USESF

**Uba Sani Engagement & Sensitization Forum**

*Engage • Sensitize • Empower • Transform*

USESF is a Flutter-based election operations platform for membership and agent accreditation, field monitoring, incident/evidence reporting, polling-unit result capture, hierarchical collation, GIS operations, communications and situation-room workflows.

## Scope: Kaduna State

USESF is a state-level programme covering Kaduna State only. Kaduna State is the operational root of every dashboard, role and report.

| | |
|---|---|
| Senatorial zones | 3 (Kaduna North, Kaduna Central, Kaduna South) |
| LGAs | 23 |
| Wards | 255 |
| Polling units | 8,012 |

Records still carry their full INEC address (country and geopolitical zone included) so that official catalogue imports and exports stay compatible, but no screen, role or report operates above the state.

LGA boundaries on the Kaduna map are from the GRID3 Nigeria administrative boundaries, distributed by [geoBoundaries](https://www.geoboundaries.org) under CC BY 4.0.

## Core hierarchy

```text
Kaduna State
  -> Senatorial Zone (Kaduna North / Central / South)
    -> LGA
      -> Ward / Registration Area
        -> Polling Unit
```

## Roles

State Administrator, State Collation Officer, Situation Room Director, State Coordinator, Senatorial Zone Coordinator, LGA Coordinator, Ward Coordinator, Polling Unit Agent, Observer, Legal Officer, Technical Support and Executive Viewer.

## Product principles

- Offline-first field operations.
- Server-side authorization; UI visibility is never treated as authorization.
- Every operational record has stable identity, provenance and auditability.
- Election-day campaign/observer submissions remain unofficial until declared by the legally authorized election authority.
- Result evidence is preserved separately from extracted or manually entered figures.
- AI/OCR assists verification; it must not silently alter submitted figures.
- Geographic scope is explicit on users, assignments, incidents, reports and results.
- App, SMS, USSD and manual submissions are source-tagged and reconciled.

## Initial modules

1. Authentication and accreditation
2. Membership and field-agent management
3. Kaduna State geography and polling-unit catalogue
4. Monitoring and incident management
5. Evidence capture
6. Result submission and verification
7. Hierarchical collation
8. Situation Room
9. Communications
10. GIS and geofencing
11. SMS/USSD fallback
12. Audit, reporting and governance

## Architecture direction

```text
Flutter clients
  -> repository contracts
    -> encrypted local storage + durable sync outbox
      -> backend APIs
        -> PostgreSQL/PostGIS
        -> Redis / queues
        -> object storage
        -> OCR / biometric services
        -> SMS / USSD gateways
```

The Flutter domain layer is kept backend-agnostic so development can begin with local implementations while preserving a clean path to production APIs and offline synchronization.
