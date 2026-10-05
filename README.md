# USESF

**Uba Sani Engagement & Sensitization Forum**

*Engage • Sensitize • Empower • Transform*

USESF is a Flutter-based, offline-first operational platform for member registration, role and assignment management, geographic coordination, field monitoring, incident/evidence reporting, communications, meetings, result capture, reporting and situation-room workflows.

## Scope: Kaduna State

USESF is a state-level programme covering Kaduna State. Kaduna State is the operational root of the current deployment.

| | |
|---|---|
| Senatorial districts | 3 (Kaduna North, Kaduna Central, Kaduna South) |
| LGAs | 23 |
| Wards / Registration Areas | 255 |
| Polling units | 8,012 |

Records retain the full geographic address required for authoritative catalogue imports and exports.

## Member-first identity

The permanent identity model is:

```text
Member
  -> zero or more active roles
  -> zero or more active assignments
  -> combined scope-aware permissions
```

A person is registered once as a member. Agent, coordinator and functional responsibilities are roles attached to that member rather than separate identities.

Normal self-registration requires PVC/VIN capture and a live selfie. The PVC image is used for extraction and is not retained. Structured PVC/VIN and home polling-unit data remain attached to the member profile. State Coordinator and backend System Admin are the authorized exception for creating a member without PVC.

A member signs in with PVC/VIN, phone number or email plus password. Phone and email are optional at initial registration. A verified email becomes the password-recovery anchor and can only be changed by the backend System Admin.

A member with neither an active role nor an active assignment remains in the restricted waiting workspace.

## Operational hierarchy

```text
State Coordinator
  -> Senatorial District Coordinator
    -> LGA Coordinator
      -> Ward Coordinator
        -> Polling Unit Coordinator
          -> Polling Unit Agent
```

The backend System Admin is a technical authority and is intentionally not exposed as a normal operational role in the app UI.

Functional roles can also be scoped geographically. Current standard roles include Media Officer, Women Mobilization Coordinator, Youth Mobilization Coordinator, Communications Officer, Logistics Officer, Monitoring & Evaluation Officer, Data & Evidence Officer, Transport Coordinator, Training Officer and ICT Officer, alongside legal, technical, observer and result/collation responsibilities.

Members may hold multiple compatible roles simultaneously. Effective access is the union of active role permissions and active assignment permissions, evaluated against the scope attached to each grant.

## Assignments

Assignments are separate from roles.

- A member may have multiple active assignments.
- Coordinators create individual assignments only within their authorized level and scope.
- An individual assignment may be tied to a polling unit or may be location-flexible for special work.
- The State Coordinator may create a group assignment spanning one or more selected Kaduna geographic targets.
- Group membership may be selected manually or derived from the selected geography.
- Group movement may be together, manually distributed member-by-member, or automatically distributed across the selected targets.
- Every group has one chairman, selected by the State Coordinator or assigned automatically by the system.
- Only the group chairman submits the group assignment; members do not submit separate completion records.
- Group GPS telemetry, AI-derived records and operational intelligence are internal system data and are not exposed on member-facing group assignment screens.
- Temporary capabilities on a group assignment remain constrained to the group's selected geographic targets, including when the group moves together.
- The coordinator can grant only the temporary app capabilities needed for the assignment and only from authority they already possess.
- Assignment-only access disappears automatically when the assignment is completed, cancelled or removed.
- GPS remains required for evidence capture and individual assignment completion; group submission is chairman-controlled while member telemetry is retained internally.
- Role and assignment history remain auditable after deactivation.

## Product principles

- One person, one permanent member identity.
- Offline-first field operations with a durable synchronization outbox.
- Scope-aware authorization; UI visibility is never treated as authorization.
- Multiple active roles and assignments combine automatically without manual role switching.
- Every operational record has stable identity, provenance and auditability.
- Result submissions remain unofficial until declared by the legally authorized election authority.
- Result evidence is preserved separately from extracted or manually entered figures.
- AI/OCR assists review; it must not silently alter submitted figures.
- Member identity approval is a backend human-review process; operational UI does not automatically approve a face match.
- App, SMS, USSD and manual submissions remain source-tagged and reconcilable.

## Main modules

1. Member self-registration and authentication
2. Member Operations
3. Roles & Authorization
4. Jobs & Assignment Control
5. Kaduna geography and polling-unit registry
6. Field Monitoring & Incident Capture
7. Evidence Capture
8. Result Capture & Verification
9. Collation
10. Situation Room and Live Operations
11. Communications, discussion and meeting rooms
12. Media Intelligence
13. Reporting, audit and governance
14. System Monitoring

## Architecture direction

```text
Flutter clients
  -> repository / controller layer
    -> encrypted local storage + durable sync outbox
      -> backend APIs
        -> PostgreSQL/PostGIS
        -> Redis / queues
        -> object storage
        -> OCR / review services
        -> SMS / USSD gateways
```

The current Flutter domain layer remains backend-agnostic. Production server authentication, authoritative backend authorization, synchronization transport, cloud object storage, background device telemetry and production AI services still require their backend integrations.

## Development status

The repository contains a working local/offline-first application foundation and presentation data. Production API transport and server-side identity/authorization are not yet configured.

The member-first access model is the source of truth for new development. Legacy accreditation data structures may remain temporarily for migration compatibility, but new UI and workflows should use member roles and assignments rather than create separate agent identities.
