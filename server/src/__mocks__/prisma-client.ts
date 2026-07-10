/**
 * Mock for @prisma/client — used by Jest tests.
 *
 * Provides a lightweight PrismaClient stub so that service unit tests
 * can run without a real database connection.
 *
 * Updated by Agent-3: Added all social/community model mocks.
 */

const makeModelMock = () => ({
  findUnique: jest.fn().mockResolvedValue(null),
  findFirst: jest.fn().mockResolvedValue(null),
  findMany: jest.fn().mockResolvedValue([]),
  create: jest.fn().mockResolvedValue({}),
  createMany: jest.fn().mockResolvedValue({ count: 0 }),
  update: jest.fn().mockResolvedValue({}),
  updateMany: jest.fn().mockResolvedValue({ count: 0 }),
  delete: jest.fn().mockResolvedValue({}),
  deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
  upsert: jest.fn().mockResolvedValue({}),
  count: jest.fn().mockResolvedValue(0),
  groupBy: jest.fn().mockResolvedValue([]),
  aggregate: jest.fn().mockResolvedValue({}),
});

const makeModelMockWithDeleteMany = () => ({
  ...makeModelMock(),
  deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
});

export class PrismaClient {
  $connect = jest.fn().mockResolvedValue(undefined);
  $disconnect = jest.fn().mockResolvedValue(undefined);
  $transaction = jest.fn((fn: any) => (typeof fn === 'function' ? fn(this) : Promise.resolve()));
  $queryRaw = jest.fn().mockResolvedValue([]);
  $queryRawUnsafe = jest.fn().mockResolvedValue([]);
  $executeRaw = jest.fn().mockResolvedValue(0);
  $executeRawUnsafe = jest.fn().mockResolvedValue(0);
  $on = jest.fn();

  // ── Core models ──────────────────────────────────────────────────
  user = makeModelMock();
  family = makeModelMock();
  member = makeModelMock();
  relationship = makeModelMock();
  invitation = makeModelMock();
  notification = makeModelMock();
  session = makeModelMock();

  // ── Agent-3 Social/Community models ──────────────────────────────
  follow = makeModelMock();
  sparq = makeModelMockWithDeleteMany();
  sparqView = makeModelMock();
  sparqEcho = makeModelMock();
  story = makeModelMockWithDeleteMany();
  storyView = makeModelMock();
  community = makeModelMock();
  communityMember = makeModelMock();
  communityPost = makeModelMock();
  communityEvent = makeModelMock();
  eventRSVP = makeModelMock();
  eventReminder = makeModelMock();
  communityRule = makeModelMock();

  // ── Agent-3 Timeline models ──────────────────────────────────────
  reaction = makeModelMock();
  comment = makeModelMock();
  familyPost = makeModelMock();
  familyMember = makeModelMock();

  // ── Agent-3 Gamification models ──────────────────────────────────
  badge = makeModelMock();
  userBadge = makeModelMock();
  userContribution = makeModelMock();

  // ── Agent-3 Share models ─────────────────────────────────────────
  shareableLink = makeModelMock();

  // ── Other models used in lookups ─────────────────────────────────
  person = makeModelMock();
  blockedUser = makeModelMock();
  familyConnection = makeModelMock();
  familyMilestone = makeModelMock();

  // ── Agent-7 Track C (AURA Governance) models ──────────────────────
  // Constitution lifecycle
  familyConstitution = makeModelMockWithDeleteMany();
  constitutionVersion = makeModelMockWithDeleteMany();
  constitutionArticle = makeModelMockWithDeleteMany();
  constitutionClause = makeModelMockWithDeleteMany();

  // Decisions + voting
  familyDecision = makeModelMockWithDeleteMany();
  decisionVote = makeModelMock();
  decisionMemory = makeModelMock();
  decisionImpact = makeModelMock();

  // AURA Timeline
  aURATimelineEvent = makeModelMock();

  // AURA Intelligence
  aIInsight = makeModelMockWithDeleteMany();
  aICostBudget = makeModelMock();

  // AURA Learning
  learningSignal = makeModelMock();
  familyBehaviorProfile = makeModelMock();
  familyBehaviorProfileHistory = makeModelMock();
  globalLearningDefaults = makeModelMock();

  // AURA Search
  searchIndex = makeModelMockWithDeleteMany();

  // AURA Analytics
  familyAnalyticsSnapshot = makeModelMock();

  // AURA Secretary
  meetingArtifact = makeModelMockWithDeleteMany();

  // Smart Reminders
  smartReminder = makeModelMock();

  // Governance sync watermarks
  syncWatermark = makeModelMock();
}
