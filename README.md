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

Normal self-registration requires PVC/VIN capture and a live selfie. The PVC image is used for extraction and is not retained. Structured PVC/VIN and home polling-unit data remain attached to the member profile.

The Kaduna State Coordinator has a separate command enrolment workflow. The coordinator may create a permanent member identity using full name plus at least one contact method (phone or email), without PVC, selfie, password or home polling unit. The new identity is created in Pending Activation state at Kaduna State scope and may receive authorized roles immediately.

A coordinator-created member activates the same permanent identity later by finding the account with phone or email and setting the first password. Password creation changes Pending Activation to Active; role assignments made before activation remain attached to the same member. Identity review does not bypass first-password activation.

A member signs in with PVC/VIN, phone number or email plus password. Phone and email are optional for normal PVC-based registration, while State Coordinator quick enrolment requires at least one of them. A verified email becomes the password-recovery anchor and can only be changed by the backend System Admin.

Phone numbers and email addresses supplied during member creation are checked against existing member identities to reduce duplicate enrolment.

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
- From Assignment Control or Field Monitoring, the State Coordinator may initiate operational calls only to members with a fresh active GPS heartbeat. Members without a current assignment can still be called when a fresh managed-device GPS heartbeat is available.
- Every operational call stores a per-recipient GPS snapshot with coordinates, capture time, device/source and assignment context where available; call start is rejected if any intended recipient lacks fresh GPS.
- Operational-call GPS uses a seven-minute live-monitoring freshness window. When a member answers, GPS is refreshed again; a stale location blocks answering until a fresh heartbeat is available.
- Assignment-linked calls retain participants, assignment/group linkage, GPS context, state, answer time and end time; media itself is not recorded by this workflow.
- Field Monitoring lets the State Coordinator call a group chairman by audio/video, call any GPS-active individual group member, conference the whole GPS-active group, or call the holder of an individual assignment.
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
- Result submission and State result review are separate responsibilities. Authorized field roles capture and submit polling-unit results; the State Coordinator does not receive the result-entry workspace.
- On supported Android/iOS devices, field result capture uses the camera, SHA-256 evidence hashing, a GPS capture attempt and on-device ML Kit OCR. OCR-extracted figures auto-fill the result form for human confirmation and are persisted separately from the submitted/manual figures.
- Unsupported OCR platforms still preserve the captured result form and route the record with OCR unavailable; the system never fabricates extracted figures.
- The State Coordinator's Result module is rendered as Result Intelligence. It accounts for every polling unit in the loaded canonical catalogue as Missing, Received, AI Review, Conflict, Disputed or Verified.
- State Result Intelligence scores each submission from stored evidence/integrity, GPS presence, arithmetic validation, polling-unit/submitter scope checks, duplicate/conflict state and OCR/manual comparison. AI findings are advisory; only an authorized human reviewer may Verify or Dispute a result.
- AI/OCR-extracted party figures are retained with the result record and remain auditable after synchronization/hydration.
- Multiple unresolved submissions for one polling unit remain a Conflict until competing records are disputed/rejected/archived or otherwise resolved. Rejected/archived submissions do not satisfy polling-unit result accounting.
- Result Intelligence may call a registered submitter through the existing GPS-bound operational-call workflow when that member has active GPS.
- Result Intelligence verifies individual polling-unit records; Collation aggregates verified records upward. A USESF Verified result remains an internally verified unofficial field result and is not an official electoral declaration.
- The State Coordinator's geography module is rendered as State Coverage Intelligence rather than the shared field Geographic Operations workspace.
- State Coverage Intelligence compares all 23 LGAs directly from the State view, then drills down LGA → Ward → Polling Unit while preserving the canonical Kaduna hierarchy.
- Coverage readiness is a transparent operational score, not a hidden AI score: polling-unit staffing contributes 30%, fresh GPS coverage among deployed members 25%, coordinate readiness 15%, expected coordinator-role coverage 15% and unresolved-incident health 15%.
- Areas with no loaded polling-unit catalogue are marked Catalogue Pending and do not receive a fabricated readiness score.
- The State coverage exception queue surfaces vacant coordinator roles, PU staffing gaps, stale/mismatched GPS, missing/review coordinates, unresolved incidents and—after result activity begins—missing or conflicting PU results.
- State Coverage Intelligence is review/intervention only: it does not expose field coordinate capture, evidence capture, incident submission or result submission controls.
- GPS-active area coordinators and deployed PU members may be contacted through the existing GPS-bound operational-call workflow, and PU drill-down links back to Assignment Control, Evidence Intelligence and Result Intelligence.
- The State Coordinator's member registry is rendered as Membership Intelligence rather than the shared Member Operations directory used by lower coordinators and field roles.
- Membership Intelligence accounts statewide for active accounts, Pending Activation identities, blocked/suspicious identities, members without roles, deployed members and GPS-active deployed members.
- Member readiness is transparent rather than a hidden AI score: active account state contributes 20%, identity readiness 20%, reachable phone/email 10%, at least one active role 15%, managed device 10%, home-PU linkage 10%, and live GPS 15% when deployed. Members without an active assignment are not penalized for lacking live GPS.
- Blocked/suspicious members always have zero operational readiness and remain blocked regardless of other profile completeness.
- Legacy system-derived members whose registry record was already verified before the newer identity-review field existed are treated as identity-ready migration records; genuinely pending or suspicious identities remain visible for human review.
- Membership Intelligence surfaces people exceptions such as no role, deployed without a managed device, deployed without fresh GPS, no contact method, no home PU, pending activation, identity review, blocked access and multiple coordinator posts.
- Leadership coverage separately accounts for Senatorial, all 23 LGA coordinator posts, loaded Ward coordinator posts and loaded Polling Unit coordinator posts, and lists the actual vacant scopes.
- Membership Intelligence may call a GPS-active member through the existing operational-call workflow and may hand off to Member Enrolment, Roles & Authorization, Assignment Control, State Coverage Intelligence and Result Intelligence.
- Membership Intelligence does not duplicate enrolment, role mutation or assignment creation; those remain authoritative in their dedicated modules.
- The State Coordinator's AI Verification module is rendered as State AI Review Centre and moved into the command/intelligence surface; lower authorized roles retain the existing scoped AI Verification workflow.
- State AI Review Centre builds its queue from real domain state rather than hard-coded review counts: identity-review state, active Assignment Edge AI findings/events, evidence-integrity exceptions and unresolved result validation/conflicts.
- The State AI queue is explainable. Every case records why it needs review, its scope/reference/member where available, severity and the authoritative workspace for follow-up.
- Derived assignment GPS/device findings are queued only after an assignment enters its operational lifecycle; a newly assigned job waiting for acceptance is not treated as a GPS anomaly. Explicit durable AI events may still surface at any lifecycle stage.
- Durable Assignment Edge AI events can be marked resolved by the State Coordinator after human review. Derived telemetry findings remain until the underlying GPS/device condition changes.
- Evidence without a stored cryptographic content hash is a critical integrity review case and is handed to Evidence Intelligence; the AI Review Centre does not fabricate an integrity decision.
- Result conflicts are deduplicated into one critical polling-unit review case, while non-conflicting results enter review only when their durable status/validation requires human attention.
- Identity cases are visible statewide, but identity approval/suspicious marking remains a backend/System Admin human-review authority. The State Coordinator is never given silent or automatic face/PVC approval authority by this module.
- State AI Review Centre hands cases to Membership Intelligence, Assignment Control, Evidence Intelligence and Result Intelligence rather than creating a second mutation path for those domains.
- AI never silently closes, verifies, approves or changes the underlying operational record.
- Role and assignment history remain auditable after deactivation.

## Product principles

- State Coordinator workspaces are command/intelligence surfaces: statewide visibility, accounting, exceptions, review and intervention. Field/coordinator/member workspaces remain execution surfaces: assigned work, capture, submission and local operations. Shared modules must reuse the same authoritative stores while presenting role-appropriate actions.
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
2. Member Operations / State Membership Intelligence
3. Roles & Authorization
4. Jobs & Assignment Control
5. Geographic Operations / State Coverage Intelligence
6. Field Monitoring / State Field Command Monitoring
7. AI Verification / State AI Review Centre
8. Evidence Capture / State Evidence Intelligence
9. Result Capture / State Result Intelligence
10. Collation
11. Situation Room and Live Operations
12. Communications, discussion and meeting rooms
13. Media Intelligence
14. Reporting, audit and governance
15. System Monitoring

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
