/**
 * KINREL Mirror — Shared Type Definitions
 * All domain types used across the application.
 */

// ── Authentication ────────────────────────────────────────────────

export interface AuthUser {
  id: string;
  email: string;
  name: string;
  role: UserRole;
  preferredLanguage: string;
}

export type UserRole = 'user' | 'admin' | 'agent';

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface RegisterRequest {
  name: string;
  email: string;
  password: string;
}

// ── Family ────────────────────────────────────────────────────────

export interface Family {
  id: string;
  name: string;
  description: string | null;
  primaryLanguage: string;
  gotra: string | null;
  originVillage: string | null;
  memberCount: number;
  personCount: number;
  role?: FamilyRole;
  createdAt: string;
  updatedAt: string;
}

export type FamilyRole = 'admin' | 'editor' | 'member' | 'viewer';

export interface CreateFamilyRequest {
  name: string;
  description?: string;
  primaryLanguage?: string;
  gotra?: string;
  originVillage?: string;
}

// ── Person ────────────────────────────────────────────────────────

export interface Person {
  id: string;
  familyId: string;
  name: string;
  relationship: string | null;
  dateOfBirth: string | null;
  gotra: string | null;
  occupation: string | null;
  city: string | null;
  isDeceased: boolean;
  privacyLevel: PrivacyLevel;
  createdAt: string;
  updatedAt: string;
}

export type PrivacyLevel = 'family' | 'extended' | 'public';

export interface CreatePersonRequest {
  name: string;
  relationship: string;
  dateOfBirth?: string;
  gotra?: string;
  occupation?: string;
  city?: string;
  isDeceased?: boolean;
  privacyLevel?: PrivacyLevel;
}

// ── Relationship ──────────────────────────────────────────────────

export interface Relationship {
  id: string;
  familyId: string;
  fromPersonId: string;
  toPersonId: string;
  type: string;
  direction: string;
  fromPerson?: Person;
  toPerson?: Person;
  createdAt: string;
  updatedAt: string;
}

export interface CreateRelationshipRequest {
  fromPersonId: string;
  toPersonId: string;
  type: string;
}

// ── Graph / Tree ──────────────────────────────────────────────────

export interface TreeNode {
  person: PersonSummary;
  spouse?: PersonSummary;
  children: TreeNode[];
}

export interface PersonSummary {
  id: string;
  name: string;
  relationship: string | null;
  dateOfBirth: string | null;
  isDeceased: boolean;
  privacyLevel: string;
  occupation: string | null;
  city: string | null;
  gotra: string | null;
}

export interface PathStep {
  relationshipId: string;
  type: string;
  direction: 'from' | 'to';
  localizedType?: string;
  fromPerson?: { id: string; name: string };
  toPerson?: { id: string; name: string };
}

export interface PathResult {
  from: { id: string; name: string };
  to: { id: string; name: string };
  path: PathStep[] | null;
  length: number;
  relationshipDescription?: string;
  localizedDescription?: string;
}

// ── Notification ──────────────────────────────────────────────────

export interface Notification {
  id: string;
  userId: string;
  eventType: string;
  title: string;
  body: string;
  channels: string[];
  priority: NotificationPriority;
  read: boolean;
  readAt: string | null;
  createdAt: string;
}

export type NotificationPriority = 'critical' | 'high' | 'normal' | 'low';

// ── Community ─────────────────────────────────────────────────────

export interface Community {
  id: string;
  type: CommunityType;
  name: string;
  slug: string;
  description: string | null;
  memberCount: number;
  isPrivate: boolean;
  isVerified: boolean;
  createdAt: string;
}

export type CommunityType = 'gotra' | 'village' | 'surname' | 'custom';

// ── Support ───────────────────────────────────────────────────────

export interface SupportTicket {
  id: string;
  ticketNumber: string;
  userId: string;
  category: TicketCategory;
  severity: TicketSeverity;
  subject: string;
  status: TicketStatus;
  createdAt: string;
}

export type TicketCategory = 'billing' | 'account' | 'data_loss' | 'bug' | 'feature_request' | 'general' | 'matrimonial' | 'verification' | 'privacy';
export type TicketSeverity = 'critical' | 'high' | 'medium' | 'low';
export type TicketStatus = 'open' | 'in_progress' | 'waiting_customer' | 'resolved' | 'closed';

// ── Developer ─────────────────────────────────────────────────────

export interface ApiKeyInfo {
  id: string;
  name: string;
  keyPrefix: string;
  scopes: string[];
  tier: ApiKeyTier;
  rateLimitPerMinute: number;
  lastUsedAt: string | null;
  expiresAt: string | null;
  revokedAt: string | null;
  createdAt: string;
}

export type ApiKeyTier = 'free' | 'pro' | 'enterprise';

// ── Pagination ────────────────────────────────────────────────────

export interface PaginationInfo {
  page: number;
  limit: number;
  total: number;
  hasMore: boolean;
  totalPages: number;
}

export interface ApiResponse<T> {
  data: T;
  meta: {
    requestId: string;
    timestamp: string;
    version: string;
  };
}

export interface ApiCollectionResponse<T> {
  data: T[];
  meta: {
    requestId: string;
    timestamp: string;
    version: string;
  };
  pagination: PaginationInfo;
}

// ── Moderation ────────────────────────────────────────────────────

export type ModerationCategory = 'safe' | 'borderline' | 'harassment' | 'hate_speech' | 'violence' | 'sexual_content' | 'csam' | 'pii_exposure' | 'spam';
export type ModerationAction = 'allow' | 'allow_with_flag' | 'quarantine' | 'reject' | 'escalate';
export type ModerationPriority = 'low' | 'normal' | 'high' | 'urgent' | 'critical';

// ── Audit ─────────────────────────────────────────────────────────

export interface AuditLog {
  id: string;
  userId: string | null;
  action: string;
  resource: string;
  resourceId: string | null;
  details: string;
  createdAt: string;
}
