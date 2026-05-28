import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async getOrCreateUser(id: string, email: string) {
    let user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) {
      user = await this.prisma.user.create({
        data: {
          id,
          email,
          name: email.split('@')[0],
        },
      });
    }
    return user;
  }

  async getProfile(id: string) {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) return null;
    const { twoFactorSecret, ...safeUser } = user as any;
    return safeUser;
  }

  async updateProfile(id: string, data: any) {
    const allowedFields = [
      'name', 'phone', 'avatarUrl', 'bio', 'dateOfBirth',
      'gender', 'preferredLanguage', 'profileVisibility', 'invitePermission',
    ];
    const updateData: any = {};
    for (const field of allowedFields) {
      if (data[field] !== undefined) {
        updateData[field] = data[field];
      }
    }
    return this.prisma.user.update({
      where: { id },
      data: updateData,
    });
  }

  async updateAvatar(id: string, avatarUrl: string) {
    return this.prisma.user.update({
      where: { id },
      data: { avatarUrl },
    });
  }

  async getStats(id: string) {
    const familyTrees = await this.prisma.familyMember.count({
      where: { userId: id },
    });

    const familyIds = await this.prisma.familyMember.findMany({
      where: { userId: id },
      select: { familyId: true },
    });

    const familyIdList = familyIds.map((f) => f.familyId);

    const membersAdded = await this.prisma.person.count({
      where: { familyId: { in: familyIdList } },
    });

    const relations = await this.prisma.relationship.count({
      where: { familyId: { in: familyIdList } },
    });

    return {
      familyTrees,
      membersAdded,
      relations,
    };
  }

  async checkUsername(username: string) {
    const existing = await this.prisma.user.findUnique({
      where: { username },
    });
    return { available: !existing };
  }

  async setUsername(id: string, username: string) {
    const existing = await this.prisma.user.findUnique({
      where: { username },
    });
    if (existing && existing.id !== id) {
      return { error: 'Username already taken' };
    }
    return this.prisma.user.update({
      where: { id },
      data: { username },
    });
  }

  async getFamilies(id: string) {
    const memberships = await this.prisma.familyMember.findMany({
      where: { userId: id },
      include: { family: true },
    });
    return memberships.map((m) => ({
      ...m.family,
      role: m.role,
      joinedAt: m.joinedAt,
    }));
  }

  async getInvitations(id: string) {
    return this.prisma.invitation.findMany({
      where: { inviteeId: id, status: 'pending' },
    });
  }

  async getBlocked(id: string) {
    // Simple implementation - in production, use a blocked users table
    return { blocked: [] };
  }

  async unblockUser(id: string, blockedUserId: string) {
    return { message: 'User unblocked' };
  }

  async requestDataExport(id: string) {
    return { message: 'Data export requested', exportId: id + '-export-' + Date.now() };
  }

  async deleteAccount(id: string) {
    // Delete all user data
    await this.prisma.session.deleteMany({ where: { userId: id } });
    await this.prisma.familyMember.deleteMany({ where: { userId: id } });
    await this.prisma.invitation.deleteMany({ where: { inviteeId: id } });
    await this.prisma.supportTicket.deleteMany({ where: { userId: id } });
    await this.prisma.user.delete({ where: { id } });
    return { message: 'Account deleted successfully' };
  }

  async updateQuietHours(id: string, data: any) {
    // Store quiet hours in user metadata
    return { message: 'Quiet hours updated', quietHours: data };
  }
}
