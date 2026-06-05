import { db } from "@/lib/db";

async function seed() {
  // Create users
  const manish = await db.user.create({
    data: {
      email: "manish@example.com",
      name: "Manish",
      username: "manish",
      avatar: null,
    },
  });

  const sneha = await db.user.create({
    data: {
      email: "sneha@example.com",
      name: "Sneha",
      username: "sneha_sharma",
      avatar: null,
    },
  });

  const rahul = await db.user.create({
    data: {
      email: "rahul@example.com",
      name: "Rahul",
      username: "royal_rahul",
      avatar: null,
    },
  });

  const sunita = await db.user.create({
    data: {
      email: "sunita@example.com",
      name: "Sunita",
      username: "sunita_dev",
      avatar: null,
    },
  });

  const vikram = await db.user.create({
    data: {
      email: "vikram@example.com",
      name: "Vikram",
      username: "vikram_s",
      avatar: null,
    },
  });

  // Create family
  const family = await db.family.create({
    data: {
      name: "Sharma Family",
      familyCode: "sharmafamilytbo4",
      description: "The Sharma family - united by love and tradition",
      memberCount: 4,
      generationCount: 3,
    },
  });

  // Add members to family
  await db.familyMember.createMany({
    data: [
      { userId: manish.id, familyId: family.id, role: "admin" },
      { userId: sneha.id, familyId: family.id, role: "member" },
      { userId: rahul.id, familyId: family.id, role: "member" },
      { userId: sunita.id, familyId: family.id, role: "member" },
    ],
  });

  // Create stories with different gradients
  const now = new Date();
  const tomorrow = new Date(now.getTime() + 24 * 60 * 60 * 1000);

  const gradients = [
    "from-orange-500 to-amber-600",
    "from-rose-500 to-pink-600",
    "from-emerald-500 to-teal-600",
    "from-violet-500 to-purple-600",
    "from-sky-500 to-blue-600",
    "from-amber-500 to-orange-600",
  ];

  const storiesData = [
    {
      userId: manish.id,
      familyId: family.id,
      caption: "Family reunion this weekend! 🎉",
      mediaUrl: "",
      mediaType: "text",
      bgGradient: gradients[0],
      expiresAt: tomorrow,
    },
    {
      userId: manish.id,
      familyId: family.id,
      caption: "New member added to the Sharma family tree 🌳",
      mediaUrl: "",
      mediaType: "text",
      bgGradient: gradients[1],
      expiresAt: tomorrow,
    },
    {
      userId: sneha.id,
      familyId: family.id,
      caption: "Celebrating Diwali together! 🪔✨",
      mediaUrl: "",
      mediaType: "text",
      bgGradient: gradients[2],
      expiresAt: tomorrow,
    },
    {
      userId: rahul.id,
      familyId: family.id,
      caption: "Found a new relation path! Check the family graph 📊",
      mediaUrl: "",
      mediaType: "text",
      bgGradient: gradients[3],
      expiresAt: tomorrow,
    },
    {
      userId: sunita.id,
      familyId: family.id,
      caption: "Morning chai with the family ☕",
      mediaUrl: "",
      mediaType: "text",
      bgGradient: gradients[4],
      expiresAt: tomorrow,
    },
    {
      userId: vikram.id,
      familyId: null,
      caption: "Just joined the app! Looking for my family 🔍",
      mediaUrl: "",
      mediaType: "text",
      bgGradient: gradients[5],
      expiresAt: tomorrow,
    },
  ];

  for (const story of storiesData) {
    await db.story.create({ data: story });
  }

  console.log("Seed data created successfully!");
  console.log({ users: [manish, sneha, rahul, sunita, vikram], family });
}

seed()
  .catch(console.error)
  .finally(() => db.$disconnect());
