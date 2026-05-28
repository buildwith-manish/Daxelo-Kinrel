import {
  Injectable,
  NotFoundException,
  UnauthorizedException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import * as CryptoJS from 'crypto-js';
import { UpdateProfileDto } from './dto/update-profile.dto';
import { ChangePasswordDto } from './dto/change-password.dto';
import { UpdateUsernameDto } from './dto/update-username.dto';
import { Verify2faDto, Disable2faDto } from './dto/two-factor.dto';
import { DeleteAccountDto } from './dto/delete-account.dto';
import { ExportFamilyDto } from './dto/export-family.dto';
import { CreateSupportTicketDto } from './dto/create-support-ticket.dto';
import { QuietHoursDto } from './dto/quiet-hours.dto';
import { randomBytes, randomUUID } from 'crypto';

@Injectable()
export class ProfileService {
  constructor(private prisma: PrismaService) {}

  // ── User Stats ──────────────────────────────────────────────────────

  async getUserStats(userId: string) {
    const familyMemberships = await this.prisma.familyMember.findMany({
      where: { userId },
      select: { familyId: true },
    });

    const familyIds = familyMemberships.map((fm) => fm.familyId);

    const membersAdded = await this.prisma.person.count({
      where: {
        familyId: { in: familyIds },
        deletedAt: null,
      },
    });

    const relations = await this.prisma.relationship.count({
      where: {
        familyId: { in: familyIds },
      },
    });

    return {
      familyTrees: familyIds.length,
      membersAdded,
      relations,
    };
  }

  // ── Avatar ──────────────────────────────────────────────────────────

  async updateAvatar(userId: string, imageUrl: string) {
    await this.prisma.user.update({
      where: { id: userId },
      data: { avatarUrl: imageUrl },
    });

    return { imageUrl };
  }

  // ── Profile Update ──────────────────────────────────────────────────

  async updateProfile(userId: string, dto: UpdateProfileDto) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new NotFoundException('User not found');
    }

    const updateData: Record<string, unknown> = {};
    if (dto.name !== undefined) updateData.name = dto.name.trim() || null;
    if (dto.phone !== undefined) updateData.phone = dto.phone.trim() || null;
    if (dto.bio !== undefined) updateData.bio = dto.bio.trim() || null;
    if (dto.dateOfBirth !== undefined) updateData.dateOfBirth = dto.dateOfBirth ? new Date(dto.dateOfBirth) : null;
    if (dto.gender !== undefined) updateData.gender = dto.gender;
    if (dto.preferredLanguage !== undefined) updateData.preferredLanguage = dto.preferredLanguage;
    if (dto.profileVisibility !== undefined) updateData.profileVisibility = dto.profileVisibility;
    if (dto.invitePermission !== undefined) updateData.invitePermission = dto.invitePermission;

    const updated = await this.prisma.user.update({
      where: { id: userId },
      data: updateData,
      select: {
        id: true,
        email: true,
        name: true,
        phone: true,
        bio: true,
        dateOfBirth: true,
        gender: true,
        username: true,
        avatarUrl: true,
        preferredLanguage: true,
        profileVisibility: true,
        invitePermission: true,
        authProvider: true,
        googleId: true,
        twoFactorEnabled: true,
        role: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'USER_PROFILE_UPDATED',
        resource: 'User',
        resourceId: userId,
        details: JSON.stringify({ updatedFields: Object.keys(updateData) }),
      },
    });

    return { user: updated };
  }

  // ── Change Password ─────────────────────────────────────────────────

  async changePassword(userId: string, dto: ChangePasswordDto) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, passwordHash: true, authProvider: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    if (user.authProvider !== 'email' && !user.passwordHash) {
      throw new BadRequestException('Password change not available for social accounts. Please set a password first.');
    }

    // Verify current password
    const currentHash = CryptoJS.SHA256(dto.currentPassword).toString();
    if (currentHash !== user.passwordHash) {
      throw new UnauthorizedException('Current password is incorrect');
    }

    // Hash and save new password
    const newHash = CryptoJS.SHA256(dto.newPassword).toString();
    await this.prisma.user.update({
      where: { id: userId },
      data: { passwordHash: newHash },
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'PASSWORD_CHANGED',
        resource: 'User',
        resourceId: userId,
        details: JSON.stringify({}),
      },
    });

    return { success: true, message: 'Password changed successfully' };
  }

  // ── Google Link / Unlink ────────────────────────────────────────────

  async linkGoogle(userId: string, googleToken: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new NotFoundException('User not found');
    }

    if (user.googleId) {
      throw new BadRequestException('Google account already linked');
    }

    // In production, verify the googleToken using google-auth-library
    // For now, use the token as a placeholder googleId
    const googleId = `google_${CryptoJS.SHA256(googleToken).toString().substring(0, 20)}`;

    // Check if this Google ID is already used by another account
    const existingGoogleUser = await this.prisma.user.findUnique({ where: { googleId } });
    if (existingGoogleUser) {
      throw new BadRequestException('This Google account is already linked to another user');
    }

    await this.prisma.user.update({
      where: { id: userId },
      data: {
        googleId,
        authProvider: user.authProvider === 'email' ? 'email' : 'google',
      },
    });

    return { success: true, message: 'Google account linked successfully' };
  }

  async unlinkGoogle(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, googleId: true, passwordHash: true, authProvider: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    if (!user.googleId) {
      throw new BadRequestException('No Google account linked');
    }

    // Ensure user has a password set before unlinking
    if (!user.passwordHash) {
      throw new BadRequestException('Please set a password before unlinking your Google account');
    }

    await this.prisma.user.update({
      where: { id: userId },
      data: {
        googleId: null,
        authProvider: 'email',
      },
    });

    return { success: true, message: 'Google account unlinked successfully' };
  }

  // ── 2FA Setup / Verify / Disable ───────────────────────────────────

  async setup2fa(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new NotFoundException('User not found');
    }

    if (user.twoFactorEnabled) {
      throw new BadRequestException('2FA is already enabled. Disable it first to re-setup.');
    }

    // Generate a random base32 secret (30 bytes → base32)
    const secretBytes = randomBytes(20);
    const secret = this.base32Encode(secretBytes);

    // Save the secret (not enabled yet)
    await this.prisma.user.update({
      where: { id: userId },
      data: { twoFactorSecret: secret },
    });

    // Build otpauth:// URL
    const appName = encodeURIComponent('Daxelo KinRel');
    const email = encodeURIComponent(user.email);
    const qrCodeUrl = `otpauth://totp/${appName}:${email}?secret=${secret}&issuer=${appName}&algorithm=SHA1&digits=6&period=30`;

    return { secret, qrCodeUrl };
  }

  async verify2fa(userId: string, dto: Verify2faDto) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, twoFactorSecret: true, twoFactorEnabled: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    if (!user.twoFactorSecret) {
      throw new BadRequestException('Please setup 2FA first before verifying');
    }

    if (user.twoFactorEnabled) {
      throw new BadRequestException('2FA is already enabled');
    }

    // Verify the TOTP code
    const isValid = this.verifyTotpCode(user.twoFactorSecret, dto.code);
    if (!isValid) {
      throw new BadRequestException('Invalid verification code');
    }

    // Generate backup codes
    const backupCodes = this.generateBackupCodes();

    // Enable 2FA
    await this.prisma.user.update({
      where: { id: userId },
      data: {
        twoFactorEnabled: true,
        twoFactorBackupCodes: JSON.stringify(backupCodes),
      },
    });

    return { enabled: true, backupCodes };
  }

  async disable2fa(userId: string, dto: Disable2faDto) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, passwordHash: true, twoFactorEnabled: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    if (!user.twoFactorEnabled) {
      throw new BadRequestException('2FA is not enabled');
    }

    // Verify password
    const hash = CryptoJS.SHA256(dto.password).toString();
    if (hash !== user.passwordHash) {
      throw new UnauthorizedException('Incorrect password');
    }

    await this.prisma.user.update({
      where: { id: userId },
      data: {
        twoFactorEnabled: false,
        twoFactorSecret: null,
        twoFactorBackupCodes: null,
      },
    });

    return { success: true, message: '2FA disabled successfully' };
  }

  // ── Sessions ────────────────────────────────────────────────────────

  async getSessions(userId: string) {
    const sessions = await this.prisma.activeSession.findMany({
      where: { userId },
      orderBy: { lastActiveAt: 'desc' },
      select: {
        id: true,
        deviceName: true,
        deviceType: true,
        ipAddress: true,
        location: true,
        lastActiveAt: true,
        createdAt: true,
      },
    });

    return { sessions };
  }

  async revokeSession(userId: string, sessionId: string) {
    const session = await this.prisma.activeSession.findUnique({
      where: { id: sessionId },
    });

    if (!session) {
      throw new NotFoundException('Session not found');
    }

    if (session.userId !== userId) {
      throw new ForbiddenException('You can only revoke your own sessions');
    }

    await this.prisma.activeSession.delete({
      where: { id: sessionId },
    });

    return { success: true, message: 'Session revoked' };
  }

  async revokeAllOtherSessions(userId: string, currentTokenHash: string) {
    const result = await this.prisma.activeSession.deleteMany({
      where: {
        userId,
        tokenHash: { not: currentTokenHash },
      },
    });

    return { success: true, revokedCount: result.count, message: 'All other sessions revoked' };
  }

  async createSession(
    userId: string,
    tokenHash: string,
    data?: { deviceName?: string; deviceType?: string; ipAddress?: string; location?: string },
  ) {
    return this.prisma.activeSession.create({
      data: {
        userId,
        tokenHash,
        deviceName: data?.deviceName ?? null,
        deviceType: data?.deviceType ?? 'mobile',
        ipAddress: data?.ipAddress ?? null,
        location: data?.location ?? null,
      },
    });
  }

  // ── Data Export ─────────────────────────────────────────────────────

  async requestDataExport(userId: string) {
    // Check if there's already a pending or processing request
    const existing = await this.prisma.dataExportRequest.findFirst({
      where: {
        userId,
        status: { in: ['pending', 'processing'] },
      },
    });

    if (existing) {
      throw new BadRequestException('You already have a pending data export request');
    }

    const exportRequest = await this.prisma.dataExportRequest.create({
      data: {
        userId,
        status: 'pending',
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000), // 7 days
      },
    });

    // In production, this would trigger a background job to process the export
    // For now, mark as processing and then completed with a placeholder
    setTimeout(async () => {
      try {
        await this.prisma.dataExportRequest.update({
          where: { id: exportRequest.id },
          data: {
            status: 'completed',
            downloadUrl: `/exports/user-${userId}-${Date.now()}.json`,
            completedAt: new Date(),
          },
        });
      } catch {
        // Ignore errors in the simulated background job
      }
    }, 2000);

    return {
      id: exportRequest.id,
      status: exportRequest.status,
      message: 'Data export requested. You will be notified when it is ready.',
    };
  }

  // ── Delete Account ──────────────────────────────────────────────────

  async deleteAccount(userId: string, dto: DeleteAccountDto) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, passwordHash: true, authProvider: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Verify password (only for email auth users with password)
    if (user.passwordHash) {
      const hash = CryptoJS.SHA256(dto.password).toString();
      if (hash !== user.passwordHash) {
        throw new UnauthorizedException('Incorrect password');
      }
    }

    if (dto.confirmation !== 'DELETE') {
      throw new BadRequestException('Confirmation must be "DELETE"');
    }

    // Delete in order respecting foreign key constraints
    // 1. Active sessions
    await this.prisma.activeSession.deleteMany({ where: { userId } });

    // 2. Blocked user records
    await this.prisma.blockedUser.deleteMany({ where: { blockerId: userId } });
    await this.prisma.blockedUser.deleteMany({ where: { blockedId: userId } });

    // 3. Data export requests
    await this.prisma.dataExportRequest.deleteMany({ where: { userId } });

    // 4. Family exports
    await this.prisma.familyExport.deleteMany({ where: { userId } });

    // 5. Notification preferences
    await this.prisma.notificationPreference.deleteMany({ where: { userId } });

    // 6. Notifications
    await this.prisma.notification.deleteMany({ where: { userId } });

    // 7. WhatsApp consent
    await this.prisma.whatsAppConsent.deleteMany({ where: { userId } });

    // 8. Family memberships
    await this.prisma.familyMember.deleteMany({ where: { userId } });

    // 9. API keys
    await this.prisma.apiKey.deleteMany({ where: { userId } });

    // 10. Subscription
    await this.prisma.subscription.deleteMany({ where: { userId } });

    // 11. Support tickets
    await this.prisma.supportTicket.deleteMany({ where: { userId } });

    // 12. Invitations (as inviter)
    await this.prisma.invitation.deleteMany({ where: { inviterId: userId } });

    // 13. Finally, delete the user
    await this.prisma.user.delete({ where: { id: userId } });

    return {
      success: true,
      message: 'Account deleted permanently',
    };
  }

  // ── User Families ───────────────────────────────────────────────────

  async getUserFamilies(userId: string) {
    const memberships = await this.prisma.familyMember.findMany({
      where: { userId },
      include: {
        family: {
          select: {
            id: true,
            name: true,
            description: true,
            primaryLanguage: true,
            gotra: true,
            originVillage: true,
            createdAt: true,
            members: {
              select: { id: true },
            },
          },
        },
      },
      orderBy: { joinedAt: 'desc' },
    });

    const families = memberships.map((m) => ({
      id: m.family.id,
      name: m.family.name,
      description: m.family.description,
      primaryLanguage: m.family.primaryLanguage,
      gotra: m.family.gotra,
      originVillage: m.family.originVillage,
      role: m.role,
      memberCount: m.family.members.length,
      joinedAt: m.joinedAt,
      createdAt: m.family.createdAt,
    }));

    return { families };
  }

  // ── Invitations ─────────────────────────────────────────────────────

  async getUserInvitations(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { email: true, phone: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Find pending invitations matching user's email or phone
    const invitations = await this.prisma.invitation.findMany({
      where: {
        status: 'pending',
        OR: [
          { recipientEmail: user.email },
          ...(user.phone ? [{ recipientPhone: user.phone }] : []),
        ],
      },
      include: {
        inviter: {
          select: { id: true, name: true, email: true },
        },
        family: {
          select: { id: true, name: true, primaryLanguage: true },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    return { invitations };
  }

  async acceptInvitation(userId: string, invitationId: string) {
    const invitation = await this.prisma.invitation.findUnique({
      where: { id: invitationId },
    });

    if (!invitation) {
      throw new NotFoundException('Invitation not found');
    }

    if (invitation.status !== 'pending') {
      throw new BadRequestException(`Invitation is already ${invitation.status}`);
    }

    // Check if expired
    if (invitation.expiresAt && new Date() > invitation.expiresAt) {
      await this.prisma.invitation.update({
        where: { id: invitationId },
        data: { status: 'expired' },
      });
      throw new BadRequestException('Invitation has expired');
    }

    // Update invitation
    await this.prisma.invitation.update({
      where: { id: invitationId },
      data: {
        status: 'accepted',
        acceptedAt: new Date(),
      },
    });

    // Add user to family
    const existingMembership = await this.prisma.familyMember.findUnique({
      where: {
        familyId_userId: { familyId: invitation.familyId, userId },
      },
    });

    if (!existingMembership) {
      await this.prisma.familyMember.create({
        data: {
          familyId: invitation.familyId,
          userId,
          role: invitation.role,
        },
      });
    }

    return { success: true, message: 'Invitation accepted', familyId: invitation.familyId };
  }

  async declineInvitation(userId: string, invitationId: string) {
    const invitation = await this.prisma.invitation.findUnique({
      where: { id: invitationId },
    });

    if (!invitation) {
      throw new NotFoundException('Invitation not found');
    }

    if (invitation.status !== 'pending') {
      throw new BadRequestException(`Invitation is already ${invitation.status}`);
    }

    await this.prisma.invitation.update({
      where: { id: invitationId },
      data: { status: 'cancelled' },
    });

    return { success: true, message: 'Invitation declined' };
  }

  // ── Blocked Users ───────────────────────────────────────────────────

  async getBlockedUsers(userId: string) {
    const blocked = await this.prisma.blockedUser.findMany({
      where: { blockerId: userId },
      include: {
        blocked: {
          select: { id: true, name: true, email: true, avatarUrl: true, username: true },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    return {
      blockedUsers: blocked.map((b) => ({
        id: b.blocked.id,
        name: b.blocked.name,
        email: b.blocked.email,
        avatarUrl: b.blocked.avatarUrl,
        username: b.blocked.username,
        blockedAt: b.createdAt,
      })),
    };
  }

  async unblockUser(userId: string, targetUserId: string) {
    const block = await this.prisma.blockedUser.findUnique({
      where: {
        blockerId_blockedId: { blockerId: userId, blockedId: targetUserId },
      },
    });

    if (!block) {
      throw new NotFoundException('Block record not found');
    }

    await this.prisma.blockedUser.delete({
      where: { id: block.id },
    });

    return { success: true, message: 'User unblocked' };
  }

  // ── Family Export ───────────────────────────────────────────────────

  async exportFamily(userId: string, familyId: string, dto: ExportFamilyDto) {
    // Verify user is a member of the family
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });

    if (!membership) {
      throw new ForbiddenException('You are not a member of this family');
    }

    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      include: {
        members: {
          select: { userId: true, role: true },
        },
        persons: {
          where: { deletedAt: null },
          include: {
            relationshipsFrom: {
              select: { toPersonId: true, type: true, direction: true },
            },
            relationshipsTo: {
              select: { fromPersonId: true, type: true, direction: true },
            },
          },
        },
      },
    });

    if (!family) {
      throw new NotFoundException('Family not found');
    }

    const exportRecord = await this.prisma.familyExport.create({
      data: {
        familyId,
        userId,
        format: dto.format,
        status: 'processing',
      },
    });

    // Generate export data
    let fileUrl: string;
    const exportData = {
      family: {
        id: family.id,
        name: family.name,
        description: family.description,
        primaryLanguage: family.primaryLanguage,
        gotra: family.gotra,
        originVillage: family.originVillage,
      },
      persons: family.persons.map((p) => ({
        id: p.id,
        name: p.name,
        relationship: p.relationship,
        dateOfBirth: p.dateOfBirth,
        occupation: p.occupation,
        city: p.city,
        isDeceased: p.isDeceased,
        relationships: [
          ...p.relationshipsFrom.map((r) => ({
            with: r.toPersonId,
            type: r.type,
            direction: r.direction,
          })),
          ...p.relationshipsTo.map((r) => ({
            with: r.fromPersonId,
            type: r.type,
            direction: r.direction,
          })),
        ],
      })),
      exportedAt: new Date().toISOString(),
    };

    if (dto.format === 'json') {
      fileUrl = `/exports/family-${familyId}-${Date.now()}.json`;
      // In production, write the JSON file to storage
    } else if (dto.format === 'csv') {
      fileUrl = `/exports/family-${familyId}-${Date.now()}.csv`;
    } else {
      fileUrl = `/exports/family-${familyId}-${Date.now()}.pdf`;
    }

    // Mark as completed
    await this.prisma.familyExport.update({
      where: { id: exportRecord.id },
      data: { status: 'completed', fileUrl },
    });

    return {
      id: exportRecord.id,
      format: dto.format,
      status: 'completed',
      fileUrl,
      data: dto.format === 'json' ? exportData : undefined,
    };
  }

  // ── Support Ticket ──────────────────────────────────────────────────

  async createSupportTicket(userId: string, dto: CreateSupportTicketDto) {
    // Generate ticket number
    const ticketCount = await this.prisma.supportTicket.count();
    const ticketNumber = `DK-${new Date().getFullYear()}-${String(ticketCount + 1).padStart(5, '0')}`;

    const ticket = await this.prisma.supportTicket.create({
      data: {
        ticketNumber,
        userId,
        category: 'general',
        severity: 'medium',
        subject: dto.subject,
        description: dto.message,
        attachments: JSON.stringify(dto.screenshotUrl ? [dto.screenshotUrl] : []),
        deviceInfo: dto.deviceInfo ?? null,
      },
    });

    return {
      id: ticket.id,
      ticketNumber: ticket.ticketNumber,
      status: ticket.status,
      message: 'Support ticket created successfully',
    };
  }

  // ── Logout ──────────────────────────────────────────────────────────

  async logout(userId: string, tokenHash?: string) {
    // Delete the specific session if token hash is provided
    if (tokenHash) {
      await this.prisma.activeSession.deleteMany({
        where: { userId, tokenHash },
      });
    }

    return { success: true, message: 'Logged out successfully' };
  }

  // ── Quiet Hours ─────────────────────────────────────────────────────

  async updateQuietHours(userId: string, dto: QuietHoursDto) {
    // Update all notification preferences for this user
    const prefs = await this.prisma.notificationPreference.findMany({
      where: { userId },
    });

    if (prefs.length === 0) {
      // Create a default preference entry
      await this.prisma.notificationPreference.create({
        data: {
          userId,
          eventType: 'general',
          quietHoursStart: dto.enabled ? dto.start : null,
          quietHoursEnd: dto.enabled ? dto.end : null,
        },
      });
    } else {
      // Update existing preferences
      await this.prisma.notificationPreference.updateMany({
        where: { userId },
        data: {
          quietHoursStart: dto.enabled ? dto.start : null,
          quietHoursEnd: dto.enabled ? dto.end : null,
        },
      });
    }

    return {
      start: dto.start,
      end: dto.end,
      enabled: dto.enabled,
    };
  }

  // ── Check Username ──────────────────────────────────────────────────

  async checkUsername(username: string) {
    const existing = await this.prisma.user.findUnique({
      where: { username },
      select: { id: true },
    });

    return { available: !existing };
  }

  // ── Update Username ─────────────────────────────────────────────────

  async updateUsername(userId: string, dto: UpdateUsernameDto) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Check if username is taken
    const existing = await this.prisma.user.findUnique({
      where: { username: dto.username },
    });

    if (existing && existing.id !== userId) {
      throw new BadRequestException('Username is already taken');
    }

    await this.prisma.user.update({
      where: { id: userId },
      data: { username: dto.username },
    });

    // Audit log
    await this.prisma.auditLog.create({
      data: {
        userId,
        action: 'USERNAME_UPDATED',
        resource: 'User',
        resourceId: userId,
        details: JSON.stringify({ username: dto.username }),
      },
    });

    return { username: dto.username };
  }

  // ── Helper: Base32 Encode ──────────────────────────────────────────

  private base32Encode(buffer: Buffer): string {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    let bits = '';
    let result = '';

    for (const byte of buffer) {
      bits += byte.toString(2).padStart(8, '0');
    }

    for (let i = 0; i < bits.length; i += 5) {
      const chunk = bits.substring(i, i + 5).padEnd(5, '0');
      result += alphabet[parseInt(chunk, 2)];
    }

    return result;
  }

  // ── Helper: Generate TOTP code (for verification) ──────────────────

  private verifyTotpCode(secret: string, code: string): boolean {
    // Simple TOTP verification
    // In production, use a proper TOTP library like 'otpauth'
    const timeStep = Math.floor(Date.now() / 1000 / 30);

    // Check current and adjacent time windows (±1 to account for clock drift)
    for (let offset = -1; offset <= 1; offset++) {
      const step = timeStep + offset;
      const generatedCode = this.generateTotpCode(secret, step);
      if (generatedCode === code) {
        return true;
      }
    }

    return false;
  }

  private generateTotpCode(secret: string, timeStep: number): string {
    // Decode base32 secret
    const decoded = this.base32Decode(secret);

    // Convert time step to 8-byte buffer
    const timeBuffer = Buffer.alloc(8);
    timeBuffer.writeUInt32BE(Math.floor(timeStep / 0x100000000), 0);
    timeBuffer.writeUInt32BE(timeStep & 0xffffffff, 4);

    // HMAC-SHA1
    const crypto = require('crypto');
    const hmac = crypto.createHmac('sha1', decoded);
    hmac.update(timeBuffer);
    const hmacResult = hmac.digest();

    // Dynamic truncation
    const offset = hmacResult[hmacResult.length - 1] & 0x0f;
    const binary =
      ((hmacResult[offset] & 0x7f) << 24) |
      ((hmacResult[offset + 1] & 0xff) << 16) |
      ((hmacResult[offset + 2] & 0xff) << 8) |
      (hmacResult[offset + 3] & 0xff);

    const otp = binary % 1000000;
    return otp.toString().padStart(6, '0');
  }

  private base32Decode(encoded: string): Buffer {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    let bits = '';

    for (const char of encoded.toUpperCase()) {
      const val = alphabet.indexOf(char);
      if (val === -1) continue;
      bits += val.toString(2).padStart(5, '0');
    }

    const bytes: number[] = [];
    for (let i = 0; i + 8 <= bits.length; i += 8) {
      bytes.push(parseInt(bits.substring(i, i + 8), 2));
    }

    return Buffer.from(bytes);
  }

  // ── Helper: Generate Backup Codes ──────────────────────────────────

  private generateBackupCodes(): string[] {
    const codes: string[] = [];
    for (let i = 0; i < 10; i++) {
      const code = randomBytes(4).toString('hex').toUpperCase();
      codes.push(`${code.substring(0, 4)}-${code.substring(4)}`);
    }
    return codes;
  }
}
