// lib/features/sparq_tray/sparq_tray_strings.dart
//
// DAXELO KINREL — Family Sparq Tray user-facing strings (single source).
//
// Naming rule (spec section 0): the word "story" does not appear in
// any user-visible string in this feature. The feature is called Sparq.
//
// All user-facing copy for the tray, the run screen overlay, the
// Moment Sparq card, and the semantics labels lives here so a single
// grep can audit every label.

/// All user-facing strings for the Family Sparq tray feature.
///
/// These are `const String`s so the analyzer can tree-shake them and
/// the linter can flag any hardcoded "Sparq" string outside this file.
class SparqTrayStrings {
  SparqTrayStrings._();

  // ── Tray labels ─────────────────────────────────────────────────────

  /// The "Your Sparq" entry label, shown under the medallion when the
  /// viewer is the tray's first item.
  static const String yourSparq = 'Your Sparq';

  /// Small "+" badge tooltip — tapping opens `/sparq/create`.
  static const String addASparq = 'Add a Sparq';

  /// Last entry in the tray — dashed circle + plus icon →
  /// `context.push('/families/create')`.
  static const String newFamily = 'New family';

  /// Second line under the medallion: "{n} new" (amber) when n > 0.
  /// Caller substitutes `{n}` with the actual unseen count.
  static const String nNew = '{n} new';

  /// Second line when only a Moment Sparq is live for the family (no
  /// member Sparqs, but the birthday/anniversary/festival card is
  /// available to play).
  static const String moment = 'Moment';

  // ── Run screen overlay ──────────────────────────────────────────────

  /// Bottom row label on the run screen: avatars of the other members
  /// in the family that will play after the current one finishes.
  static const String alsoFromThisFamily = 'Also from this family';

  /// Right-aligned hint on the run screen when there's another family
  /// with unseen Sparqs queued up after this one.
  /// Caller substitutes `{family}` with the next family's name.
  static const String nextFamily = 'Next: {family}';

  /// Pill at the top of the run screen, showing progress through the
  /// family's member queue. Caller substitutes `{family}` with the
  /// family name, `{k}` with the current member index (1-based), and
  /// `{n}` with the total member count.
  static const String familyProgress = '{family} · {k} of {n} members';

  /// Kinship label pill — never falls back to a wrong term. Caller
  /// format: "{kinshipLabel} · {relationLine}". If no kinship could be
  /// resolved, the pill is omitted entirely (no fallback string here).
  static const String kinshipPill = '{kinship} · {relation}';

  // ── Moment Sparq card ──────────────────────────────────────────────

  /// Header label on the Moment Sparq card.
  static const String kinrelMomentToday = 'Kinrel moment · Today';

  /// Primary CTA on the Moment Sparq card.
  static const String sendAWish = 'Send a wish';

  /// Quick reply 1 — respectful greeting for elders.
  static const String pranam = 'Pranam';

  /// Quick reply 2 — used for birthdays and anniversaries.
  static const String happyBirthday = 'Happy birthday';

  /// Quick reply 3 — opens the existing blessing record sheet.
  static const String voiceBlessing = 'Voice blessing';

  // ── Semantics labels (TalkBack / VoiceOver) ───────────────────────

  /// A11y label for a family tray entry that has unseen Sparqs from
  /// specific members. Caller substitutes `{family}` with the family
  /// name, `{count}` with the unseen count, and `{names}` with a
  /// comma-separated list of member display names.
  static const String semanticsFamilyWithNew =
      '{family}, {count} new Sparqs from {names}';

  /// A11y label for a family tray entry whose Sparqs are all seen.
  /// Caller substitutes `{family}` with the family name.
  static const String semanticsFamilyAllSeen =
      '{family}, all Sparqs seen';

  /// A11y label for a family tray entry with no live Sparqs at all —
  /// tapping opens the family page (not the Sparq run).
  static const String semanticsFamilyEmpty =
      '{family}, no Sparqs. Opens family page';

  /// A11y label for the "Your Sparq" entry when the viewer has a live
  /// Sparq. Tap plays their own Sparq.
  static const String semanticsYourSparqLive =
      'Your Sparq, you have a live Sparq. Tap to view.';

  /// A11y label for the "Your Sparq" entry when the viewer has no live
  /// Sparq. Tap opens the Sparq create screen.
  static const String semanticsYourSparqEmpty =
      'Your Sparq, no live Sparq. Tap to add a Sparq.';

  /// A11y label for the "New family" dashed circle.
  static const String semanticsNewFamily =
      'New family. Double tap to create a new family.';

  /// A11y hint for the small "+" badge on the Your Sparq entry.
  static const String semanticsAddBadge =
      'Add a Sparq. Double tap to open the Sparq create screen.';
}
