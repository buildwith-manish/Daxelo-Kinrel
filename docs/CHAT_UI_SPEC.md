# Chat UI Reference — Unified Chat UI Spec (Kin Thread)

This document is the source of truth for the unified chat UI. All
visual components live in `lib/features/chat/presentation/` and read
their colors, sizes and typography from
`chat_ui_tokens.dart` (`ChatUi`) — no chat widget hard-codes a color
or a dimension.

Both chat types (group + 1:1 direct) share the SAME components and
logic; the direct variants only suppress group-only affordances
(kinship band, sender row, member counts).

---

## A. Color tokens (`ChatUi`)

| Token | Value | Used by |
|---|---|---|
| chatBackground | `#131416` | D2 chat screen background |
| chatBar | `#13141E` | D1 header, D12 composer, D14 selection bar |
| chatCard | `#191B2C` | D8 date chips, D11 card, D18 invite cards |
| chatCardBorder | white @ 8% | hairline on cards |
| chatReceived | `#2A2D48` | D3/D4 received bubbles, D8 floating chip, D10 pill |
| chatSent | `#34201A` | D5 sent bubble |
| chatSentBorder | ember `#C44A18` @ 28% | D5 sent border (0.75 dp) |
| chatMenu | `#1F2236` | D17 overflow/context menu card, D15 pill |
| chatSelectedRow | orange `#E8612A` @ 18% | D16 selected row tint |
| textPrimary | `#ECEAF2` | message text, names |
| textSecondary | `#B9BDD0` | subtitles, pill labels |
| textMeta | `#8E92A8` | D7 timestamps, quiet rows |
| accent | `#E8612A` (KinrelColors.orange) | send circle, hearts, links |
| wallDot | `#1F2230` | D13 wallpaper dots |
| wallLine | `#1A1C27` | D13 wallpaper lines |

Kinship band colors are `KinrelColors.node*`:

| Relation | Color |
|---|---|
| parent | `#3B82F6` |
| sibling | `#8B5CF6` |
| child | `#EC4899` |
| grandparent | `#6366F1` |
| aunt/uncle | `#06B6D4` |
| cousin | `#10B981` |
| in-law | `#F59E0B` |
| spouse | `#F97316` |
| self | `#FFC94A` |
| extended (and unresolved fallback) | `#64748B` |

## B. Typography rules

- Message text: body font (DMSans), 14 / w400 / 1.4 line height,
  textPrimary.
- Titles (header, cards): display font (Outfit) 16 / w500.
- Timestamps: body 11 / w400 / textMeta.
- Pills: body 12 / w400 (textSecondary or textPrimary).
- **Forbidden:** weights >= 600 anywhere in the chat UI; the mono
  font in pills/timestamps.

## C. Icon sizes

- Header icons (phone, more_vert): 22 dp
- Composer icons (emoji, attach, heart, mic/send): 20 dp
- Menu icons (D17 rows): 20 dp
- Read-receipt ticks: 13 dp (`Icons.done` / `Icons.done_all`)
- Sparkle (D9): 14 dp; heart (D11): 18 dp
- All tap targets >= 48 dp, all icon buttons carry Semantics labels

## D. Components (D1–D18)

| # | Component | File | Notes |
|---|---|---|---|
| D1 | Header bar (56 dp) | `widgets/chat_header_bar.dart` | chatBar bg, 34 dp avatar, title + "N members · N online", phone + more_vert 22 dp. Direct variant: "Father · online", chatReceived avatar w/ relationship-color initial |
| D2 | Message list metrics | `widgets/chat_message_list.dart` | h12 per-row padding, 8 between senders, 2 within a 2-minute cluster, top 10 |
| D3 | Group received bubble | `widgets/message_bubble.dart` | chatReceived, radius 14 (all corners), 3 dp kinship band (Stack-positioned, left edge), 80% max width |
| D4 | Direct received bubble | same | no band, no sender row, no avatar |
| D5 | Sent bubble | same | chatSent, ember border 0.75 dp @ 28%, right aligned |
| D6 | Sender row | same | relationship pill (radius full, 12%/30% kinship tint, 11/w500) + name 12/w400; unresolved -> orange name, no pill |
| D7 | Time row | same | right aligned, 11 textMeta, + 13 dp ticks for sent |
| D8 | Date chips | `chat_message_list.dart` (static) + `floating_date_indicator.dart` (floating) | static: chatCard pill; floating: chatReceived pill pinned 8 dp below header |
| D9 | System notice | `widgets/chat_system_notice.dart` | centered pill, sparkle 14 in accent, optional "View in tree" in accent |
| D10 | Unread divider | `chat_message_list.dart` | chatReceived pill, "N unread messages" 12 textPrimary, no icon |
| D11 | Thinking of you | `widgets/message_bubble.dart` | centered chatCard card, radius 12, heart 18 accent, 13 textPrimary |
| D12 | Composer | `widgets/chat_input_bar.dart` | chatBar surface; capsule chatCard radius 20 with emoji INSIDE left + attach/heart INSIDE right; 40 dp accent circle (mic->send) OUTSIDE right |
| D13 | Constellation wallpaper | `widgets/constellation_pattern.dart` | 320x480 tile, 14 dots #1F2230, 9 lines #1A1C27 1 dp, cached ui.Image + ImageShader |
| D14 | Selection toolbar | `widgets/selection_mode_toolbar.dart` | replaces header, 56 dp, chatBar, close + "N selected" + Reply/Forward/Star/Delete/More |
| D15 | Reaction bar | `widgets/chat_meta.dart` (ReactionOverlay) | pill, chatMenu bg, 6 glyphs (heart/lol/thumbs/wow/sad/pray) 22 dp + plus |
| D16 | Selected row | `chat_message_list.dart` | full-bleed chatSelectedRow tint, no border, no check icon — tap row toggles |
| D17 | Overflow menu | `widgets/chat_header_bar.dart` | 210 dp wide card, radius 12, chatMenu, 20 dp icons; used by header more_vert AND selection more |
| D18 | Game invite card | `widgets/game_invite_card.dart` | 4 states: active slim card (outlined Join), result card (gold trophy + Rematch), expired one-liner (no bubble), collapsed run (chatCard row); result cards never collapse |

## E. UI Gallery (debug)

`chat_ui_gallery.dart` renders the real widgets with sample data —
boot gate in `main.dart`:

```
flutter run --dart-define=UI_GALLERY=true
```

Four pages: group chat sample, invite states, selection mode, direct
chat sample. The `perf-profile-apk.yml` workflow has a `ui_gallery`
input that produces a `kinrel-profile-apk-gallery` artifact.

## Flat style rules

- No shadows, no gradients, no blur, no `Opacity`/`ColorFiltered`
  layers anywhere in the chat UI.
- All colors via `ChatUi` / `KinrelColors`; sizes via `ChatUi` /
  `KinrelSpacing` / `KinrelRadius`.
- Never modify logic/data/SQL/navigation to change a visual.
