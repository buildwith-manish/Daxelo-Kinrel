# Track C v2.0 — API Reference

Base URL: `/api/v1`
Auth: Supabase JWT in `Authorization: Bearer <token>`
Idempotency: All mutating endpoints accept `Idempotency-Key` header (24h cache)
Rate limits (per-user-per-family, sliding window):
- Read endpoints: 600 req/min
- Mutating endpoints: 120 req/min
- AI endpoints: 30 req/min, 1000 req/day, plus daily token budget
Pagination: Cursor-based (`?cursor=...&limit=50`), max limit 100
Errors: RFC 7807 problem+json
Realtime: Supabase Realtime channels scoped by `familyId`

---

## Constitution

### `GET /families/{familyId}/constitution`
Returns the family's constitution (current published version + draft if exists). Auto-creates an empty shell if none exists.

### `POST /families/{familyId}/constitution/draft`
**Admin-only.** Create or replace the draft version of the constitution.

**Body:**
```json
{
  "title": "Sharma Family Constitution",
  "preamble": "We, the Sharma family...",
  "articles": [
    {
      "title": "Annual Family Gathering",
      "intent": "Ensure annual reunion happens",
      "clauses": [
        { "text": "The family will gather annually during Diwali.", "intent": "Diwali is the anchor" }
      ]
    }
  ]
}
```

### `POST /families/{familyId}/constitution/publish`
**Admin-only.** Publish the current draft. Makes the version immutable. Marks the previous version as superseded. Emits `constitution_version_published` (and `constitution_created` if first publication, or `constitution_amended` if subsequent) timeline events.

### `GET /families/{familyId}/constitution/versions`
List all versions (drafts, published, superseded).

### `GET /families/{familyId}/constitution/versions/{versionId}`
Get a single version with full articles + clauses.

### `POST /families/{familyId}/constitution/amend`
**Admin-only.** Open an amendment decision (type=`constitution_amend`, quorum≥67%). The amendment is applied only if the decision resolves with supermajority.

---

## Decisions

### `GET /families/{familyId}/decisions?status=open&lifecycleState=planned&cursor=...`
List decisions. Optional filters: `status`, `lifecycleState`, cursor pagination.

### `POST /families/{familyId}/decisions`
Create a new decision.

**Body:**
```json
{
  "title": "Choose destination for summer vacation",
  "description": "Decide between Goa, Kerala, and Himachal.",
  "type": "simple_vote",
  "options": ["Goa", "Kerala", "Himachal"],
  "quorumPct": 50,
  "showVotesLive": false,
  "deadlineAt": "2026-07-20T00:00:00Z"
}
```

### `GET /families/{familyId}/decisions/{decisionId}`
Get a decision with its votes, memory, and impacts.

### `PATCH /families/{familyId}/decisions/{decisionId}`
Update title/description/deadline. Only allowed while status=open.

### `POST /families/{familyId}/decisions/{decisionId}/vote`
Cast a vote. Append-only — duplicate votes return 409 Conflict.

**Body:** `{ "option": "Goa" }`

### `POST /families/{familyId}/decisions/{decisionId}/resolve`
Compute quorum + pass criterion. Sets status=resolved, lifecycleState=planned. Emits `decision_resolved` (or `decision_expired` if quorum not met).

### `POST /families/{familyId}/decisions/{decisionId}/cancel`
Cancel an open decision.

### `PATCH /families/{familyId}/decisions/{decisionId}/lifecycle`
Transition the post-resolution lifecycle. Emits `decision_lifecycle_changed`.

**Body:** `{ "to": "started" }`

Allowed transitions:
- `null → planned` (only via resolve)
- `planned → started | cancelled | expired | archived`
- `started → in_progress | cancelled | expired | archived`
- `in_progress → completed | cancelled | expired | archived`
- `completed | cancelled | expired → archived`

### `GET /families/{familyId}/decisions/{decisionId}/memory`
Get the post-resolution memory record.

### `POST /families/{familyId}/decisions/{decisionId}/memory`
Upsert the memory record.

### `POST /families/{familyId}/decisions/{decisionId}/impacts`
Add an impact milestone.

### `PATCH /families/{familyId}/decisions/{decisionId}/impacts/{impactId}`
Update an impact milestone (mark completed, add evidence, etc.).

---

## Kinrel Timeline

### `GET /families/{familyId}/timeline?kind=decision_resolved&cursor=...`
List timeline events. Optional `kind` filter (CSV for multiple). Cursor pagination on `occurredAt`.

### `GET /families/{familyId}/timeline/export?format=pdf|json&year=2026`
Export the timeline. PDF returns print-ready HTML (client triggers print-to-PDF). JSON returns the raw event stream (chunked by year for >10MB).

### `GET /families/{familyId}/timeline/{eventId}`
Get a single event.

### `GET /families/{familyId}/timeline/{eventId}/corrections`
Get all corrections for an event (kind=correction rows with parentEventId=this).

### `POST /families/{familyId}/timeline/{eventId}/correct`
Append a correction event. The original event is NEVER mutated (DB trigger).

**Body:**
```json
{
  "correctedFields": {
    "title": { "from": "Old title", "to": "Corrected title" }
  },
  "note": "Typo in original"
}
```

---

## Kinrel Intelligence

### `POST /families/{familyId}/decisions/{decisionId}/insights/request`
Request one or more insights. Returns cached insights immediately; generates new ones synchronously if circuit is closed and budget remains.

**Body:** `{ "kinds": ["decision_analysis", "pros_cons", "duplicate_detection"] }`

**Response:**
```json
{
  "cached": [...],
  "generated": [...],
  "degradedMode": false,
  "queued": false
}
```

### `GET /families/{familyId}/decisions/{decisionId}/insights?kind=...`
List insights for a decision.

### `POST /insights/{insightId}/accept`
Mark an insight as accepted. (Note: this endpoint is at the top level, not under families, because the insight ID is globally unique.)

**Body:** `{ "familyId": "fam1" }`

### `POST /insights/{insightId}/dismiss`
Mark an insight as dismissed. Records a `insight_dismissed` learning signal.

**Body:**
```json
{
  "familyId": "fam1",
  "reason": "not_relevant"
}
```

Allowed reasons: `not_relevant`, `already_known`, `too_prescriptive`, `other`.

---

## Kinrel Learning Engine

### `GET /families/{familyId}/learning/profile`
Get the family's behavior profile. Returns global defaults if `confidenceScore < 0.4`.

### `POST /families/{familyId}/learning/signals`
Ingest a client-side signal (e.g. reminder dismissed, insight accepted).

**Body:**
```json
{
  "signalType": "reminder_dismissed",
  "targetType": "SmartReminder",
  "targetId": "rem1",
  "payload": { "leadHours": 24 }
}
```

### `POST /families/{familyId}/learning/reset`
**Admin-only.** Reset the behavior profile to defaults. Logs a `learning_profile_reset` timeline event. Previous profile version retained in `FamilyBehaviorProfileHistory` for 90 days.

**Body:** `{ "reason": "user_request" }`

### `POST /families/{familyId}/learning/recompute`
**Admin-only.** Trigger an immediate profile recompute (normally done by nightly pg-boss worker).

---

## Kinrel Search

### `GET /families/{familyId}/search?q=trip&entityType=decision&limit=20`
Universal search. Uses Postgres tsvector + GIN index. Ranking: `ts_rank_cd × boostedScore`.

### `GET /families/{familyId}/search/suggest?q=tr`
Autocomplete. Returns up to 10 distinct titles matching the prefix.

### `POST /families/{familyId}/search/reindex`
**Admin-only.** Trigger an immediate full reindex of all entities for the family. (Normally done incrementally by hourly pg-boss worker.)

---

## Kinrel Secretary

### `POST /families/{familyId}/secretary/artifacts`
Create a new meeting artifact. Generates draft minutes via LLM (with PII redaction). Extracts action items.

### `GET /families/{familyId}/secretary/artifacts?status=draft&limit=50`
List artifacts.

### `GET /families/{familyId}/secretary/artifacts/{artifactId}`
Get a single artifact.

### `PATCH /families/{familyId}/secretary/artifacts/{artifactId}/draft`
Edit the draft minutes (Markdown). Only allowed while status=draft or reviewed.

### `POST /families/{familyId}/secretary/artifacts/{artifactId}/publish`
**Admin-only.** Publish the artifact. Emits `meeting_artifact_published` timeline event. Published artifacts are immutable.

---

## Kinrel Analytics

### `GET /families/{familyId}/analytics/snapshots?granularity=weekly&from=...&to=...`
List snapshots. Up to 52 returned (1 year of weekly).

### `GET /families/{familyId}/analytics/summary?granularity=weekly`
Get the latest snapshot + trend vs prior period. If no snapshot exists, computes one on the fly.

### `POST /families/{familyId}/analytics/trigger?granularity=weekly`
**Admin-only.** Trigger an immediate snapshot.

---

## Sync

### `GET /sync/delta?since={watermark}&families={csv}`
Delta sync. Returns all rows where `updatedAt > watermark` for the families the user is a member of. Updates the per-device `SyncWatermark`.

**Headers:** `X-Device-Id: <device-uuid>` (required)

**Response:**
```json
{
  "watermark": "2026-07-09T16:00:00.000Z",
  "clamped": false,
  "changes": {
    "constitutions": [...],
    "decisions": [...],
    "votes": [...],
    "timelineEvents": [...],
    ...
  },
  "deletions": {}
}
```

Edge case #15: If `since` is in the future (clock skew), server clamps to `now()` and returns `clamped: true`.

### `POST /sync/push`
Push offline mutations from the client outbox. Idempotent per `clientOpId`. LWW conflict resolution.

**Body:**
```json
{
  "operations": [
    {
      "kind": "create",
      "entity": "decision",
      "op": "vote",
      "payload": { "familyId": "fam1", "decisionId": "dec1", "option": "Goa" },
      "clientOpId": "op_001"
    }
  ]
}
```

**Response:**
```json
{
  "applied": [{ "clientOpId": "op_001", "result": { "id": "vote_1", ... } }],
  "conflicts": [],
  "rejected": []
}
```

**Operations supported:**
- `decision/vote` — cast a vote (idempotent if already voted)
- `decision/editTitle` — LWW on title
- `decision/editDescription` — LWW on description
- `decision/lifecycle` — lifecycle state transition
- `constitution/editClause` — clause text edit (admin-only)
- `reminder/snooze` — snooze a reminder
- `reminder/dismiss` — dismiss a reminder
- `reminder/act` — mark reminder as acted upon

Edge case #16: Operations rejected by RLS are marked `rejected` and not retried.

---

## Error responses (RFC 7807)

All errors return:
```json
{
  "type": "https://kinrel.app/errors/forbidden",
  "title": "Forbidden",
  "status": 403,
  "detail": "You are not an eligible voter for this decision",
  "instance": "/api/v1/families/fam1/decisions/dec1/vote"
}
```

Common status codes:
- 400 — `BadRequestException` (validation failed)
- 401 — Unauthorized (missing/invalid JWT)
- 403 — Forbidden (RLS denied, or role insufficient)
- 404 — NotFound (family/decision/etc. not found, or user not a member)
- 409 — Conflict (state machine violation, double-vote, etc.)
- 410 — Gone (voting after deadline — mapped to 409 in current implementation)
- 429 — Too Many Requests (rate limit OR AI budget exhausted — check `degraded_mode` flag)
- 503 — Service Unavailable (AI circuit breaker open — `degraded_mode: true` in response)
