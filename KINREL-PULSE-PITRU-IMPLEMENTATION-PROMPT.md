# Kinrel Pulse + Pitru — Complete Implementation Prompt

> **Paste this entire file into a fresh chat to continue the build.**
> The new chat will have full context: the vision, the build plan, all credentials, and what's already been done.

---

## 0. Project Overview

**Daxelo Kinrel** is an Indian family relationship intelligence app (Flutter + NestJS + Supabase). It maps kinship across 7 Indian languages with a graph-first architecture.

**The vision**: Build three pillars that make the app unfireable from a phone:
1. **Kinrel** (already built) — Family identity crest generated from graph topology. Festival-level engagement.
2. **Pulse** (in progress) — Daily 7am personalized family intelligence brief. The "WhatsApp chat" daily driver.
3. **Pitru** (next) — Ancestral voice memory with AI persona. The forever lock-in.

**Plus 10 addictiveness features** that layer across Pulse + Pitru:
- Kinrel Streaks (connection streaks between pairs)
- Family Karma (invisible social currency, tied to Kinrel roles)
- Relationship Weather (per-pair emotional climate: sunny/cloudy/stormy)
- Memory Orbits (memories resurface on anniversaries + festivals)
- Blessing Chain (elders record blessings, scheduled delivery on birthdays/festivals)
- Family Quests (weekly AI-generated missions targeting weak relationships)
- Silent Alarms (private inactivity nudges to the family "bridge")
- Time Capsule (lock messages for future dates — child's 18th, wedding, after death)
- Family Chronicle (AI-written family history book, auto-updated monthly)
- Festival Intelligence (7-language Indian festival calendar with culturally-aware theming)

**The single-sentence pitch**: *"Daxelo Kinrel is the only app that knows your family well enough to tell you, every morning, who needs you today — and keeps your grandmother's voice alive forever."*

---

## 1. Credentials & URLs

> **⚠️ SECURITY NOTE**: All secrets below are redacted as `[REDACTED:xxx]` placeholders to pass GitHub Push Protection. The actual values were provided in the original chat. If you're the repo owner, fill them in from your password manager / the original chat. If you're a new chat continuing this work, ask the user to provide the actual values.

**GitHub:**
- Repo: `https://github.com/buildwith-manish/Daxelo-Kinrel`
- PAT: `[REDACTED:github_pat]` — GitHub Personal Access Token with `repo` scope

**Supabase (production database + auth + realtime):**
- Project URL: `https://promxswvsnvilplmrtsj.supabase.co`
- Access token (PAT): `[REDACTED:supabase_pat]` — starts with `sbp_`
- Project ref: `promxswvsnvilplmrtsj`
- Database URL (pooler, port 6543 — for runtime): `postgresql://postgres.promxswvsnvilplmrtsj:[REDACTED:db_password]@aws-1-ap-southeast-1.pooler.supabase.com:6543/postgres`
- Direct URL (port 5432 — for migrations, may be IPv6-only): `postgresql://postgres:[REDACTED:db_password]@db.promxswvsnvilplmrtsj.supabase.co:5432/postgres`
- **Important**: When using Prisma with the pooler, append `?pgbouncer=true&prepare=false` to the connection string to avoid "prepared statement does not exist" errors.
- Service role key: `[REDACTED:supabase_service_role_key]` — JWT starting with `eyJ...` with `"role":"service_role"`
- Anon key: `[REDACTED:supabase_anon_key]` — JWT starting with `eyJ...` with `"role":"anon"`

**Render (NestJS backend hosting):**
- Service URL: `https://daxelo-kinrel-server.onrender.com`
- Health: `https://daxelo-kinrel-server.onrender.com/api/health`
- API token: `[REDACTED:render_token]` — starts with `rnd_`
- Service ID: `srv-d8gpvc5ckfvc73d1ctrg`
- DATABASE_URL and DIRECT_URL are already set as env vars on Render (verified via Render API).

**Vercel (Flutter web hosting):**
- Production URL: `https://daxelo-kinrel.vercel.app`
- Project ID: `prj_N8xJJpSuL073ulQYN4HLi7CwXA3Q`
- Auto-deploys from `main` branch on GitHub.

---

## 2. Repository Structure

```
Daxelo-Kinrel/
├── Daxelo-Kinrel-App/        # Flutter app (web + mobile)
├── server/                    # NestJS backend (TypeScript + Prisma)
│   ├── src/
│   │   ├── kinrel-intelligence/              # ✅ Kinrel — COMPLETE (Phases 1-6)
│   │   ├── pulse/             # 🚧 Pulse — IN PROGRESS (Phase 1 partial)
│   │   ├── modules/           # Existing modules (auth, families, graph, etc.)
│   │   └── app.module.ts
│   └── prisma/schema.prisma   # Prisma schema (includes Kinrel + Pulse models)
├── supabase/migrations/       # SQL migrations (applied to live DB)
└── scripts/                   # Test/validation scripts
```

---

## 3. What's Already Built (DO NOT redo)

### Kinrel — COMPLETE ✅ (6 phases, deployed to production)

**Migration:** `supabase/migrations/20260708010000_create_kinrel_tables.sql` (applied live)
- 3 tables: `FamilyKinrel`, `FamilyKinrelHistory`, `MemberKinrelRole`
- RLS: 12 policies (family members SELECT, service_role writes)
- Realtime: `FamilyKinrel` + `MemberKinrelRole` in `supabase_realtime` publication
- Prisma models in `server/prisma/schema.prisma`

**NestJS services** (in `server/src/kinrel-intelligence/`):
- `graph-metrics.ts` — pure computation (Brandes betweenness, BFS generations, clustering, lineage, language distribution). Validated against hand-computed test graph — all 30+ metrics match.
- `graph-analysis.service.ts` — NestJS wrapper, loads from Prisma
- `archetype-classifier.service.ts` — 6 archetypes (banyan, river_delta, confluence, spine, lotus, forest) with 8-language names. Validated against 5 test cases.
- `kinrel-parameter-generator.service.ts` — symbol math (rings, spokes, colors, pulse). Validated against 4 test cases with exact hex matches.
- `role-glyph.service.ts` — per-member role classification (root/anchor/bridge/weaver/leaf/twin_node)
- `kinrel-orchestration.service.ts` — main coordinator: graph→classify→params→upsert→history→roles. Bug fixed: `archetypeChanged=false` on first computation.
- `kinrel-query.service.ts` — read queries with family membership verification
- `kinrel.controller.ts` — REST: `GET /kinrel-intelligence/:familyId`, `/roles`, `/history`; `POST /recompute`
- `kinrel-event.listener.ts` — listens to 6 domain events, 2s debounce, triggers recompute. Bug fixed: FK validation for deleted persons.
- `kinrel.module.ts` — wires all providers

**EventEmitter integration:**
- `@nestjs/event-emitter` installed and `EventEmitterModule.forRoot()` registered in `app.module.ts`
- `SupabaseRealtimeService` (in `server/src/modules/realtime/supabase-realtime.service.ts`) modified to emit domain events (`family.member.added`, `family.relationship.created`, etc.) when Person/Relationship changes occur

**Test scripts** (in `scripts/`):
- `test_graph_analysis.ts`, `test_archetype_classifier.ts`, `test_parameter_generator.ts`, `test_kinrel_orchestration.ts`, `test_kinrel_event_listener.ts`

### Pulse — IN PROGRESS 🚧 (Phase 1 partial)

**Migration:** `supabase/migrations/20260708020000_create_pulse_tables.sql` (applied live)
- 6 tables: `DailyBrief`, `BriefItem`, `BriefInteraction`, `RelationshipWeather`, `ConnectionStreak`, `FamilyKarma`
- RLS: 24 policies (4 per table)
- Realtime: `DailyBrief` in `supabase_realtime` publication
- Prisma models added to `schema.prisma` (DailyBrief, BriefItem, BriefInteraction, RelationshipWeather, ConnectionStreak, FamilyKarma) with back-relations on User, Family, Person
- `prisma generate` succeeds

**NestJS services** (in `server/src/pulse/`):
- ✅ `brief-types.ts` — pure types (BriefItemData, BriefCollector, BriefCollectorContext, GREETINGS, ACTION_LABELS for 8 languages)
- ✅ `brief-generator.service.ts` — orchestrator: loads user context, runs collectors in parallel, merges/sorts/caps items, generates summary, persists DailyBrief + BriefItem rows. Includes `generateBriefForUser()`, `generateBriefsForFamily()`, `generateAllBriefs()`.
- ❌ **NOT YET WRITTEN**: the 6 collectors (Birthday, Inactivity, FeedHighlights, OnThisDay, Weather, MemoryOrbit)
- ❌ **NOT YET WRITTEN**: `pulse.controller.ts`, `pulse.module.ts`, AppModule registration
- ❌ **NOT YET WRITTEN**: validation script
- ❌ **NOT YET WRITTEN**: daily 7am cron job

---

## 4. What Needs To Be Built

### Pulse Phase 1 (finish the current phase)

**4.1 Write 6 brief collectors** in `server/src/pulse/collectors/`:
- `birthday.collector.ts` — finds family members with birthdays in the next 7 days. Query `Person.dateOfBirth` (or `birthYear` for year-only). Compute days until birthday. Generate `birthday` items with priority based on closeness (parent/child = 90, sibling = 80, cousin = 60, other = 40).
- `inactivity.collector.ts` — finds family members who haven't been active in 4+ days. Use `User.updatedAt` or `Person.updatedAt` as last-active proxy. Generate `inactivity` or `need_you` items. Priority: elders (age ≥ 60) get `need_you` at priority 95; others get `inactivity` at priority 50.
- `feed-highlight.collector.ts` — finds top FamilyFeedPost entries from the last 24h that the user hasn't reacted to. Query `FamilyPost` where `createdAt > now - 24h` and the user hasn't interacted. Priority 60, actionType `view_post`.
- `on-this-day.collector.ts` — finds Sparqs or FamilyPosts from previous years on this same date. Query `Sparq` where `date_trunc('day', createdAt) = briefDate` in any previous year. Priority 70, actionType `view_sparq`.
- `weather.collector.ts` — finds RelationshipWeather rows for this user where `weather != 'sunny'`. For each cloudy/stormy relationship, generate a `weather` item. Priority: stormy=85, rainy=75, cloudy=65, partly_cloudy=40.
- `memory-orbit.collector.ts` (STUB for now) — Pitru memories will resurface on anniversaries. For Phase 1, return `[]` (Pitru doesn't exist yet). The stub is important so the orchestrator already calls it — when Pitru ships, this collector lights up.

**Each collector must:**
- Implement the `BriefCollector` interface from `brief-types.ts`
- Be defensive: return `[]` on any error (never throw — a single collector failure must not break the brief)
- Use the `BriefCollectorContext` (userId, familyId, briefDate, userLanguageCode, familyArchetype)
- Localize item titles/bodies using the `userLanguageCode` (use English as fallback)

**4.2 Write `pulse.controller.ts`:**
- `GET /pulse/today` — returns today's brief for the authenticated user (or generates it on-demand if it doesn't exist yet)
- `GET /pulse/:date` — returns a specific date's brief (for history browsing)
- `POST /pulse/:briefId/interact` — records a BriefInteraction (call, message, view, etc.) and awards karma
- `GET /pulse/weather` — returns all RelationshipWeather rows for the user
- `GET /pulse/streaks` — returns all ConnectionStreak rows for the user
- `GET /pulse/karma` — returns the user's FamilyKarma across all their families

All endpoints require JWT auth (global `JwtAuthGuard`). Use `@CurrentUser('id')` decorator for the userId.

**4.3 Write `pulse.module.ts`:**
- Register `BriefGeneratorService`, all 6 collectors, `PulseQueryService` (read queries), `PulseController`
- Use `OnModuleInit` to call `briefGeneratorService.setCollectors([...all collectors])` after DI resolves
- Export `BriefGeneratorService` (for the cron job to use)

**4.4 Register `PulseModule` in `app.module.ts`** (next to `KinrelModule`)

**4.5 Write the daily 7am cron:**
- Use `@nestjs/schedule` (already installed — `ScheduleModule.forRoot()` is registered)
- Create `pulse-cron.service.ts` with `@Cron('0 7 * * *')` that calls `briefGeneratorService.generateAllBriefs()`
- Also add a `@Cron('0 1 * * *')` (1am) job to compute RelationshipWeather for all pairs (so it's ready by 7am)
- Register the cron service in `PulseModule`

**4.6 Write validation script** (`scripts/test_pulse_brief.ts`):
- Find a real user from the live DB (one who has a family with members)
- Call `briefGeneratorService.generateBriefForUser(userId)`
- Verify: DailyBrief row created, BriefItem rows created, items have correct types/priorities/relevance
- Test the `GET /pulse/today` endpoint shape (by calling the query service directly)
- Clean up test rows after

**4.7 Apply + verify:** TypeScript compiles (`tsc --noEmit`), NestJS builds (`nest build`), validation script passes on live DB.

### Pulse Phase 2-6 (after Phase 1 validates)

- **P-2**: Brief collectors deep-dive (graph-aware personalization using Kinrel roles + relationship closeness)
- **P-3**: Push notification delivery via FCM (the `deliveredAt` field on DailyBrief)
- **P-4**: Relationship Weather computation algorithm (interaction frequency + sentiment scoring)
- **P-5**: Connection Streaks tracking (hook into chat/call events)
- **P-6**: Family Karma scoring (karma rules per interaction type, tied to Kinrel roles)

### Pitru (after Pulse validates daily engagement)

- **Pt-1**: Pitru schema — `AncestralMemory` table (voice/video upload, transcription, translation, graph tags)
- **Pt-2**: Recording flow — Flutter UI for elders to record, NestJS upload endpoint, Whisper transcription, GPT translation
- **Pt-3**: Graph tagging — AI tags memories by person/topic/event, attaches to Person nodes
- **Pt-4**: Playback + memorial mode — when a Person is marked deceased, their node becomes a living memorial
- **Pt-5**: AI persona (consent-gated) — conversational AI using recorded memories as knowledge base, voice cloning with consent

### Addictiveness features (layer across Pulse + Pitru)

- **A-1**: Blessing Chain — elder blessing recording + scheduled delivery on birthdays/festivals
- **A-2**: Time Capsule — locked messages with future unlock dates
- **A-3**: Family Quests — weekly AI-generated quests from graph weak points
- **A-4**: Silent Alarms — inactivity detection + private nudges to the bridge role
- **A-5**: Memory Orbits — anniversary/festival resurfacing scheduler (lights up the Phase 1 stub)
- **A-6**: Festival Intelligence — 7-language Indian festival calendar with culturally-aware theming
- **A-7**: Family Chronicle — AI-written family history, monthly auto-update

---

## 5. Critical Architecture Patterns (follow these exactly)

### 5.1 Database conventions
- **All table names are PascalCase, quoted**: `"DailyBrief"`, `"BriefItem"`, etc. (matches existing convention)
- **All column names are camelCase, quoted** in SQL: `"userId"`, `"familyId"`, `"briefDate"`. PostgreSQL lowercases unquoted identifiers — this is critical.
- **Foreign keys**: `TEXT` (cuid) referencing `public."Family"("id")`, `public."Person"("id")`, or `public."User"("id")` with `ON DELETE CASCADE ON UPDATE CASCADE` (matching existing FKs). Nullable FKs to Person use `ON DELETE SET NULL`.
- **Timestamps**: `TIMESTAMPTZ NOT NULL DEFAULT NOW()` for `createdAt`, `updatedAt`, `computedAt`, etc.
- **RLS pattern**: family members can SELECT (via FamilyMember join), service_role can INSERT/UPDATE/DELETE. Defense-in-depth: GRANT only SELECT to anon/authenticated, REVOKE all write privileges, GRANT ALL to service_role.
- **Realtime**: `ALTER TABLE ... REPLICA IDENTITY FULL` + add to `supabase_realtime` publication via `DO $$ ... $$` block (idempotent).

### 5.2 NestJS conventions
- **Pure computation files** (like `graph-metrics.ts`, `brief-types.ts`) have **zero NestJS dependencies** — they can be unit-tested standalone with `bun`.
- **Services** are `@Injectable()` and inject `PrismaService` (which is `@Global()`).
- **PrismaModule is @Global()** — don't import it in feature modules.
- **EventEmitter2** is available globally — use `@OnEvent('event.name')` for domain events.
- **Family membership check**: inline in services via `prisma.familyMember.findUnique({ where: { familyId_userId: { familyId, userId } } })`. There is no `FamilyMemberGuard`.
- **CurrentUser decorator**: `@CurrentUser('id')` extracts the userId from the JWT payload.

### 5.3 Prisma + Supabase pooler
- The live DB uses Supabase's pooler (port 6543) via `DATABASE_URL`.
- PgBouncer in transaction mode doesn't support Prisma's prepared statements.
- **For standalone scripts** (test scripts run with `bun`), pass `DATABASE_URL` with `?pgbouncer=true&prepare=false` appended.
- **The NestJS app** handles this in production (the pooler supports prepared statements when configured correctly, or the app uses the directUrl fallback for migrations).
- **Direct URL (port 5432)** may be IPv6-only from outside Supabase's network — prefer the pooler for scripts.

### 5.4 Validation pattern (MANDATORY for every phase)
Before marking any phase complete:
1. **State predictions BEFORE writing code** — for each test case, hand-compute the expected output.
2. **Write a test script** that runs the code and compares predicted vs actual.
3. **Run on the live DB** (not just locally) — use the credentials above.
4. **Show the comparison** — every metric, every value, pass/fail per item.
5. **If any mismatch**: debug and explain before proceeding. Don't skip to the next phase.
6. **Clean up test rows** from the live DB after validation.

### 5.5 Commit + deploy
- After each phase validates, commit with a detailed message and push to `origin/main`.
- Vercel (Flutter web) auto-deploys from the push.
- Render (NestJS) auto-deploys from the push.
- Supabase migrations are applied via `supabase db query --linked -f <file>` using the access token.

---

## 6. The Pitch (the "why")

> *Daxelo Kinrel is the only app that knows your family well enough to tell you, every morning, who needs you today — and keeps your grandmother's voice alive forever.*

- **Kinrel** = brand identity (the crest on the door). Festival-level engagement. Already built.
- **Pulse** = daily driver (the reason people walk in every day). The "WhatsApp chat" moment.
- **Pitru** = lock-in (the reason they never leave). Ancestral voice memory + AI persona.

No competitor can copy this without the relationship graph. WhatsApp has contacts but not relationship types. Instagram has content but not family structure. Vamshavriksha has the tree but not daily engagement. Google Photos has photos but not the family web.

---

## 7. The 6-Item Brief (the UX target)

```
🌅 Good morning, Manish. Here's your family today.

💜 Needs you today
   Dadi hasn't been active in 4 days. Last seen: Sunday.
   She mentioned knee pain in her last voice note.
   → Call her? [Tap to call]

🎂 This week
   Priya's birthday — Thursday (3 days)
   She's turning 25. Nani is already planning.
   → Contribute to family gift pool? [₹200 suggested]

📸 Just happened
   Rajesh bhaiya (Bangalore) added 6 photos of Anaya's
   first steps. Your mom already reacted ❤️
   → See photos

🌧️ Relationship weather
   Anil bhai — cloudy. You haven't spoken in 23 days.
   Last conversation: brief, about money.
   → Send a message?

👵 New from the elders
   Dadi shared a 2-min voice memory about her
   wedding day — the bullock cart, the monsoon rain.
   → Listen before it scrolls away

🔮 On this day, 1987
   Your grandfather started his first job at the bank.
   He mentioned this in a story 3 years ago.
   → Hear him tell it
```

Each section maps to a `BriefItemType`:
- `need_you` (priority 95, actionType `call`)
- `birthday` (priority 90, actionType `contribute`)
- `feed_highlight` (priority 60, actionType `view_post`)
- `weather` (priority 65, actionType `message`)
- `memory_orbit` (priority 70, actionType `listen_memory`) — stub until Pitru
- `on_this_day` (priority 70, actionType `view_sparq`)

---

## 8. Instructions For The New Chat

**You are continuing the Kinrel Pulse build.** The previous chat got interrupted mid-Phase-1. Here's what to do:

1. **First, clone the repo and verify the current state:**
   ```bash
   git clone https://github.com/buildwith-manish/Daxelo-Kinrel
   cd Daxelo-Kinrel
   # Verify Pulse migration is applied
   export SUPABASE_ACCESS_TOKEN="[REDACTED:supabase_pat]"  # fill in the actual token
   npx supabase db query --linked "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename IN ('DailyBrief','BriefItem','BriefInteraction','RelationshipWeather','ConnectionStreak','FamilyKarma');"
   ```

2. **Verify the Pulse files already exist:**
   - `server/src/pulse/brief-types.ts` ✅
   - `server/src/pulse/brief-generator.service.ts` ✅
   - `server/prisma/schema.prisma` should have the Pulse models at the end ✅
   - Run `cd server && npx prisma generate` to confirm the schema compiles

3. **Continue Pulse Phase 1:**
   - Write the 6 collectors in `server/src/pulse/collectors/`
   - Write `pulse.controller.ts`, `pulse.module.ts`
   - Register `PulseModule` in `app.module.ts`
   - Write the 7am cron job
   - Write the validation script
   - Run validation on the live DB
   - Commit + push

4. **Follow the validation pattern strictly**: state predictions before code, write test scripts, run on live DB, show comparison, clean up test rows.

5. **After Pulse Phase 1 validates**, proceed to Phase 2 (graph-aware personalization), then Phase 3 (push delivery), etc. Then Pitru. Then the addictiveness features.

6. **Commit after every phase** with a detailed message. Push to `origin/main`. Vercel + Render auto-deploy.

7. **Don't skip validation.** Graph algorithms and personalization logic can run cleanly and still be silently wrong. Every phase must be validated against hand-computed predictions on a real family from the live DB.

8. **The test family** on the live DB is `cmr1xhyo7bivcw8rzx0hlguyi` ("Yakshitha Poojary", 5 members, 3 relationships, primaryLanguage=en, archetype=confluence). Use this family for all live validation.

9. **The live user** for brief generation tests: find one via `SELECT u.id, u.name, u."preferredLanguage" FROM "User" u JOIN "FamilyMember" fm ON fm."userId" = u.id WHERE fm."familyId" = 'cmr1xhyo7bivcw8rzx0hlguyi' LIMIT 1;`

10. **Be ambitious.** The user wants this app to be "the bestest" — attractive, addictable, everything. Add your own ideas. Don't miss anything. The goal is a daily-habit family OS that no competitor can replicate.

---

**Now begin. Clone the repo, verify the state, and continue Pulse Phase 1.**
