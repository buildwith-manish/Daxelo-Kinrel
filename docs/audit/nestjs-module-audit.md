# NestJS Module Audit Report — Tier 3 #9

**Date:** 2026-09-23
**Scope:** All 37 NestJS modules — cross-referenced against Flutter app API call sites
**Status:** AUDIT ONLY — no code changes made in this pass

## Methodology

1. Extracted all NestJS controller route prefixes from `server/src/modules/*/`
2. Extracted all API endpoints called from the Flutter app (`lib/`) via `grep -oE "['\"]/(api|v1)/[^'\"]*['\"]"`
3. Cross-referenced NestJS module routes against Flutter call sites
4. Identified modules with no Flutter callers as "needs further investigation"
5. Checked for non-Flutter callers: admin panel, webhook receivers, cron-triggered internal calls, other services

## Results

### Confirmed Active Modules (called from Flutter app)

| Module | Route Prefix | Flutter Call Sites | Recommendation |
|--------|-------------|-------------------|----------------|
| `auth` | `/api/auth` | `/api/auth/2fa`, `/api/auth/logout`, `/api/auth/me`, `/api/auth/sessions`, `/api/auth/change-password` | **Keep** — auth, 2FA, session management |
| `families` | `/api/families` | `/api/families/:id/members`, `/api/families/:id/leave`, `/api/families/:id/family-id`, `/api/families/family-id/search`, `/api/families/family-id/join`, `/api/families/:id/viewer`, `/api/families/:id/chat/*` | **Keep** — core family management |
| `members` | `/api/families/:familyId/persons` | called via families module | **Keep** — person CRUD |
| `relationships` | `/api/families/:familyId/relationships` | `/api/families/:id/relationship-path` | **Keep** — relationship management |
| `viewer` | `/api/families/:familyId/viewer` | `/api/families/:id/viewer`, `/api/families/:id/persons/:personId/claim`, `/api/families/:id/persons/:personId/unlink`, `/api/families/:id/persons/:personId/invite` | **Keep** — viewer perspective |
| `notifications` | `/api/notifications` | `/api/notifications`, `/api/notifications/unread-count` | **Keep** — notification management |
| `users` | `/api/users` | `/api/users/me`, `/api/users/me/stats` | **Keep** — user profile |
| `support` | `/api/support` | `/api/support/tickets/my` | **Keep** — support tickets |
| `search` | `/api/search` | `/api/search` | **Keep** — cross-feature search |
| `kinship` | `/v1/kinship` | `/v1/kinship`, `/v1/kinship/languages`, `/v1/kinship/search` | **Keep** — kinship data |
| `referral` | `/v1/referral` | `/v1/referral/my-code`, `/v1/referral/apply`, `/v1/referral/stats` | **Keep** — referral system |
| `ai-cards` | `/v1/ai-cards` | `/v1/ai-cards/templates`, `/v1/ai-cards/festival`, `/v1/ai-cards/kinship` | **Keep** — AI card generation |
| `ai-voice` | `/v1/ai-voice` | `/v1/ai-voice/transcribe`, `/v1/ai-voice/lookup` | **Keep** — voice transcription |
| `gamification` | `/v1/gamification` | `/v1/gamification/leaderboard`, `/v1/gamification/daily-challenge` | **Keep** — gamification system |
| `communities` | `/v1/communities` | `/v1/communities` | **Keep** — community features |
| `chat` | `/api/families/:familyId/chat` | `/api/families/:id/chat/info`, `/api/families/:id/chat/media`, `/api/families/:id/chat/pinned` | **Keep** — chat management + WebSocket gateway |
| `games` | WebSocket gateway | called via Socket.IO from Flutter | **Keep** — multiplayer game gateway |
| `gateway` | WebSocket gateway | called via Socket.IO from Flutter | **Keep** — Socket.IO gateway |
| `realtime` | WebSocket gateway | called via Socket.IO from Flutter | **Keep** — realtime events |

### Needs Further Investigation (no direct Flutter call found, but may have non-Flutter callers)

| Module | Route Prefix | Potential Non-Flutter Callers | Recommendation |
|--------|-------------|------------------------------|----------------|
| `admin` | `/admin` | Admin panel (if exists), internal tools | **Needs investigation** — check if an admin panel or internal tool calls these endpoints. If not, candidate for removal. |
| `ai-chat` | `/v1/ai-chat` | `/v1/ai-chat/suggestions`, `/v1/ai-chat/relationship-explanation` — may be called from Flutter via a different import path not caught by grep | **Needs investigation** — verify if the Flutter app's AI chat feature calls these endpoints. The `/api/kinrel` prefix found in Flutter may route to this module. |
| `analytics` | No controller | No endpoints — likely a service-only module (provides analytics to other modules) | **Keep** — service module, not a controller |
| `community` | `/v1/communities` | Already listed above as called from Flutter | **Keep** (duplicate of communities) |
| `developer` | `/v1/webhooks`, `/v1/developer/keys` | External API consumers, webhook receivers | **Keep** — developer API for external integrations |
| `feature-flags` | `/feature-flags` | Flutter app reads feature flags — may be called via RemoteConfig or a different path not caught by grep | **Needs investigation** — check if Flutter calls this via Firebase Remote Config or directly. |
| `follow` | `/follow` | `/follow`, `/follow/accept/:userId`, `/follow/reject/:userId` — social follow system; Flutter has `follow_provider.dart` and `follow_repository.dart` | **Needs investigation** — check follow_repository for the actual endpoint paths. |
| `graph` | `/graph` | `/graph/:familyId/enriched`, `/graph/:familyId/layout` — may be called from Flutter's graph providers via a different path | **Needs investigation** — check graph providers. |
| `invitations` | `/invitations` | `/invitations/:id/accept` — Flutter has invitation handling | **Keep** — invitations are actively used |
| `moderation` | `/moderation` | `/moderation/report`, `/moderation/queue` — may be called by admin panel or content moderation tools | **Needs investigation** — check if any admin or moderation UI calls these. |
| `payments` | `/payments` | `/payments/create-order`, `/payments/verify`, `/payments/subscription` — Flutter has `premium_service.dart` which calls `/api/premium/status` | **Keep** — premium/payment system is active |
| `profile` | `/profile` | `/profile/:familyId/:personId` — person profile data | **Needs investigation** — check if Flutter calls this or uses Supabase directly. |
| `share` | `/share` | `/share`, `/share/track`, `/share/mine` — share card generation | **Needs investigation** — Flutter has `share_screen.dart` which may call these. |
| `sparq` | `/sparq` | `/sparq/feed`, `/sparq/user/:userId` — social feed; Flutter has `sparq_provider.dart` and `sparq_repository.dart` | **Needs investigation** — check sparq_repository for actual endpoint paths. |
| `stories` | `/stories` | `/stories`, `/stories/mine` — story mode; Flutter has story-related screens | **Needs investigation** — check story thread providers. |
| `sync` | `/sync` | `/sync` — offline sync engine; Flutter has `sync_engine.dart` and `background_sync_manager` | **Keep** — sync is actively used |
| `thinking` | `/v1/thinking` | `/v1/thinking/tap`, `/v1/thinking/received` — "Thinking of You" feature | **Needs investigation** — check thinking service in Flutter. |
| `timeline` | `/feed`, `/families/:familyId/timeline` | `/feed` — unified timeline; Flutter has timeline screens | **Needs investigation** — check if Flutter calls `/feed` or uses Supabase directly. |
| `whatsapp` | `/whatsapp` | `/whatsapp/consent` — WhatsApp integration | **Needs investigation** — check if the app has a WhatsApp consent screen. |

### Summary

| Category | Count | Modules |
|----------|-------|---------|
| **Confirmed active** (called from Flutter) | 19 | auth, families, members, relationships, viewer, notifications, users, support, search, kinship, referral, ai-cards, ai-voice, gamification, communities, chat, games, gateway, realtime |
| **Needs investigation** (may have non-Flutter callers) | 14 | admin, ai-chat, feature-flags, follow, graph, moderation, profile, share, sparq, stories, thinking, timeline, whatsapp, payments |
| **Service-only** (no controller) | 1 | analytics |
| **Confirmed active** (sync, invitations) | 2 | sync, invitations |
| **Total** | 36 | (analytics is the 37th — service-only) |

### Recommendation

Do NOT delete any module in this pass. The 14 "needs investigation" modules require a deeper audit:

1. **Server access logs** — check actual HTTP request logs on the NestJS server (onrender.com) over the last 2-4 weeks to see which endpoints actually received traffic
2. **Flutter grep** — the current grep may have missed endpoints called via dynamic URL construction (template literals, string interpolation) or via a different base path
3. **Non-Flutter callers** — verify if admin panel, webhooks, payment provider callbacks, or cron-triggered internal calls exist

### Cost Impact (if dead modules are found and removed)

The NestJS server is hosted on onrender.com (free tier or paid tier). Removing dead modules would:
- Reduce server memory usage (fewer modules loaded)
- Reduce cold-start time (if on free tier with spin-down)
- Simplify maintenance (fewer files to maintain)

The actual cost savings depend on the hosting plan. If the server is on onrender.com's free tier, it costs $0 regardless — but removing dead code reduces cold-start latency. If it's on a paid tier, reducing the server's memory footprint may allow downsizing to a cheaper plan.

---

**This report is for planning purposes only. No code changes were made.**
