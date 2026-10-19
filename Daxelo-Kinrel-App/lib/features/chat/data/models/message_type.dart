// lib/features/chat/data/models/message_type.dart
//
// Extracted from lib/features/chat/providers/chat_provider.dart (Phase 0
// refactor — zero behavior change). Re-exported by chat_provider.dart so
// no existing import changes.

/// Message type — drives the bubble content and layout.
enum MessageType {
  text,
  photo,
  voiceNote,
  familyEvent,
  sticker,
  gameInvite,
  poll,
  gif,
  document,
  location,
  system,
}
