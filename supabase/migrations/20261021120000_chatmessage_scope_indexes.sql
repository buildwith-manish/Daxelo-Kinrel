-- ============================================================
-- Migration: chatmessage_scope_indexes
-- Why: the chat client now loads each conversation scope on its own:
--   family-wide : WHERE familyId = ? AND groupId IS NULL  ORDER BY createdAt DESC LIMIT 50
--   group / DM  : WHERE familyId = ? AND groupId = ?      ORDER BY createdAt DESC LIMIT 50
-- The existing idx_chatmessage_family_created (familyId, createdAt) cannot
-- serve the groupId predicate, so large families would scan many rows.
-- Additive and idempotent.
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_chatmessage_family_group_created
  ON "ChatMessage" ("familyId", "groupId", "createdAt" DESC)
  WHERE "groupId" IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_chatmessage_family_nogroup_created
  ON "ChatMessage" ("familyId", "createdAt" DESC)
  WHERE "groupId" IS NULL;
