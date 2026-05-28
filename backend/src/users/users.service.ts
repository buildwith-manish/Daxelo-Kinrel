import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UsersService {
  constructor(private prisma: PrismaService) {}

  /**
   * Get current user profile
   */
  async getProfile(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        name: true,
        phone: true,
        preferredLanguage: true,
        role: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    return { user };
  }

  /**
   * Update current user profile
   */
  async updateProfile(userId: string, data: { name?: string; phone?: string; preferredLanguage?: string }) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new NotFoundException('User not found');
    }

    const updateData: Record<string, unknown> = {};
    if (data.name !== undefined) updateData.name = data.name.trim() || null;
    if (data.phone !== undefined) updateData.phone = data.phone.trim() || null;
    if (data.preferredLanguage !== undefined) updateData.preferredLanguage = data.preferredLanguage;

    const updated = await this.prisma.user.update({
      where: { id: userId },
      data: updateData,
      select: {
        id: true,
        email: true,
        name: true,
        phone: true,
        preferredLanguage: true,
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

  /**
   * Update user's FCM token for push notifications
   */
  async updateFcmToken(userId: string, fcmToken: string) {
    await this.prisma.user.update({
      where: { id: userId },
      data: { fcmToken },
    });

    return { success: true, message: 'FCM token updated' };
  }

  /**
   * Record app open event
   * Updates User.lastOpenedAt and resets dormantNotificationSent to false
   */
  async appOpen(userId: string): Promise<void> {
    await this.prisma.user.update({
      where: { id: userId },
      data: {
        lastOpenedAt: new Date(),
        dormantNotificationSent: false,
      },
    });
  }

  /**
   * Delete user account with cascade
   */
  async deleteAccount(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Delete in order respecting foreign key constraints
    // 1. Notification preferences
    await this.prisma.notificationPreference.deleteMany({ where: { userId } });

    // 2. Notifications
    await this.prisma.notification.deleteMany({ where: { userId } });

    // 3. WhatsApp consent
    await this.prisma.whatsAppConsent.deleteMany({ where: { userId } });

    // 4. Family memberships (cascade will handle family-level data if user is last admin)
    await this.prisma.familyMember.deleteMany({ where: { userId } });

    // 5. API keys
    await this.prisma.apiKey.deleteMany({ where: { userId } });

    // 6. Subscription
    await this.prisma.subscription.deleteMany({ where: { userId } });

    // 7. Support tickets
    await this.prisma.supportTicket.deleteMany({ where: { userId } });

    // 8. Invitations (as inviter)
    await this.prisma.invitation.deleteMany({ where: { inviterId: userId } });

    // 9. Finally, delete the user
    await this.prisma.user.delete({ where: { id: userId } });

    return {
      success: true,
      message: 'Account deleted',
    };
  }
}
