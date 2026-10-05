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
- Group cancellation is handled at the group level by the State Coordinator so child assignments close consistently.
- From Assignment Control, the State Coordinator may initiate direct audio/video call sessions to any active registered Kaduna member, including members without a current assignment.
- Assignment-linked calls retain call metadata such as participants, assignment/group linkage, state, answer time and end time; media itself is not recorded by this workflow.
- Group Assignment Control supports a direct chairman call and a conference invitation to the selected group members.
- Incoming operational calls are surfaced globally for signed-in members, regardless of which authorized module they are currently viewing.
- Remote audio/video transport still requires the production signaling/WebRTC provider; the current Flutter layer provides call-session orchestration, incoming-call state and local camera/call controls.
- If a polling unit has no operational coordinate, the State Coordinator may enter latitude/longitude from Assignment Control. The coordinate becomes a persistent reusable reference coordinate with an audit mutation.
- Manual Assignment Control coordinate entry never silently overwrites an existing reference or field-verified operational coordinate.
- Group GPS telemetry, AI-derived records and operational intelligence are internal system data and are not exposed on member-facing group assignment screens.
- Assignment Control includes a private Assignment Edge AI monitor for assignment managers; members do not receive the AI score, findings or event ledger.
- The current Edge AI foundation actively evaluates GPS integrity and managed-device integrity from fresh local telemetry, producing an assignment health score and internal findings.
- Assignment Edge AI profiles support Normal, Verification, Event and Emergency monitoring modes and persist through encrypted offline storage/outbox sync.
- AI events retain type, severity, source, confidence, optional evidence reference, resolution state and assignment scope. The event schema is ready for image-quality, video-verification, audio-event, identity, crowd, OCR/location-corroboration and evidence-integrity detectors as those on-device models are implemented.
- Image/video/audio detectors are not treated as active merely because their event types exist; they must be backed by real on-device capture/inference before being enabled as working detectors.
- Submitted individual and group assignments open a historical AI report from the Submitted register. The report assesses stored completion GPS, evidence, assignment timeline and recorded AI events as they existed at submission rather than re-scoring old work from current live telemetry.
- Submitted group AI reports aggregate all child assignments and their evidence under the chairman's submitted group record.
- Evidence entries in a submitted AI report are individually clickable for capture metadata, GPS, integrity/reference fields and uploader details when available.
- Evidence viewing and evidence capture are separate permissions. The State Coordinator has statewide evidence visibility but does not receive field capture controls.
- The State Coordinator's Evidence module is rendered as Evidence Intelligence and aggregates direct captures, assignment evidence, incident evidence, field-report evidence and result-form evidence across the authorized state scope.
- Evidence Intelligence supports filtering by source, evidence type, LGA and AI-review state, and every evidence record opens into its uploader, source/reference, geographic scope, capture time, GPS, integrity metadata, AI events and linked assignment/result/incident context.
- Direct field captures are stored in the shared encrypted evidence registry and become visible to authorized Evidence Intelligence reporting after synchronization.
- Coordinators with assignment-management authority may delegate the temporary Capture evidence capability to field members even when the coordinator's own interface is review-only.
- Temporary capabilities on a group assignment remain constrained to the group's selected geographic targets, including when the group moves together.
- The coordinator grants only the temporary app capabilities needed for the assignment; evidence capture may be delegated through assignment-management authority even when the coordinator's own evidence interface is review-only.
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
7. Evidence Capture / State Evidence Intelligence
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
