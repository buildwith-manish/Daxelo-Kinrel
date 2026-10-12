# Kinrel Chat Signature Spec

This document specifies the **Kinrel Signature** visual pass on the chat
UI — a set of distinctive, original Kinrel details so the chat does not
look copied from WhatsApp or Telegram. The signature pass is **visual
only** — it does not change logic, providers, data, SQL, or navigation.

## Scope rules

- **Flat style only** — solid colors, no shadows, no blur, no gradients,
  no `Opacity` or `ColorFiltered` widgets. A plain color with alpha
  (such as black at 22 percent) is fine. Chat is about 10 ms raster
  and must not get slower.
- Everything shared between group and direct chat is built once and
  wired into both.
- All colors, sizes, and durations come from
  `lib/features/chat/presentation/chat_ui_tokens.dart` (the `ChatUi`
  class, created on the `kin-chat` branch). New constants are added
  there. One helper `blendOver(background, color, amount)` mixes a
  color over the chat background at the given amount and returns an
  opaque color; use it instead of `Color.withValues(alpha:)` wherever
  a faded color is needed.
- **Accessibility**: Semantics labels on every new mark, decorative
  painters excluded from semantics, text scale up to 1.3 without
  overflow, tap targets at least 48 dp, never rely on color alone
  (every state differs by shape), respect reduce motion.
- New user-visible strings go into the template ARB (`app_en.arb`) and
  every existing locale ARB with the English text if a translation is
  missing; the l10n generation is run by `flutter build` automatically
  (the ARB has `@key` metadata blocks for the template).
- Do **not** touch the swipe-to-reply widget, the selection logic, the
  graph, or `AndroidManifest.xml`.

## A. Colors and sizes (added to `ChatUi`)

| Token | Value |
|-------|-------|
| `chatBackground` | `#131416` (KinrelColors.darkBackground) |
| `chatCard` | `#191B2C` |
| `chatReceived` | `#2A2D48` |
| `orange` | `#E8612A` |
| `ember` | `#C44A18` |
| `lineColor` | `#2E3150` (NEW) |
| `textPrimary` | `#ECEAF2` |
| `textSecondary` | `#B9BDD0` |
| `textSubtitle` | `#9AA0B8` (NEW) |
| `textMeta` | `#8E92A8` |
| `nodeDim1` | `#B9BDD0` (NEW) |
| `nodeDim2` | `#8E92A8` (NEW) |
| `nodeDim3` | `#5A5E78` (NEW) |
| `edgeDim` | `#6B6F86` (NEW) |

Kinship colors come from the existing `kinshipCategoryColor` helper:

| Category | Color |
|----------|-------|
| parent | `#3B82F6` |
| sibling | `#8B5CF6` |
| child | `#EC4899` |
| grandparent | `#6366F1` |
| aunt / uncle | `#06B6D4` |
| cousin | `#10B981` |
| in-law | `#F59E0B` |
| spouse | `#F97316` |
| self | `#FFC94A` |
| extended | `#64748B` |

Readable text variant of a kinship color for small labels: blend the
color 20 percent toward white via `ChatUi.readableKinshipLabel(c)`
(parent becomes about `#6FA3F8`).

Typography: body font. Time `11 / 400 / textMeta`. Label `13 / 400`.
Small label `11 / 500`. Marker text `12 / 400`. **Never italic, never
monospace in chat.**

`ChatUi.blendOver(background, color, amount)` — mixes `color` over
`background` at `amount` (0..1) and returns an OPAQUE color (alpha
forced to 1). Equivalent to:
`Color.lerp(background, color, amount).withValues(alpha: 1)`.

## B. Ghost bubble (`DeletedMessageGhost`)

Replaces the inline placeholder code in `message_bubble.dart` (the
"You deleted this message" block and any `Icons.block` or prohibited
sign icon) — the existing logic that decides who deleted it and when
to show it is kept; only the look and wording change.

- **Shape**: hugs its content, radius 14, border 1 dp **DASHED**
  (4 on, 3 off) drawn by one small `CustomPainter` with the dash path
  computed once per size and cached, **no fill**, padding 8 vertical
  and 10 horizontal, max width 80 percent of the row, aligned like a
  bubble (own right, others left), same spacing rules as messages.
- Own messages: no band. Received in group chat: a 3 dp wide band on
  the left (inside the rounded clip) in the sender's kinship color
  blended at 0.55 over `chatBackground`, left padding 14. Direct chat:
  no band, left padding 10. Unresolved relationship: extended color.
- Border and icon color: own = `blendOver(chatBackground, ember, 0.55)`
  which is `#743217`; received = `blendOver(chatBackground, kinship
  color, 0.55)` (parent gives `#295091`).
- **Icon `GhostNodeIcon`**, 22 × 16 dp, `CustomPainter`: two dots of
  radius 1.1 at (3, 8) and (7, 8), and a ring of radius 4.5 with stroke
  1.5 centered at (15.5, 8), all in the border color.
- **Text** `13 / 400 / textSubtitle`, one row with 8 dp gap after the
  icon; own: "You took this back"; others: "NAME took this back", where
  NAME is the relationship label when resolved (for example "Papa"),
  otherwise the sender name. Time `11 / textMeta` to the right after a
  6 dp gap, no ticks. Keep any existing different wording for admin
  removals but use the same look.
- **Collapse**: three or more consecutive ghost rows (adjacent in the
  list) become one row: radius 10, background `chatCard`, padding 8
  vertical and 10 horizontal, row with 8 gap: neutral ghost icon
  (color `nodeDim2`), text "N messages were taken back" (`13 /
  textSubtitle`), chevron down 16. Tapping it expands to show the
  individual ghosts (local widget state only). The collapsed row is not
  selectable.
- A reply quote that points to a deleted message shows the ghost icon
  (14 dp) and the text "Message taken back" in `12 / textMeta` instead
  of the old quoted text, if the deleted state is available to the
  quote; if not, report it.
- Long press and selection keep working with only the actions that
  exist today for such a message.
- **Motion**: if a message changes to deleted while the chat is open,
  cross-fade 150 ms with `DeletedMessageGhostTransition`; no animation
  when the list first builds.
- **Semantics label**: "NAME took this message back" (own: "You took
  this message back").

## C. Delivery marks (`DeliveryMark`)

Replaces the Material `done` and `done_all` ticks in `chat_meta.dart`
(`ReadReceipt`). Keep the existing status logic and the failed state
exactly as they are; change only the drawn mark.

One `CustomPainter DeliveryMark`, 18 dp wide and 10 dp tall, right of
the time with a 6 dp gap:

| Status | Geometry |
|--------|----------|
| sending | hollow ring, radius 3, stroke 1.4, centered at (5,5), `textMeta` |
| sent | filled dot, radius 3, at (5,5), `textMeta` |
| delivered | filled dot radius 2.6 at (4,5), a 1.2 stroke line from x 6.8 to 10.2 at y 5, hollow ring radius 2.6 stroke 1.4 at (12.4,5), all `textMeta` |
| read | same as delivered but both circles filled and the line, all in `orange` |

Semantics labels: "Sending", "Sent", "Delivered", "Read". Group chat
uses whatever read rule exists today.

> **Optional tip** (only if the app already has a first-run tip
> mechanism): one dismissible tip, "Two linked dots mean your message
> was read." The app currently has no first-run tip mechanism in the
> chat — **skipped and reported**.

## D. Thread date marker (`ThreadDateMarker`)

Replaces `_buildDateSeparator` in `chat_message_list.dart`.

Row, vertical padding 6, centered: a 1 dp line (`lineColor`) that
expands, 8 dp gap, a 6 × 6 circle (`nodeDim1`), 6 dp gap, the date
label `12 / textSecondary` (same text rules as today: Today, Yesterday,
weekday within 6 days, otherwise a short date), 8 dp gap, a 1 dp line
that expands. **No pill, no background.** The floating date chip shown
while scrolling stays a pill (`chatReceived` background, `textPrimary`),
unchanged.

## E. Unread marker (`UnreadMarker`)

Replaces the N unread messages pill in `chat_message_list.dart`.

Same layout as D with: lines color `blendOver(chatBackground, ember,
0.55)`, node 6 × 6 in `orange`, label `12 / orange` reading "N new
messages" (1 new message for one). Keep the existing logic that
decides where and when it appears.

## F. Passed along label (`_buildForwardedLabel` in `message_bubble.dart`)

For messages whose `forwardedFrom` (or the equivalent field) is set,
show above the content a row with 4 dp gap and 2 dp bottom margin: a
branch icon (Material `call_split_rounded`) 13 dp and the text "Passed
along", both `11 / 500 / textMeta`. Do not show the original author.
Works in group and direct chat.

> The `ChatMessage` model already has the `forwardedFrom` field — no
> new field was invented.

## G. Reply quote with relationship band (`_buildReplyPreview` in
`message_bubble.dart` + `reply_preview_bar.dart`)

Inside the bubble: container radius 8, background black at 22 percent
alpha (plain color via `blendOver(chatBackground, Colors.black, 0.22)`),
padding 4 top, 8 right, 4 bottom, 12 left, bottom margin 4, with a 3 dp
band on the left in the replied-to sender's kinship color (own messages:
orange; unresolved: extended). Title row `11 / 500` in the readable
text variant of that color, reading "RELATIONSHIP, NAME" (for example
"Papa, Father"), or "You" for your own message, or just the name in
orange when no relationship resolved. Quoted text `12 / textSecondary`,
max 2 lines with ellipsis. Tap behavior (jump to message) stays. The
reply bar above the composer uses the same band and the text "Replying
to NAME" with the same colors.

## H. Typing indicator (`TypingIndicator`)

Replace the bouncing dots. Show a small received-style bubble
(`chatReceived`, radius 14, padding 8 vertical, 14 left in group chat
and 12 in direct chat, 12 right) with, in group chat only, the 3 dp
band in the typist's kinship color blended at 0.55 over
`chatBackground`. Inside, a row with 10 dp gap: a painter 46 × 12 dp
with three nodes of radius 2.6 at x = 5, 23, and 41 (y = 6) and two
1 dp lines between them in `edgeDim`; static colors `nodeDim1`,
`nodeDim2`, `nodeDim3` from left to right; then the text
`12 / textSubtitle`: "NAME is typing" (relationship label or name),
"NAME and NAME are typing", "Several people are typing"; in direct chat
just "typing".

Animation: one `AnimationController`, 1.2 s loop, that rotates which
node is brightest (`nodeDim1` moves to the next node each third),
wrapped in a `RepaintBoundary` and listened to only by the small
painter; start it only while the indicator is visible and stop it
when hidden. When `DeviceTierCache.instance.lowRam` is true or reduce
motion is on, draw the static frame and never start the controller.

## I. Gallery (`ChatUiGallery`)

The kin-chat branch already has `ChatUiGallery` behind the
`UI_GALLERY` define. Add two pages with fixed sample data and the real
widgets:

### Page "Signature details"

- A date marker "Today".
- A received "Papa" (Father, parent color) bubble with the Passed
  along label and the text "Dinner at 8, everyone coming?" 7:42 PM.
- A sent bubble with a reply quote (Papa, Father, "Dinner at 8,
  everyone coming?"), the text "Yes, on my way.", 7:46 PM and the
  read mark.
- An unread marker "2 new messages".
- A received "Nani" (Grandmother, grandparent color) bubble "I will
  bring the sweets." 7:48 PM.
- The typing indicator for Nani.
- A legend row of the four delivery marks (Sending, Sent, Delivered,
  Read, labels `12 / textSecondary`).

### Page "Deleted messages"

- A normal Papa bubble and a normal sent bubble.
- The own ghost ("You took this back", 3:40 PM).
- The Papa ghost ("Papa took this back", 7:44 PM).
- The collapsed row ("3 messages were taken back").

## J. Delivery

- Write `docs/CHAT_SIGNATURE_SPEC.md` (this file).
- Re-read all edited code for syntax (matching commas and
  parentheses; a stray semicolon instead of a comma, and `const`
  constructors around `KinrelFx` calls, broke earlier builds).
- Search the repo for leftover uses of the old placeholder,
  `Icons.block`, `Icons.done`, `Icons.done_all`, the old unread pill,
  and the old bouncing dots. All removed.
- Dispatch `ci.yml` and report ONLY new analyzer warnings compared to
  main.
- Dispatch `perf-profile-apk.yml` twice on the branch: normal
  (`rich_fx: false`) and with `ui_gallery: true`. If a build fails,
  read the log, make the smallest fix and re-run (maximum 3 attempts).
- Open a pull request `feat/kin-signature` into `main` with the
  migration warning from Step 0c at the top of the description:

  > ⚠️ BEFORE merging to main, apply the SQL migration
  > `supabase/migrations/20261012120000_message_deletion_undo.sql`
  > (from the merged `feat/message-deletion-undo` branch) to the
  > production Supabase project. Merging to main auto-deploys the web
  > app, and the new `fn_undelete_message_for_me` /
  > `fn_bulk_delete_for_me` / `fn_bulk_undelete_for_me` RPCs must
  > exist when the new client starts calling them.

## DO NOT DO

- Change logic or data.
- Run SQL.
- Add dependencies.
- Touch the graph, the swipe-to-reply widget, selection logic, or
  `AndroidManifest.xml`.
- Merge any PR.
- Force push, rebase, or delete branches.
