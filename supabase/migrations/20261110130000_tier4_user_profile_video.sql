-- =============================================================================
-- Daxelo Kinrel — Tier 4 Feature 4.7: Profile video
-- =============================================================================
-- Lets a user set a short looping video as their profile pic. Plays on tap
-- in the member profile sheet.
--
-- Schema: add `profileVideoUrl text` to User (nullable; null = no video,
-- falls back to avatarUrl).
-- =============================================================================

ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "profileVideoUrl" text;

-- Verification
SELECT 'User.profileVideoUrl' AS col,
       EXISTS(
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'User' AND column_name = 'profileVideoUrl'
       ) AS exists;
