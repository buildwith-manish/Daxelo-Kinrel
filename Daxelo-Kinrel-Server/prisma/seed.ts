import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

// ═══════════════════════════════════════════════════════════════════════
// DEMO LOGIN CREDENTIALS
// ═══════════════════════════════════════════════════════════════════════
// Email:    demo@kinrel.com
// Password: Demo@1234
// ═══════════════════════════════════════════════════════════════════════

const DEMO_USERS = [
  {
    name: 'Demo User',
    email: 'demo@kinrel.com',
    password: 'Demo@1234',
    role: 'user',
    preferredLanguage: 'hi',
  },
  {
    name: 'Admin User',
    email: 'admin@kinrel.com',
    password: 'Admin@1234',
    role: 'admin',
    preferredLanguage: 'en',
  },
];

async function main() {
  console.log('🌱 Seeding database...\n');

  for (const demoUser of DEMO_USERS) {
    // Check if user already exists
    const existing = await prisma.user.findUnique({
      where: { email: demoUser.email },
    });

    if (existing) {
      console.log(`⏭️  User already exists: ${demoUser.email}`);
      continue;
    }

    // Hash password with bcrypt (same as auth.service.ts)
    const salt = await bcrypt.genSalt(12);
    const passwordHash = await bcrypt.hash(demoUser.password, salt);

    // Create user + default family in transaction
    const result = await prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          name: demoUser.name,
          email: demoUser.email,
          passwordHash,
          role: demoUser.role,
          preferredLanguage: demoUser.preferredLanguage,
        },
        select: { id: true, email: true, name: true, role: true },
      });

      const family = await tx.family.create({
        data: {
          name: `${demoUser.name}'s Family`,
          primaryLanguage: demoUser.preferredLanguage,
        },
      });

      await tx.familyMember.create({
        data: {
          familyId: family.id,
          userId: user.id,
          role: 'admin',
        },
      });

      // Create free subscription for demo user
      await tx.subscription.create({
        data: {
          userId: user.id,
          plan: 'free',
          status: 'active',
          supportTier: 'basic',
        },
      });

      return { user, familyId: family.id };
    });

    console.log(`✅ Created: ${result.user.email} (${result.user.role}) — Family ID: ${result.familyId}`);
  }

  console.log('\n🎉 Seeding complete!');
  console.log('══════════════════════════════════════════════');
  console.log('📋 Demo Login Credentials:');
  console.log('');
  console.log('  👤 Demo User:');
  console.log('     Email:    demo@kinrel.com');
  console.log('     Password: Demo@1234');
  console.log('');
  console.log('  🛡️  Admin User:');
  console.log('     Email:    admin@kinrel.com');
  console.log('     Password: Admin@1234');
  console.log('══════════════════════════════════════════════');
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
