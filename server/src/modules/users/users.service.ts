import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ConflictException,
  UnauthorizedException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcryptjs';

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

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

  // ── Check Username Availability ─────────────────────────────────

  async checkUsername(username: string) {
    if (!username || username.trim().length < 3) {
      return { available: false, reason: 'Username must be at least 3 characters' };
    }

    const trimmed = username.trim().toLowerCase();

    // Check reserved words
    const reserved = ['admin', 'root', 'system', 'moderator', 'support', 'help', 'api', 'null', 'undefined'];
    if (reserved.includes(trimmed)) {
      return { available: false, reason: 'This username is reserved' };
    }

    // Check in User table
    const existingUser = await this.prisma.user.findUnique({
      where: { username: trimmed },
    });

    if (existingUser) {
      return { available: false, reason: 'Username is already taken' };
    }

    // Also check in Person table (as per task requirements)
    const existingPerson = await this.prisma.person.findFirst({
      where: { username: trimmed, deletedAt: null },
    });

    if (existingPerson) {
      return { available: false, reason: 'Username is already taken' };
    }

    return { available: true };
  }

  // ── Update Username ─────────────────────────────────────────────

  async updateUsername(userId: string, username: string) {
    if (!username || username.trim().length < 3) {
      throw new BadRequestException('Username must be at least 3 characters');
    }

    const trimmed = username.trim();

    // Check availability
    const existingUser = await this.prisma.user.findUnique({
      where: { username: trimmed },
    });

    if (existingUser && existingUser.id !== userId) {
      throw new ConflictException('Username is already taken');
    }

    const user = await this.prisma.user.update({
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
}
