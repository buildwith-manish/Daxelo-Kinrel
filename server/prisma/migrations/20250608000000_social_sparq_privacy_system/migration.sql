-- CreateEnum: FollowStatus
CREATE TYPE "FollowStatus" AS ENUM ('PENDING', 'ACCEPTED', 'REJECTED');

-- CreateEnum: SparqType
CREATE TYPE "SparqType" AS ENUM ('IMAGE', 'VIDEO', 'TEXT', 'VOICE');

-- CreateEnum: SparqAudience
CREATE TYPE "SparqAudience" AS ENUM ('PUBLIC', 'FAMILY_ONLY');

-- AlterTable: Add social system fields to User
ALTER TABLE "User" ADD COLUMN "isPrivate" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "User" ADD COLUMN "isFamilyGraphPublic" BOOLEAN NOT NULL DEFAULT true;

-- AlterTable: Add social system fields to Family
ALTER TABLE "Family" ADD COLUMN "isPublic" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable: Add social system fields to FamilyInvite
ALTER TABLE "FamilyInvite" ADD COLUMN "creatorId" TEXT;
ALTER TABLE "FamilyInvite" ADD COLUMN "active" BOOLEAN NOT NULL DEFAULT true;

-- CreateTable: Follow
CREATE TABLE "Follow" (
    "id" TEXT NOT NULL,
    "followerId" TEXT NOT NULL,
    "followingId" TEXT NOT NULL,
    "status" "FollowStatus" NOT NULL DEFAULT 'ACCEPTED',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Follow_pkey" PRIMARY KEY ("id")
);

-- CreateTable: Sparq
CREATE TABLE "Sparq" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" "SparqType" NOT NULL,
    "mediaUrl" TEXT,
    "thumbnailUrl" TEXT,
    "text" TEXT,
    "backgroundColor" TEXT,
    "duration" INTEGER,
    "audience" "SparqAudience" NOT NULL DEFAULT 'PUBLIC',
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "viewCount" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "Sparq_pkey" PRIMARY KEY ("id")
);

-- CreateTable: SparqView
CREATE TABLE "SparqView" (
    "id" TEXT NOT NULL,
    "sparqId" TEXT NOT NULL,
    "viewerId" TEXT NOT NULL,
    "viewedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SparqView_pkey" PRIMARY KEY ("id")
);

-- CreateIndex: Follow unique constraint on follower+following
CREATE UNIQUE INDEX "Follow_followerId_followingId_key" ON "Follow"("followerId", "followingId");

-- CreateIndex: Follow indexes
CREATE INDEX "Follow_followerId_idx" ON "Follow"("followerId");
CREATE INDEX "Follow_followingId_idx" ON "Follow"("followingId");

-- CreateIndex: FamilyInvite creatorId index
CREATE INDEX "FamilyInvite_creatorId_idx" ON "FamilyInvite"("creatorId");

-- CreateIndex: Sparq indexes
CREATE INDEX "Sparq_userId_createdAt_idx" ON "Sparq"("userId", "createdAt");
CREATE INDEX "Sparq_expiresAt_idx" ON "Sparq"("expiresAt");
CREATE INDEX "Sparq_audience_idx" ON "Sparq"("audience");

-- CreateIndex: SparqView unique constraint on sparq+viewer
CREATE UNIQUE INDEX "SparqView_sparqId_viewerId_key" ON "SparqView"("sparqId", "viewerId");

-- CreateIndex: SparqView indexes
CREATE INDEX "SparqView_sparqId_idx" ON "SparqView"("sparqId");
CREATE INDEX "SparqView_viewerId_idx" ON "SparqView"("viewerId");

-- AddForeignKey: Follow.followerId -> User.id
ALTER TABLE "Follow" ADD CONSTRAINT "Follow_followerId_fkey" FOREIGN KEY ("followerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey: Follow.followingId -> User.id
ALTER TABLE "Follow" ADD CONSTRAINT "Follow_followingId_fkey" FOREIGN KEY ("followingId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey: FamilyInvite.creatorId -> User.id
ALTER TABLE "FamilyInvite" ADD CONSTRAINT "FamilyInvite_creatorId_fkey" FOREIGN KEY ("creatorId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey: Sparq.userId -> User.id
ALTER TABLE "Sparq" ADD CONSTRAINT "Sparq_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey: SparqView.sparqId -> Sparq.id
ALTER TABLE "SparqView" ADD CONSTRAINT "SparqView_sparqId_fkey" FOREIGN KEY ("sparqId") REFERENCES "Sparq"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey: SparqView.viewerId -> User.id
ALTER TABLE "SparqView" ADD CONSTRAINT "SparqView_viewerId_fkey" FOREIGN KEY ("viewerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
