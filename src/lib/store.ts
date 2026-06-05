// In-memory data store for the Daxelo Kinrel app
// This simulates a database with stories, users, and families

export interface User {
  id: string;
  email: string;
  name: string;
  username: string;
  avatar: string | null;
}

export interface Family {
  id: string;
  name: string;
  familyCode: string | null;
  avatar: string | null;
  description: string | null;
  memberCount: number;
  generationCount: number;
}

export interface FamilyMember {
  id: string;
  userId: string;
  familyId: string;
  role: string;
}

export interface Story {
  id: string;
  userId: string;
  familyId: string | null;
  caption: string | null;
  mediaType: string;
  bgGradient: string;
  viewed: boolean;
  createdAt: string;
  expiresAt: string;
  user: User;
  views: { viewerId: string; viewedAt: string }[];
}

// ── Seed Data ──────────────────────────────────────────────

const users: User[] = [
  { id: "u1", email: "manish@example.com", name: "Manish", username: "manish", avatar: null },
  { id: "u2", email: "sneha@example.com", name: "Sneha", username: "sneha_sharma", avatar: null },
  { id: "u3", email: "rahul@example.com", name: "Rahul", username: "royal_rahul", avatar: null },
  { id: "u4", email: "sunita@example.com", name: "Sunita", username: "sunita_dev", avatar: null },
  { id: "u5", email: "vikram@example.com", name: "Vikram", username: "vikram_s", avatar: null },
  { id: "u6", email: "priya@example.com", name: "Priya", username: "priya_k", avatar: null },
];

const families: Family[] = [
  {
    id: "f1",
    name: "Sharma Family",
    familyCode: "sharmafamilytbo4",
    avatar: null,
    description: "The Sharma family - united by love and tradition",
    memberCount: 5,
    generationCount: 3,
  },
  {
    id: "f2",
    name: "Patel Family",
    familyCode: "patel_kin",
    avatar: null,
    description: "Patel family - spreading joy everywhere",
    memberCount: 3,
    generationCount: 2,
  },
];

const familyMembers: FamilyMember[] = [
  { id: "fm1", userId: "u1", familyId: "f1", role: "admin" },
  { id: "fm2", userId: "u2", familyId: "f1", role: "member" },
  { id: "fm3", userId: "u3", familyId: "f1", role: "member" },
  { id: "fm4", userId: "u4", familyId: "f1", role: "member" },
  { id: "fm5", userId: "u5", familyId: "f1", role: "member" },
  { id: "fm6", userId: "u4", familyId: "f2", role: "admin" },
  { id: "fm7", userId: "u6", familyId: "f2", role: "member" },
];

const now = new Date();
const hour = 60 * 60 * 1000;
const day = 24 * hour;

const gradients = [
  "from-orange-500 to-amber-600",
  "from-rose-500 to-pink-600",
  "from-emerald-500 to-teal-600",
  "from-violet-500 to-purple-600",
  "from-sky-500 to-blue-600",
  "from-amber-500 to-orange-600",
  "from-pink-500 to-rose-600",
  "from-teal-500 to-cyan-600",
];

const stories: Story[] = [
  {
    id: "s1",
    userId: "u1",
    familyId: "f1",
    caption: "Family reunion this weekend! Can't wait to see everyone 🎉",
    mediaType: "text",
    bgGradient: gradients[0],
    viewed: false,
    createdAt: new Date(now.getTime() - 1 * hour).toISOString(),
    expiresAt: new Date(now.getTime() + 23 * hour).toISOString(),
    user: users[0],
    views: [],
  },
  {
    id: "s2",
    userId: "u1",
    familyId: "f1",
    caption: "Added new branch to the Sharma family tree! 🌳",
    mediaType: "text",
    bgGradient: gradients[1],
    viewed: false,
    createdAt: new Date(now.getTime() - 3 * hour).toISOString(),
    expiresAt: new Date(now.getTime() + 21 * hour).toISOString(),
    user: users[0],
    views: [],
  },
  {
    id: "s3",
    userId: "u2",
    familyId: "f1",
    caption: "Celebrating Diwali together! Wishing everyone joy and prosperity 🪔✨",
    mediaType: "text",
    bgGradient: gradients[2],
    viewed: false,
    createdAt: new Date(now.getTime() - 5 * hour).toISOString(),
    expiresAt: new Date(now.getTime() + 19 * hour).toISOString(),
    user: users[1],
    views: [],
  },
  {
    id: "s4",
    userId: "u3",
    familyId: "f1",
    caption: "Found a new relation path! Check the family graph 📊",
    mediaType: "text",
    bgGradient: gradients[3],
    viewed: false,
    createdAt: new Date(now.getTime() - 8 * hour).toISOString(),
    expiresAt: new Date(now.getTime() + 16 * hour).toISOString(),
    user: users[2],
    views: [],
  },
  {
    id: "s5",
    userId: "u4",
    familyId: "f1",
    caption: "Morning chai with the family ☕ Nothing beats this",
    mediaType: "text",
    bgGradient: gradients[4],
    viewed: false,
    createdAt: new Date(now.getTime() - 10 * hour).toISOString(),
    expiresAt: new Date(now.getTime() + 14 * hour).toISOString(),
    user: users[3],
    views: [],
  },
  {
    id: "s6",
    userId: "u5",
    familyId: "f1",
    caption: "Our family grew by one more today! Welcome little one 🍼",
    mediaType: "text",
    bgGradient: gradients[5],
    viewed: false,
    createdAt: new Date(now.getTime() - 12 * hour).toISOString(),
    expiresAt: new Date(now.getTime() + 12 * hour).toISOString(),
    user: users[4],
    views: [],
  },
  {
    id: "s7",
    userId: "u4",
    familyId: "f2",
    caption: "Patel family picnic was amazing! 🧺",
    mediaType: "text",
    bgGradient: gradients[6],
    viewed: false,
    createdAt: new Date(now.getTime() - 6 * hour).toISOString(),
    expiresAt: new Date(now.getTime() + 18 * hour).toISOString(),
    user: users[3],
    views: [],
  },
  {
    id: "s8",
    userId: "u6",
    familyId: "f2",
    caption: "Found my cousins through Kinrel! 🎊",
    mediaType: "text",
    bgGradient: gradients[7],
    viewed: false,
    createdAt: new Date(now.getTime() - 2 * hour).toISOString(),
    expiresAt: new Date(now.getTime() + 22 * hour).toISOString(),
    user: users[5],
    views: [],
  },
];

// ── Query helpers ──────────────────────────────────────────

export function getUsers(): User[] {
  return users;
}

export function getUserById(id: string): User | undefined {
  return users.find((u) => u.id === id);
}

export function getFamilies(): Family[] {
  return families;
}

export function getFamilyById(id: string): Family | undefined {
  return families.find((f) => f.id === id);
}

export function getFamilyMembers(familyId: string): (FamilyMember & { user: User })[] {
  return familyMembers
    .filter((fm) => fm.familyId === familyId)
    .map((fm) => ({
      ...fm,
      user: users.find((u) => u.id === fm.userId)!,
    }));
}

export function getUserFamilies(userId: string): Family[] {
  const userFamilyIds = familyMembers
    .filter((fm) => fm.userId === userId)
    .map((fm) => fm.familyId);
  return families.filter((f) => userFamilyIds.includes(f.id));
}

export function getStories(familyId?: string): Story[] {
  if (familyId) {
    return stories.filter((s) => s.familyId === familyId);
  }
  return stories;
}

export function getStoriesByUser(userId: string): Story[] {
  return stories.filter((s) => s.userId === userId);
}

export function getStoriesGroupedByUser(familyId?: string): { user: User; stories: Story[]; hasUnviewed: boolean }[] {
  const filtered = familyId ? stories.filter((s) => s.familyId === familyId) : stories;
  const grouped = new Map<string, Story[]>();

  for (const story of filtered) {
    const existing = grouped.get(story.userId) || [];
    existing.push(story);
    grouped.set(story.userId, existing);
  }

  return Array.from(grouped.entries()).map(([userId, userStories]) => {
    const user = users.find((u) => u.id === userId)!;
    return {
      user,
      stories: userStories.sort(
        (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
      ),
      hasUnviewed: userStories.some((s) => !s.viewed),
    };
  });
}

export function markStoryViewed(storyId: string, viewerId: string): Story | null {
  const story = stories.find((s) => s.id === storyId);
  if (!story) return null;
  story.viewed = true;
  story.views.push({ viewerId, viewedAt: new Date().toISOString() });
  return story;
}

export function addStory(data: {
  userId: string;
  familyId?: string;
  caption?: string;
  bgGradient?: string;
}): Story {
  const newStory: Story = {
    id: `s${stories.length + 1}`,
    userId: data.userId,
    familyId: data.familyId || null,
    caption: data.caption || null,
    mediaType: "text",
    bgGradient: data.bgGradient || gradients[Math.floor(Math.random() * gradients.length)],
    viewed: false,
    createdAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 24 * hour).toISOString(),
    user: users.find((u) => u.id === data.userId)!,
    views: [],
  };
  stories.push(newStory);
  return newStory;
}
