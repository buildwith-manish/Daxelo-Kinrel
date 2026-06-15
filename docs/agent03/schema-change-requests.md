# Agent-03 (Social-Community) Schema Change Requests

> **To:** Agent-0 (Schema Owner)
> **From:** Agent-3 (Social-Community)
> **Date:** 2025-06-15
> **Priority:** High — Required for feature completeness

This document lists all Prisma schema changes needed by Agent-3's social/community modules. These changes cannot be made by Agent-3 directly per the ownership boundaries. Each request includes the current schema, the proposed change, and the justification.

---

## 1. Story: Add `audience` and `thumbnailUrl` fields

### Current Schema (Story model)
```prisma
model Story {
  id         String   @id @default(cuid())
  userId     String
  familyId   String?
  caption    String?
  mediaUrl   String   @default("")
  mediaType  String   @default("text")
  bgGradient String?
  expiresAt  DateTime
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt
  // ...relations
}
```

### Proposed Changes
```prisma
model Story {
  // ... existing fields ...

  audience     String   @default("PUBLIC")  // PUBLIC | FAMILY_ONLY
  thumbnailUrl String?                       // Auto-generated thumbnail for video stories

  // ... existing relations ...
}
```

### Justification
- **`audience`**: Stories backend-hardening branch already implements audience-scoped visibility (PUBLIC vs FAMILY_ONLY). The controller validates and checks family membership. Currently, the field is passed via DTO but not persisted because the column doesn't exist. Without this column, audience filtering is non-functional in production.
- **`thumbnailUrl`**: Video stories need a thumbnail for the story tray preview. The backend can generate thumbnails from uploaded videos, but there's no column to store the URL. This is essential for the Flutter stories feature (Task 6).

---

## 2. CommunityMember: Add `status` field

### Current Schema (CommunityMember model)
```prisma
model CommunityMember {
  id          String   @id @default(cuid())
  communityId String
  userId      String
  role        String   @default("member") // owner, admin, moderator, member
  joinedAt    DateTime @default(now())
  joinedVia   String   @default("direct") // direct, invite_link, pending

  // ...relations
}
```

### Proposed Changes
```prisma
model CommunityMember {
  // ... existing fields ...

  status String @default("active") // active, pending, banned, muted

  // ... existing relations ...
}
```

### Justification
- Private communities require a join-request flow. Currently, the backend uses a workaround where `joinedVia='pending'` indicates a pending request, but this conflates two different concepts (how you joined vs. your current status).
- A dedicated `status` field enables: (1) proper pending/approval flow for private communities, (2) banning/muting members, (3) querying active members efficiently without checking `joinedVia`.
- The community-crud branch already implements pending flow logic using the `joinedVia` workaround, but this should be migrated to the `status` field for correctness.

---

## 3. ShareableLink: Add `userId` field

### Current Schema (ShareableLink model)
```prisma
model ShareableLink {
  id          String    @id @default(cuid())
  token       String    @unique
  cardType    String
  familyId    String?
  personId    String?
  title       String
  description String
  deepLinkUrl String
  viewCount   Int       @default(0)
  shareCount  Int       @default(0)
  expiresAt   DateTime?
  createdAt   DateTime  @default(now())

  @@index([token])
  @@index([cardType])
}
```

### Proposed Changes
```prisma
model ShareableLink {
  // ... existing fields ...

  userId String  // Who created this link — used for ownership and my-links
  user   User    @relation(fields: [userId], references: [id], onDelete: Cascade)

  // ... existing indexes ...
  @@index([userId])
}
```

### Justification
- The share-dtos-tracking branch (Task 2) adds `GET /share/mine` and `DELETE /share/:id` endpoints that need to filter by and verify `userId`. Currently, the `getMyShareableLinks` endpoint returns ALL links because there's no `userId` column to filter on.
- The `revokeShareableLink` endpoint cannot enforce ownership (any authenticated user can delete any link) because there's no `userId` to check against.
- Without this column, the share feature has a security vulnerability where any user can revoke any other user's share links.

---

## 4. Comment: Add `familyPostId` optional field

### Current Schema (Comment model)
```prisma
model Comment {
  id           String        @id @default(cuid())
  postId       String
  post         CommunityPost @relation(fields: [postId], references: [id], onDelete: Cascade)
  authorId     String
  author       User          @relation(fields: [authorId], references: [id])
  parentId     String?
  body         String
  isHidden     Boolean       @default(false)
  hiddenReason String?
  createdAt    DateTime      @default(now())
  updatedAt    DateTime      @updatedAt

  @@index([postId, createdAt])
  @@index([parentId])
  @@index([authorId])
}
```

### Proposed Changes
```prisma
model Comment {
  id           String        @id @default(cuid())
  postId       String
  post         CommunityPost? @relation(fields: [postId], references: [id], onDelete: Cascade)
  familyPostId String?                        // Optional FK to FamilyPost for timeline comments
  familyPost   FamilyPost?   @relation(fields: [familyPostId], references: [id], onDelete: Cascade)
  authorId     String
  author       User          @relation(fields: [authorId], references: [id])
  parentId     String?
  body         String
  isHidden     Boolean       @default(false)
  hiddenReason String?
  createdAt    DateTime      @default(now())
  updatedAt    DateTime      @updatedAt

  @@index([postId, createdAt])
  @@index([familyPostId, createdAt])
  @@index([parentId])
  @@index([authorId])
}
```

### Justification
- The timeline-reactions-comments branch (Task 1) stores comments inside the `FamilyPost.reactions` JSON field because the `Comment` model's FK only references `CommunityPost`. This is a temporary workaround that doesn't scale for posts with many comments.
- Adding an optional `familyPostId` field allows the Comment model to serve both CommunityPost comments AND FamilyPost timeline comments, with proper relational integrity.
- This would enable: (1) proper paginated comment retrieval via SQL queries instead of JSON parsing, (2) referential integrity with cascade delete, (3) efficient indexing and searching.
- Note: The `post` relation would need to become optional, and a validation constraint should ensure that either `postId` or `familyPostId` is set.

---

## 5. Reaction: Add `familyPostId` optional field

### Current Schema (Reaction model)
```prisma
model Reaction {
  id        String        @id @default(cuid())
  postId    String
  post      CommunityPost @relation(fields: [postId], references: [id], onDelete: Cascade)
  userId    String
  user      User          @relation(fields: [userId], references: [id], onDelete: Cascade)
  emoji     String
  createdAt DateTime      @default(now())

  @@unique([postId, userId, emoji])
  @@index([postId])
}
```

### Proposed Changes
```prisma
model Reaction {
  id           String        @id @default(cuid())
  postId       String
  post         CommunityPost? @relation(fields: [postId], references: [id], onDelete: Cascade)
  familyPostId String?                        // Optional FK to FamilyPost for timeline reactions
  familyPost   FamilyPost?   @relation(fields: [familyPostId], references: [id], onDelete: Cascade)
  userId       String
  user         User          @relation(fields: [userId], references: [id], onDelete: Cascade)
  emoji        String
  createdAt    DateTime      @default(now())

  @@unique([postId, familyPostId, userId, emoji])
  @@index([postId])
  @@index([familyPostId])
}
```

### Justification
- Same reasoning as Comment — the timeline module currently stores reactions in the `FamilyPost.reactions` JSON field as a workaround.
- Proper relational reactions would enable: (1) unique constraint per user/emoji per post, (2) efficient reaction counts via SQL aggregation, (3) consistent reaction model across both community and timeline posts.

---

## 6. UserContribution: Add `streakCount` and `lastCheckIn` fields

### Current Schema (UserContribution model)
```prisma
model UserContribution {
  id        String   @id @default(cuid())
  userId    String
  type      String   // post_created, comment_added, reaction_added, story_shared, etc.
  points    Int      @default(0)
  familyId  String?
  createdAt DateTime @default(now())

  @@index([userId])
  @@index([type])
}
```

### Proposed Changes
```prisma
model UserContribution {
  // ... existing fields ...

  streakCount  Int       @default(0)   // Current check-in streak
  lastCheckIn  DateTime?               // Last check-in timestamp

  // ... existing indexes ...
  @@index([lastCheckIn])
}
```

### Justification
- The gamification-db-persistence branch (Task previous) implements a check-in and streak system, but stores streak data in memory because there are no dedicated fields. The streak is calculated on the fly from contribution records, which is inefficient and unreliable.
- Adding `streakCount` and `lastCheckIn` directly to UserContribution (or alternatively creating a separate `UserStreak` model) would enable: (1) O(1) streak lookups, (2) accurate streak calculation without date arithmetic, (3) persistence of streak data across server restarts.
- Alternative: Create a new `UserStreak` model if keeping UserContribution focused on contribution tracking.

---

## Summary Table

| # | Model | Field(s) | Type | Priority | Blocking Task |
|---|-------|----------|------|----------|---------------|
| 1 | Story | `audience` | String @default("PUBLIC") | HIGH | Task 6 (Stories Flutter) |
| 1 | Story | `thumbnailUrl` | String? | MEDIUM | Task 6 (Stories Flutter) |
| 2 | CommunityMember | `status` | String @default("active") | HIGH | Community CRUD |
| 3 | ShareableLink | `userId` + relation | String + User | HIGH | Task 5 (Share Flutter) |
| 4 | Comment | `familyPostId` + relation | String? + FamilyPost? | MEDIUM | Task 1 (already workaround) |
| 5 | Reaction | `familyPostId` + relation | String? + FamilyPost? | MEDIUM | Task 1 (already workaround) |
| 6 | UserContribution | `streakCount`, `lastCheckIn` | Int, DateTime? | MEDIUM | Gamification check-ins |

---

## Migration Notes

After Agent-0 applies these changes, Agent-3 will need to:
1. Run `npx prisma generate` to update the Prisma client
2. Remove JSON-based comment/reaction storage in timeline service, migrate to proper Comment/Reaction rows
3. Update `getMyShareableLinks` to filter by `userId`
4. Update `revokeShareableLink` to enforce ownership via `userId`
5. Migrate community pending-flow from `joinedVia='pending'` to `status='pending'`
6. Update story creation to persist `audience` and `thumbnailUrl`
