import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ConflictException,
  UnauthorizedException,
  HttpException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { ConfigService } from '@nestjs/config';
import { CacheService } from '../../common/cache/cache.service';
import * as bcrypt from 'bcryptjs';

/**
 * Rate limit tracker for username availability checks.
 * Key: userId, Value: array of timestamps (ms)
 */
interface RateLimitEntry {
  timestamps: number[];
}

@Injectable()
export class UsersService {
  // ── In-memory rate limiter for username checks (5 checks per minute per user) ──
  private readonly usernameCheckRateLimits = new Map<string, RateLimitEntry>();
  private static readonly USERNAME_CHECK_RATE_LIMIT = 5;
  private static readonly USERNAME_CHECK_RATE_WINDOW_MS = 60_000; // 1 minute

  // ── In-memory cache for username availability (30s TTL) ──
  private readonly usernameAvailabilityCache = new Map<
    string,
    { available: boolean; reason?: string; cachedAt: number }
  >();
  private static readonly USERNAME_AVAILABILITY_CACHE_TTL_MS = 30_000; // 30 seconds

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly cacheService: CacheService,
  ) {}

  // ── Get User by Username (public profile) ──────────────────────

  async getUserByUsername(username: string) {
    if (!username || username.trim().length < 3) {
      throw new BadRequestException('Invalid username');
    }

    const trimmed = username.trim().toLowerCase();

    // Prevent enumeration: check reserved words
    const reserved = ['admin', 'root', 'system', 'moderator', 'support', 'help', 'api', 'null', 'undefined', 'me', 'check-username'];
    if (reserved.includes(trimmed)) {
      throw new NotFoundException('User not found');
    }

    const user = await this.prisma.user.findUnique({
      where: { username: trimmed },
      select: {
        id: true,
        name: true,
        username: true,
        avatarUrl: true,
        photoThumb: true,
        bio: true,
        createdAt: true,
      },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Return limited public profile (no email, phone, etc.)
    return {
      id: user.id,
      name: user.name,
      username: user.username,
      avatarUrl: user.photoThumb || user.avatarUrl,
      bio: user.bio,
      memberSince: user.createdAt,
    };
  }

  // ── Get Profile (enhanced with all ProfileModel fields) ──────────

  async getProfile(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        name: true,
        phone: true,
        avatarUrl: true,
        photoThumb: true,
        photoCard: true,
        photoFull: true,
        bio: true,
        dateOfBirth: true,
        gender: true,
        username: true,
        preferredLanguage: true,
        profileVisibility: true,
        invitePermission: true,
        twoFactorEnabled: true,
        authProvider: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    return { user };
  }

  // ── Get Stats ───────────────────────────────────────────────────

  async getStats(userId: string) {
    const userFamilies = await this.prisma.familyMember.findMany({
      where: { userId },
      select: { familyId: true },
    });
    const familyIds = userFamilies.map((m) => m.familyId);

    const [familyCount, memberCount, relationCount] = await Promise.all([
      this.prisma.familyMember.count({ where: { userId } }),
      this.prisma.person.count({
        where: {
          familyId: { in: familyIds },
          deletedAt: null,
        },
      }),
      this.prisma.relationship.count({
        where: {
          familyId: { in: familyIds },
          isActive: true,
        },
      }),
    ]);

    return {
      familyTrees: familyCount,
      membersAdded: memberCount,
      relations: relationCount,
    };
  }

  // ── Update Profile (enhanced with more fields) ──────────────────

  async updateProfile(
    userId: string,
    data: {
      name?: string;
      phone?: string;
      preferredLanguage?: string;
      username?: string;
      bio?: string;
      dateOfBirth?: string;
      gender?: string;
      avatarUrl?: string;
      profileVisibility?: string;
      invitePermission?: string;
    },
  ) {
    const updateData: Record<string, unknown> = {};

    if (data.name !== undefined) updateData.name = data.name.trim();
    if (data.phone !== undefined) updateData.phone = data.phone.trim() || null;
    if (data.preferredLanguage !== undefined)
      updateData.preferredLanguage = data.preferredLanguage;
    if (data.username !== undefined)
      updateData.username = data.username.trim() || null;
    if (data.bio !== undefined) updateData.bio = data.bio.trim() || null;
    if (data.dateOfBirth !== undefined) {
      updateData.dateOfBirth = data.dateOfBirth
        ? new Date(data.dateOfBirth)
        : null;
    }
    if (data.gender !== undefined) updateData.gender = data.gender || null;
    if (data.avatarUrl !== undefined)
      updateData.avatarUrl = data.avatarUrl || null;
    if (data.profileVisibility !== undefined)
      updateData.profileVisibility = data.profileVisibility;
    if (data.invitePermission !== undefined)
      updateData.invitePermission = data.invitePermission;

    const user = await this.prisma.user.update({
      where: { id: userId },
      data: updateData,
      select: {
        id: true,
        email: true,
        name: true,
        phone: true,
        avatarUrl: true,
        photoThumb: true,
        photoCard: true,
        photoFull: true,
        bio: true,
        dateOfBirth: true,
        gender: true,
        username: true,
        preferredLanguage: true,
        profileVisibility: true,
        invitePermission: true,
        twoFactorEnabled: true,
        authProvider: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    return { user };
  }

  // ── Upload Avatar ───────────────────────────────────────────────

  async uploadAvatar(userId: string, file: Express.Multer.File) {
    if (!file) {
      throw new BadRequestException('No file provided');
    }

    // Upload to Cloudinary if configured, otherwise store as base64 data URL
    const cloudName = this.config.get<string>('CLOUDINARY_CLOUD_NAME');
    const apiKey = this.config.get<string>('CLOUDINARY_API_KEY');
    const apiSecret = this.config.get<string>('CLOUDINARY_API_SECRET');

    let avatarUrl: string;
    let photoThumb: string | null = null;
    let photoCard: string | null = null;
    let photoFull: string | null = null;

    if (cloudName && apiKey && apiSecret) {
      // Upload to Cloudinary
      const cloudinary = require('cloudinary').v2;
      cloudinary.config({ cloud_name: cloudName, api_key: apiKey, api_secret: apiSecret });

      const uploadResult = await new Promise((resolve, reject) => {
        const uploadStream = cloudinary.uploader.upload_stream(
          {
            folder: 'kinrel/avatars',
            public_id: `avatar_${userId}_${Date.now()}`,
            transformation: [{ width: 512, height: 512, crop: 'fill' }],
            overwrite: true,
          },
          (error: any, result: any) => {
            if (error) reject(error);
            else resolve(result);
          },
        );
        uploadStream.end(file.buffer);
      });

      const publicId = (uploadResult as any).public_id;
      avatarUrl = (uploadResult as any).secure_url;

      // Generate 3 URL variants using Cloudinary transformations
      photoThumb = cloudinary.url(publicId, {
        transformation: [{ width: 80, height: 80, crop: 'fill', quality: 'auto', fetch_format: 'auto' }],
      });
      photoCard = cloudinary.url(publicId, {
        transformation: [{ width: 150, height: 150, crop: 'fill', quality: 'auto', fetch_format: 'auto' }],
      });
      photoFull = cloudinary.url(publicId, {
        transformation: [{ width: 400, height: 400, crop: 'fill', quality: 'auto', fetch_format: 'webp' }],
      });
    } else {
      // Fallback: store as base64 data URL — all variants point to the same data URL
      const base64 = file.buffer.toString('base64');
      avatarUrl = `data:${file.mimetype};base64,${base64}`;
      photoThumb = avatarUrl;
      photoCard = avatarUrl;
      photoFull = avatarUrl;
    }

    const user = await this.prisma.user.update({
      where: { id: userId },
      data: { avatarUrl, photoThumb, photoCard, photoFull },
      select: {
        id: true,
        email: true,
        name: true,
        phone: true,
        avatarUrl: true,
        photoThumb: true,
        photoCard: true,
        photoFull: true,
        bio: true,
        dateOfBirth: true,
        gender: true,
        username: true,
        preferredLanguage: true,
        profileVisibility: true,
        invitePermission: true,
        twoFactorEnabled: true,
        authProvider: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    return { user };
  }

  // ── Delete Account (with optional password confirmation) ────────

  async deleteAccount(userId: string, password?: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    // If password is provided, verify it
    if (password && user.passwordHash) {
      const passwordValid = await bcrypt.compare(password, user.passwordHash);
      if (!passwordValid) {
        throw new UnauthorizedException('Password is incorrect');
      }
    }

    await this.prisma.$transaction(async (tx) => {
      // Revoke all refresh tokens
      await tx.refreshToken.deleteMany({ where: { userId } });

      // Delete user (cascades will handle related records)
      await tx.user.delete({ where: { id: userId } });
    });

    return { success: true, message: 'Account deleted' };
  }

  // ── Check Username Availability (with rate limiting + caching) ────

  async checkUsername(username: string, userId?: string) {
    if (!username || username.trim().length < 3) {
      return { available: false, reason: 'Username must be at least 3 characters' };
    }

    const trimmed = username.trim().toLowerCase();

    // ── Rate limiting (if userId is provided) ──
    if (userId) {
      this.enforceUsernameCheckRateLimit(userId);
    }

    // ── Check in-memory cache (30s TTL) ──
    const cached = this.usernameAvailabilityCache.get(trimmed);
    if (cached && Date.now() - cached.cachedAt < UsersService.USERNAME_AVAILABILITY_CACHE_TTL_MS) {
      return { available: cached.available, reason: cached.reason };
    }

    // Validate format
    const usernameRegex = /^[a-z][a-z0-9_]{2,29}$/;
    if (!usernameRegex.test(trimmed)) {
      const result = { available: false, reason: 'Username must be 3-30 characters, start with a letter, lowercase letters, numbers, and underscores only' };
      this.usernameAvailabilityCache.set(trimmed, { ...result, cachedAt: Date.now() });
      return result;
    }

    // Check reserved words
    const reserved = ['admin', 'root', 'system', 'moderator', 'support', 'help', 'api', 'null', 'undefined'];
    if (reserved.includes(trimmed)) {
      const result = { available: false, reason: 'This username is reserved' };
      this.usernameAvailabilityCache.set(trimmed, { ...result, cachedAt: Date.now() });
      return result;
    }

    // Check in User table
    const existingUser = await this.prisma.user.findUnique({
      where: { username: trimmed },
    });

    if (existingUser) {
      const result = { available: false, reason: 'Username is already taken' };
      this.usernameAvailabilityCache.set(trimmed, { ...result, cachedAt: Date.now() });
      return result;
    }

    // Also check in Person table
    const existingPerson = await this.prisma.person.findFirst({
      where: { username: trimmed, deletedAt: null },
    });

    if (existingPerson) {
      const result = { available: false, reason: 'Username is already taken' };
      this.usernameAvailabilityCache.set(trimmed, { ...result, cachedAt: Date.now() });
      return result;
    }

    const result = { available: true };
    this.usernameAvailabilityCache.set(trimmed, { ...result, cachedAt: Date.now() });
    return result;
  }

  // ── Rate limit enforcement for username checks ──────────────────

  private enforceUsernameCheckRateLimit(userId: string): void {
    const now = Date.now();
    const entry = this.usernameCheckRateLimits.get(userId) || { timestamps: [] };

    // Prune timestamps outside the window
    entry.timestamps = entry.timestamps.filter(
      (ts) => now - ts < UsersService.USERNAME_CHECK_RATE_WINDOW_MS,
    );

    if (entry.timestamps.length >= UsersService.USERNAME_CHECK_RATE_LIMIT) {
      throw new HttpException(
        'Too many username checks. Please try again in a minute.',
        429,
      );
    }

    entry.timestamps.push(now);
    this.usernameCheckRateLimits.set(userId, entry);
  }

  // ── Generate Username Suggestions ────────────────────────────────

  async generateUsernameSuggestions(displayName: string, userId: string) {
    if (!displayName || displayName.trim().length < 1) {
      throw new BadRequestException('Display name is required to generate suggestions');
    }

    const name = displayName.trim().toLowerCase();
    const reserved = ['admin', 'root', 'system', 'moderator', 'support', 'help', 'api', 'null', 'undefined'];

    // Generate 5 candidate usernames from the display name
    const cleanName = name.replace(/[^a-z0-9_]/g, '');
    const parts = cleanName.split(/[\s_]+/).filter(Boolean);
    const firstName = parts[0] || '';
    const lastName = parts.length > 1 ? parts[parts.length - 1] : '';
    const randomSuffix = () => Math.floor(Math.random() * 100).toString().padStart(2, '0');

    const candidates: string[] = [];

    // Strategy 1: firstname
    if (firstName) candidates.push(firstName);

    // Strategy 2: firstname + lastname (if available)
    if (firstName && lastName) {
      candidates.push(`${firstName}${lastName}`);
      candidates.push(`${firstName}_${lastName}`);
    }

    // Strategy 3: firstname + random 2-digit suffix
    if (firstName) candidates.push(`${firstName}${randomSuffix()}`);

    // Strategy 4: first initial + lastname + suffix
    if (firstName && lastName) {
      candidates.push(`${firstName[0]}${lastName}${randomSuffix()}`);
    }

    // Fallback: ensure we have at least 5 candidates
    while (candidates.length < 5) {
      candidates.push(`${firstName || 'user'}${randomSuffix()}`);
    }

    // Deduplicate and limit to 5
    const uniqueCandidates = [...new Set(candidates)].slice(0, 5);

    // Check availability for each candidate
    const suggestions = await Promise.all(
      uniqueCandidates.map(async (candidate) => {
        // Validate format
        const usernameRegex = /^[a-z][a-z0-9_]{2,29}$/;
        const formatValid = usernameRegex.test(candidate);
        const isReserved = reserved.includes(candidate);

        if (!formatValid || isReserved) {
          return { username: candidate, available: false };
        }

        // Check in both User and Person tables
        const [existingUser, existingPerson] = await Promise.all([
          this.prisma.user.findUnique({ where: { username: candidate } }),
          this.prisma.person.findFirst({ where: { username: candidate, deletedAt: null } }),
        ]);

        return {
          username: candidate,
          available: !existingUser && !existingPerson,
        };
      }),
    );

    return { suggestions };
  }

  // ── Get Username Change History ──────────────────────────────────

  async getUsernameHistory(userId: string) {
    const history = await this.prisma.usernameChangeLog.findMany({
      where: { userId },
      orderBy: { changedAt: 'desc' },
      select: {
        id: true,
        oldUsername: true,
        newUsername: true,
        changedAt: true,
      },
    });

    return { history };
  }

  // ── Update Username ─────────────────────────────────────────────

  async updateUsername(userId: string, username: string) {
    if (!username || username.trim().length < 3) {
      throw new BadRequestException('Username must be at least 3 characters');
    }

    const trimmed = username.trim();

    // Validate username format: 3-30 chars, lowercase letters, numbers, underscores only
    const usernameRegex = /^[a-z][a-z0-9_]{2,29}$/;
    if (!usernameRegex.test(trimmed)) {
      throw new BadRequestException(
        'Username must be 3-30 characters, start with a letter, and contain only lowercase letters, numbers, and underscores',
      );
    }

    // Check availability
    const existingUser = await this.prisma.user.findUnique({
      where: { username: trimmed },
    });

    if (existingUser && existingUser.id !== userId) {
      throw new ConflictException('Username is already taken');
    }

    // Get current user to record old username
    const currentUser = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { username: true },
    });

    const oldUsername = currentUser?.username || null;

    // Update username and log the change in a transaction
    const user = await this.prisma.$transaction(async (tx) => {
      // Log the username change
      await tx.usernameChangeLog.create({
        data: {
          userId,
          oldUsername,
          newUsername: trimmed,
        },
      });

      // Update the user's username
      return tx.user.update({
        where: { id: userId },
        data: { username: trimmed },
        select: {
          id: true,
          email: true,
          name: true,
          username: true,
          avatarUrl: true,
          photoThumb: true,
        },
      });
    });

    // Invalidate cached availability for the new username
    this.usernameAvailabilityCache.delete(trimmed);
    if (oldUsername) {
      this.usernameAvailabilityCache.delete(oldUsername);
    }

    return { user };
  }

  // ── Get User's Families (with role info) ────────────────────────

  async getFamilies(userId: string) {
    const memberships = await this.prisma.familyMember.findMany({
      where: { userId },
      include: {
        family: {
          select: {
            id: true,
            name: true,
            username: true,
            avatarUrl: true,
            memberCount: true,
          },
        },
      },
      orderBy: { joinedAt: 'desc' },
    });

    const families = memberships.map((m) => ({
      id: m.family.id,
      name: m.family.name,
      username: m.family.username,
      role: m.role,
      memberCount: m.family.memberCount,
      avatarUrl: m.family.avatarUrl,
      joinedAt: m.joinedAt,
    }));

    return { families };
  }

  // ── Get User's Pending Invitations ──────────────────────────────

  async getInvitations(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { email: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Find invitations by recipientEmail matching the user's email
    const invitations = await this.prisma.invitation.findMany({
      where: {
        status: 'pending',
        recipientEmail: user.email,
        expiresAt: { gt: new Date() },
      },
      include: {
        family: {
          select: {
            id: true,
            name: true,
            avatarUrl: true,
          },
        },
        inviter: {
          select: {
            id: true,
            name: true,
            username: true,
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    const result = invitations.map((inv) => ({
      id: inv.id,
      familyName: inv.family.name,
      familyAvatar: inv.family.avatarUrl,
      inviterName: inv.inviter.name || 'Unknown',
      inviterUsername: inv.inviter.username,
      status: inv.status,
      role: inv.role,
      createdAt: inv.createdAt,
    }));

    return { invitations: result };
  }

  // ── Get Blocked Users ───────────────────────────────────────────

  async getBlockedUsers(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { blockedUserIds: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    let blockedIds: string[] = [];
    try {
      blockedIds = JSON.parse(user.blockedUserIds || '[]');
    } catch {
      blockedIds = [];
    }

    if (blockedIds.length === 0) {
      return { blocked: [] };
    }

    const blockedUsers = await this.prisma.user.findMany({
      where: { id: { in: blockedIds } },
      select: {
        id: true,
        name: true,
        username: true,
        avatarUrl: true,
        photoThumb: true,
      },
    });

    const blocked = blockedUsers.map((u) => ({
      id: u.id,
      name: u.name || 'Unknown',
      username: u.username,
      avatarUrl: u.photoThumb || u.avatarUrl,
      photoThumb: u.photoThumb,
    }));

    return { blocked };
  }

  // ── Unblock a User ──────────────────────────────────────────────

  async unblockUser(userId: string, blockedUserId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { blockedUserIds: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    let blockedIds: string[] = [];
    try {
      blockedIds = JSON.parse(user.blockedUserIds || '[]');
    } catch {
      blockedIds = [];
    }

    if (!blockedIds.includes(blockedUserId)) {
      throw new NotFoundException('User is not in your blocked list');
    }

    const updatedIds = blockedIds.filter((id) => id !== blockedUserId);

    await this.prisma.user.update({
      where: { id: userId },
      data: { blockedUserIds: JSON.stringify(updatedIds) },
    });

    return { success: true, message: 'User unblocked' };
  }

  // ── Block a User ────────────────────────────────────────────────

  async blockUser(userId: string, targetUserId: string) {
    if (userId === targetUserId) {
      throw new BadRequestException('Cannot block yourself');
    }

    const targetUser = await this.prisma.user.findUnique({
      where: { id: targetUserId },
    });

    if (!targetUser) {
      throw new NotFoundException('Target user not found');
    }

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { blockedUserIds: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    let blockedIds: string[] = [];
    try {
      blockedIds = JSON.parse(user.blockedUserIds || '[]');
    } catch {
      blockedIds = [];
    }

    if (blockedIds.includes(targetUserId)) {
      return { success: true, message: 'User already blocked' };
    }

    blockedIds.push(targetUserId);

    await this.prisma.user.update({
      where: { id: userId },
      data: { blockedUserIds: JSON.stringify(blockedIds) },
    });

    return { success: true, message: 'User blocked' };
  }

  // ── Request Data Export ─────────────────────────────────────────

  async requestDataExport(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        name: true,
        phone: true,
        avatarUrl: true,
        photoThumb: true,
        photoCard: true,
        photoFull: true,
        bio: true,
        dateOfBirth: true,
        gender: true,
        username: true,
        preferredLanguage: true,
        profileVisibility: true,
        invitePermission: true,
        twoFactorEnabled: true,
        authProvider: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Collect family memberships
    const families = await this.prisma.familyMember.findMany({
      where: { userId },
      include: {
        family: {
          select: { id: true, name: true, username: true },
        },
      },
    });

    // Collect notifications
    const recentNotifications = await this.prisma.notification.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: 50,
      select: {
        id: true,
        eventType: true,
        title: true,
        body: true,
        read: true,
        createdAt: true,
      },
    });

    // Collect support tickets
    const tickets = await this.prisma.supportTicket.findMany({
      where: { userId },
      select: {
        id: true,
        ticketNumber: true,
        subject: true,
        status: true,
        createdAt: true,
      },
    });

    // In a real implementation, this would generate a file and send a download link
    // For now, we return the data directly and simulate a job ID
    const exportId = `export_${userId}_${Date.now()}`;

    return {
      exportId,
      status: 'completed',
      message: 'Data export completed',
      data: {
        profile: user,
        families: families.map((f) => ({
          id: f.family.id,
          name: f.family.name,
          role: f.role,
          joinedAt: f.joinedAt,
        })),
        recentNotifications,
        supportTickets: tickets,
      },
      exportedAt: new Date().toISOString(),
    };
  }

  // ── Set Quiet Hours ─────────────────────────────────────────────

  async setQuietHours(
    userId: string,
    data: { start?: string; end?: string; enabled?: boolean },
  ) {
    // Find or create notification preference for quiet hours
    // We use a special eventType 'quiet_hours' for this
    const existing = await this.prisma.notificationPreference.findUnique({
      where: { userId_eventType: { userId, eventType: 'quiet_hours' } },
    });

    if (existing) {
      const updateData: Record<string, unknown> = {};
      if (data.start !== undefined) updateData.quietHoursStart = data.start;
      if (data.end !== undefined) updateData.quietHoursEnd = data.end;
      // If enabled is explicitly false, clear the quiet hours
      if (data.enabled === false) {
        updateData.quietHoursStart = null;
        updateData.quietHoursEnd = null;
      }

      const updated = await this.prisma.notificationPreference.update({
        where: { id: existing.id },
        data: updateData,
      });

      return {
        start: updated.quietHoursStart,
        end: updated.quietHoursEnd,
        enabled: !!(updated.quietHoursStart && updated.quietHoursEnd),
      };
    } else {
      // Create new preference
      const created = await this.prisma.notificationPreference.create({
        data: {
          userId,
          eventType: 'quiet_hours',
          quietHoursStart: data.enabled !== false ? (data.start || null) : null,
          quietHoursEnd: data.enabled !== false ? (data.end || null) : null,
        },
      });

      return {
        start: created.quietHoursStart,
        end: created.quietHoursEnd,
        enabled: !!(created.quietHoursStart && created.quietHoursEnd),
      };
    }
  }

  // ── Get Quiet Hours ─────────────────────────────────────────────

  async getQuietHours(userId: string) {
    const pref = await this.prisma.notificationPreference.findUnique({
      where: { userId_eventType: { userId, eventType: 'quiet_hours' } },
    });

    if (!pref) {
      return { start: null, end: null, enabled: false };
    }

    return {
      start: pref.quietHoursStart,
      end: pref.quietHoursEnd,
      enabled: !!(pref.quietHoursStart && pref.quietHoursEnd),
    };
  }

  // ── Register / Update FCM Token ────────────────────────────────

  async registerFcmToken(
    userId: string,
    data: { fcmToken: string; deviceType?: string },
  ) {
    if (!data.fcmToken || data.fcmToken.trim().length === 0) {
      throw new BadRequestException('FCM token is required');
    }

    // Upsert: create or update the FCM token
    const existing = await this.prisma.fcmToken.findUnique({
      where: { token: data.fcmToken },
    });

    if (existing) {
      // Update the existing token's userId and lastUsedAt
      await this.prisma.fcmToken.update({
        where: { token: data.fcmToken },
        data: {
          userId,
          deviceType: data.deviceType || existing.deviceType,
          lastUsedAt: new Date(),
        },
      });
    } else {
      // Create a new FCM token record
      await this.prisma.fcmToken.create({
        data: {
          token: data.fcmToken,
          userId,
          deviceType: data.deviceType || 'unknown',
        },
      });
    }

    return { success: true, message: 'FCM token registered' };
  }

  // ── Delete FCM Token ───────────────────────────────────────────

  async deleteFcmToken(userId: string, fcmToken: string) {
    if (!fcmToken) {
      throw new BadRequestException('FCM token is required');
    }

    const existing = await this.prisma.fcmToken.findUnique({
      where: { token: fcmToken },
    });

    if (!existing) {
      return { success: true, message: 'FCM token not found (already removed)' };
    }

    // Only allow deleting own tokens
    if (existing.userId !== userId) {
      throw new UnauthorizedException('Cannot delete another user\'s FCM token');
    }

    await this.prisma.fcmToken.delete({
      where: { token: fcmToken },
    });

    return { success: true, message: 'FCM token deleted' };
  }
}
