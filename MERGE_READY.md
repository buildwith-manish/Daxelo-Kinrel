# Merge Ready — Chat Parity Branch

**Branch:** `tier-1-chat-features`
**Base:** `main` (commit `8ddcc74`)
**Latest commit:** (see `git log` — Tier 6 + follow-up)

## PR Summary

This branch implements **all 6 tiers** of the chat-parity plan (WhatsApp/Telegram-level features). 36 idempotent SQL migrations applied live to your Supabase project; 18 NestJS controllers + 18 services added; 278 jest tests pass with zero regressions.

## What's included (by tier)

### Tier 1 — Foundation (4 features end-to-end + 5 schema-only)
- Saved Messages, Message Scheduling, Send Without Sound, Caption on Media
- Schema for: Auto-saved Drafts, View-Once Media, HD Photo, Documents, Multi-forward

### Tier 2 — Group & DM power (7 end-to-end + 5 schema-only + 1 calls-schema-only)
- Slow Mode, Anonymous Admin, Audit Log, Invite Links, Join Requests, Group Description, Custom Reactions
- Schema for: Forum Topics, Channels, Communities (renamed FamilyCommunity), Broadcast Lists, Calls

### Tier 3 — Inbox, organization, search (9 end-to-end)
- Chat Folders, Pin Chats, Mark as Unread, Mute with Duration, Privacy Toggles (last-seen + read-receipts reciprocity), Block + Report, Message Deep-link, Search Filters, Calendar Jump scaffolding

### Tier 4 — Rich text + stickers + media polish (4 end-to-end + 4 deferred Flutter UI)
- Edit Media + Edit History, Sticker Packs (with Animated Lottie), Custom Emoji Packs, Profile Video
- Deferred (pure Flutter): Markdown rendering, Edit History Sheet, Lottie rendering, Round Video

### Tier 5 — Calls, secret chats, cloud features (5 end-to-end)
- Secret Chats (E2E ciphertext-only), Public Username Discovery, People Nearby (Haversine), Chat Export Jobs, Cloud Backup Records

### Tier 6 — Polish + ecosystem (4 end-to-end + 3 deferred Flutter UI)
- Message Effects (iOS-style), Translations (provider-agnostic), Bots + Inline bots, Mini-apps (signed HMAC tokens)
- Deferred (pure Flutter): Tablet two-pane, Wear OS, Home screen widgets

### Follow-up commit (this one)
- **ChatExportRunnerService** — the actual file-builder that processes pending ChatExportJob rows via `@Cron(EVERY_MINUTE)`. Builds plain-text transcripts for scope='text' (and 'full' falls back to text with a TODO note for adm-zip). Marks jobs running → completed/failed with resultUrl + sizeBytes + messageCount + 7-day expiry.
- **Read-receipts privacy suppression** — wired `PrivacyService.hasReadReceiptsEnabled` into `ChatService.markAsRead`. When the reader OR any sender has `readReceiptsEnabled=false`, the readBy writes are suppressed both ways (matches WhatsApp — both directions are gated). The field existed since Tier 3 but the wiring was a TODO; this closes that gap.
- Updated `chat-throttler.service.spec.ts` to mock PrismaService (added in Tier 2 for slow-mode) + added 5 new slow-mode tests.
- Added 7 new tests for ChatExportRunnerService.
- Full chat test suite: **278/278 pass** with zero regressions.

## Combined totals
- **36 migrations applied to live Supabase**
- **43 RPCs created**
- **18 NestJS controllers** + **18 NestJS services**
- **278 jest tests pass** with zero regressions
- **37 new Prisma models** + **26 new columns** on existing models

## Deployment checklist (env vars to add to your NestJS server)

| Var | Required? | Purpose |
|-----|-----------|---------|
| `TRANSLATION_PROVIDER` | Optional | `deepl` \| `google` \| `libretranslate`. Absent = translations return `no_provider`. |
| `TRANSLATION_API_KEY` | When `TRANSLATION_PROVIDER` is set (except libretranslate self-hosted) | The provider API key. |
| `TRANSLATION_BASE_URL` | Optional | For self-hosted LibreTranslate. Defaults to https://libretranslate.com. |
| `BOT_MINIAPP_SECRET` | Required for mini-apps | Any random 32+ char string for HMAC-SHA256 signing. |

## Follow-up TODOs (server-side, you should know about)

1. **Replace translation provider stubs** in `translations.service.ts` (`callDeepL`, `callGoogle`, `callLibreTranslate`) with real `fetch()` calls when you have API keys. The cache infrastructure works end-to-end; only the actual provider call is a stub.

2. **Replace the ChatExportRunner's data-URL placeholder** in `chat-export-runner.service.ts` (`toDataUrl` method) with a real Supabase Storage upload when you've configured a `chat-exports` bucket + service role key on the NestJS server. Currently the runner produces a `data:text/plain;base64,...` URL — fine for small exports (under ~2MB), but for larger ones you'll want a real signed storage URL.

3. **Install `adm-zip`** in the server's package.json if you want full ZIP-with-media exports (Tier 5 Feature 5.4 scope='full'). Currently the runner falls back to text-with-a-TODO-note for 'full' scope.

## Flutter TODOs (I couldn't test these — no Android/iOS emulator here)

Across all 6 tiers, here's the Flutter-side work that's outstanding. Run `cd Daxelo-Kinrel-App && flutter analyze && flutter test` before merging.

| Tier | Feature | Flutter work |
|------|---------|--------------|
| 1 | 1.1 Saved Messages | Inbox row wired (DONE); DM screen "Saved Messages" header label TODO |
| 1 | 1.2 Message Scheduling | `ScheduleMessageSheet` widget DONE; scheduled tray UI TODO |
| 1 | 1.3 Auto-saved Drafts | `drafts_provider.dart` DONE; `chat_screen` debounce-write wiring TODO |
| 1 | 1.4 Send Without Sound | `SendSilentlySheet` DONE; long-press send button wiring TODO |
| 1 | 1.5 View-Once Media | Bubble rendering + tap-to-reveal TODO |
| 1 | 1.6 HD Photo Quality | Photo picker "Send as Standard/HD" toggle TODO |
| 1 | 7–13 | Voice waveform, transcription, in-app camera, video trim, contact share, live location — all TODO |
| 2 | Forum Topics | `TopicsGridScreen` TODO |
| 2 | Channels | `ChannelScreen` TODO |
| 2 | Communities | `CommunityScreen` TODO |
| 2 | Broadcast Lists | `BroadcastListScreen` TODO |
| 2 | Voice/Video Calls | Needs LiveKit/mediasoup signaling server (~$30-80/mo hosting) |
| 3 | Chat Folders | Folder bar widget TODO |
| 3 | Calendar Jump | `CalendarJumpSheet` widget TODO |
| 3 | Message Deep-link | `go_router` route for `/c/:familyId?m=:msgId` TODO |
| 4 | Markdown | `flutter_markdown` in `message_bubble.dart` + Spoiler widget TODO |
| 4 | Edit History Sheet | `EditHistorySheet` reading `editHistory` jsonb TODO |
| 4 | Sticker Picker | "Make sticker" flow (background-removal) TODO |
| 4 | Lottie rendering | `lottie` package in sticker bubble TODO |
| 4 | Profile Video | `video_player` in avatar slot TODO |
| 4 | Round Video | `circular_clip` painter TODO |
| 5 | Secret Chat Crypto | `cryptography` package: X25519 + AES-GCM, `SecretChatScreen` TODO |
| 5 | Nearby Screen | Map + list using `flutter_map` TODO |
| 5 | Export Sheet | Settings sheet with format options TODO |
| 5 | Cloud Backup OAuth | `googleapis` + `sign_in_with_google` for Drive; native plugin for iCloud TODO |
| 6 | Tablet Layout | `ChatTwoPaneLayout` widget (detect width > 900) TODO |
| 6 | Wear OS / Apple Watch | Native watch apps (separate codebases) TODO |
| 6 | Home Screen Widgets | `home_widget` package TODO |

## Verification commands

```bash
# Backend tests (must all pass)
cd server && npx jest src/modules/chat --silent

# Type-check (must be clean)
cd server && npx tsc --noEmit -p tsconfig.json

# Prisma generate (must succeed)
cd server && npx prisma generate

# Flutter tests (RUN THESE LOCALLY before merging)
cd Daxelo-Kinrel-App && flutter analyze && flutter test
```

## Security reminder

You shared 4 credentials with me during this work. **Rotate ALL of them immediately**:
- GitHub PAT (`ghp_…`)
- Vercel token (`vcp_…`) + team ID
- Supabase access token (`sbp_…`)
- App login password

Verified: `git log --all -p | grep -E "ghp_B1I|vcp_5Hs|sbp_8e7"` returns nothing — the PAT was only used via `git remote set-url` (transient config) and cleared after every push.

## How to merge

```bash
git checkout main
git pull origin main
git merge --no-ff tier-1-chat-features
git push origin main
```

Or open a PR on GitHub:
https://github.com/buildwith-manish/Daxelo-Kinrel/pull/new/tier-1-chat-features
