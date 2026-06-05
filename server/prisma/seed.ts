import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  console.log('🌱 Seeding database...');

  // ── Demo User ──────────────────────────────────────────────────
  const passwordHash = await bcrypt.hash('demo1234', 12);

  const user = await prisma.user.upsert({
    where: { email: 'demo@kinrel.co' },
    update: {},
    create: {
      email: 'demo@kinrel.co',
      name: 'Demo User',
      passwordHash,
      role: 'user',
      preferredLanguage: 'en',
    },
  });

  console.log(`  ✅ User: ${user.email}`);

  // ── Demo Family ────────────────────────────────────────────────
  const family = await prisma.family.create({
    data: {
      name: 'Sharma Family',
      username: 'sharmafamily-demo',
      primaryLanguage: 'hi',
      privacyMode: 'private',
      memberCount: 1,
      createdBy: user.id,
      lastActivityAt: new Date(),
    },
  });

  console.log(`  ✅ Family: ${family.name}`);

  // ── Family Membership ──────────────────────────────────────────
  await prisma.familyMember.create({
    data: {
      familyId: family.id,
      userId: user.id,
      role: 'admin',
    },
  });

  // ── Anchor Person (Grandfather) ────────────────────────────────
  const ramesh = await prisma.person.create({
    data: {
      familyId: family.id,
      name: 'Ramesh Sharma',
      gender: 'male',
      generationIndex: 0,
      isAnchor: true,
      sideOfFamily: 'paternal',
    },
  });

  // ── Grandmother ────────────────────────────────────────────────
  const savitri = await prisma.person.create({
    data: {
      familyId: family.id,
      name: 'Savitri Sharma',
      gender: 'female',
      generationIndex: 0,
      sideOfFamily: 'paternal',
    },
  });

  // Grandfather ↔ Grandmother (spouse)
  await prisma.relationship.create({
    data: {
      familyId: family.id,
      fromPersonId: ramesh.id,
      toPersonId: savitri.id,
      relationshipKey: 'wife',
      relationshipType: 'wife',
      direction: 'from',
    },
  });

  // ── Father ─────────────────────────────────────────────────────
  const vijay = await prisma.person.create({
    data: {
      familyId: family.id,
      name: 'Vijay Sharma',
      gender: 'male',
      generationIndex: 1,
      sideOfFamily: 'paternal',
    },
  });

  // Grandfather → Father (son)
  await prisma.relationship.create({
    data: {
      familyId: family.id,
      fromPersonId: ramesh.id,
      toPersonId: vijay.id,
      relationshipKey: 'son',
      relationshipType: 'son',
      direction: 'from',
    },
  });

  // ── Mother ─────────────────────────────────────────────────────
  const priya = await prisma.person.create({
    data: {
      familyId: family.id,
      name: 'Priya Sharma',
      gender: 'female',
      generationIndex: 1,
      sideOfFamily: 'maternal',
    },
  });

  // Father ↔ Mother (spouse)
  await prisma.relationship.create({
    data: {
      familyId: family.id,
      fromPersonId: vijay.id,
      toPersonId: priya.id,
      relationshipKey: 'wife',
      relationshipType: 'wife',
      direction: 'from',
    },
  });

  // ── Uncle (Father's Brother) ───────────────────────────────────
  const anil = await prisma.person.create({
    data: {
      familyId: family.id,
      name: 'Anil Sharma',
      gender: 'male',
      generationIndex: 1,
      sideOfFamily: 'paternal',
    },
  });

  // Grandfather → Uncle (son)
  await prisma.relationship.create({
    data: {
      familyId: family.id,
      fromPersonId: ramesh.id,
      toPersonId: anil.id,
      relationshipKey: 'son',
      relationshipType: 'son',
      direction: 'from',
    },
  });

  // ── Self (Demo User) ───────────────────────────────────────────
  const self = await prisma.person.create({
    data: {
      familyId: family.id,
      name: 'Arjun Sharma',
      gender: 'male',
      generationIndex: 2,
      sideOfFamily: 'paternal',
    },
  });

  // Father → Self (son)
  await prisma.relationship.create({
    data: {
      familyId: family.id,
      fromPersonId: vijay.id,
      toPersonId: self.id,
      relationshipKey: 'son',
      relationshipType: 'son',
      direction: 'from',
    },
  });

  // Update family member count and anchor
  await prisma.family.update({
    where: { id: family.id },
    data: { memberCount: 6, anchorPersonId: ramesh.id },
  });

  console.log(`  ✅ Created 6 persons with relationships`);
  console.log('🌱 Seeding complete!');
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
