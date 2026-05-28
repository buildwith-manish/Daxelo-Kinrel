// lib/core/utils/invite_message_builder.dart
//
// DAXELO KINREL — Invite Message Builder (P5)
//
// Generates localized invite messages for family invitations.
// Supports Hindi, Tamil, Telugu, and Bengali with English fallback.
// Used by InviteScreen and ShareHelper for multi-language sharing.

class InviteMessageBuilder {
  InviteMessageBuilder._();

  /// Build a localized invite message for the given [familyName],
  /// [inviteUrl], and [langCode].
  ///
  /// [langCode] should be an ISO 639-1 language code (e.g. 'hi', 'ta').
  /// Falls back to English for unsupported languages.
  static String build(String familyName, String inviteUrl, String langCode) {
    switch (langCode) {
      case 'hi':
        return 'नमस्ते! $familyName परिवार में शामिल हों।\n$inviteUrl';
      case 'ta':
        return 'வணக்கம்! $familyName குடும்பத்தில் சேருங்கள்।\n$inviteUrl';
      case 'te':
        return 'నమస్కారం! $familyName కుటుంబంలో చేరండి।\n$inviteUrl';
      case 'bn':
        return 'নমস্কার! $familyName পরিবারে যোগ দিন।\n$inviteUrl';
      default:
        return 'Join our family tree on Daxelo Kinrel!\nFamily: $familyName\n$inviteUrl';
    }
  }
}
