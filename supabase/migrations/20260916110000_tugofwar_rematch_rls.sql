-- ============================================================================
-- Tug of War — rematch roster copy fix.
--
-- The host's rematch flow re-inserts the previous roster (other players'
-- rows) client-side. The original tugofwar_players_insert policy only
-- allowed inserting YOUR OWN row, so the copy silently failed and rematches
-- started with the host alone.
--
-- Fix: the insert policy now also allows a family member who is the HOST of
-- the game to insert rows for other players (rematch roster copy). Family
-- scoping is still enforced through the game row's familyId.
-- ============================================================================

DROP POLICY IF EXISTS "tugofwar_players_insert" ON "tugofwar_players";
CREATE POLICY "tugofwar_players_insert" ON "tugofwar_players" FOR INSERT TO authenticated WITH CHECK (
  (
    -- Joining a room: your own row.
    "userId" = auth.uid()::text
    OR
    -- Host copying a rematch roster: any family member's row, but only
    -- into a game this user hosts.
    EXISTS (
      SELECT 1 FROM "tugofwar_games" g
      WHERE g."id" = "tugofwar_players"."gameId"
        AND g."hostUserId" = auth.uid()::text
        AND EXISTS (
          SELECT 1 FROM "FamilyMember" fm
          WHERE fm."familyId" = g."familyId"
            AND fm."userId" = auth.uid()::text)
    )
  )
  AND EXISTS (
    SELECT 1 FROM "tugofwar_games" g
    JOIN "FamilyMember" fm ON fm."familyId" = g."familyId"
    WHERE g."id" = "tugofwar_players"."gameId"
      AND fm."userId" = auth.uid()::text
  )
);
