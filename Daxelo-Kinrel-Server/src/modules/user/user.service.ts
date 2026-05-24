import {
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';
import { UpdateUserDto } from './dto/update-user.dto';

@Injectable()
export class UserService {
  private readonly logger = new Logger(UserService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ═══════════════════════════════════════════════════════════════════
  // Get Profile
  // ═══════════════════════════════════════════════════════════════════

  /**
   * GET /api/users/me
   * Get current user profile (JWT protected).
   * Response: { user: { id, email, name, phone, preferredLanguage, role, createdAt, updatedAt } }
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

  // ═══════════════════════════════════════════════════════════════════
  // Update Profile
  // ═══════════════════════════════════════════════════════════════════

  /**
   * PATCH /api/users/me
   * Update current user profile (JWT protected).
   * Body: { name?, phone?, preferredLanguage? }
   */
  async updateProfile(userId: string, dto: UpdateUserDto) {
    // Verify user exists first
    const existing = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true },
    });

    if (!existing) {
      throw new NotFoundException('User not found');
    }

    // Build update data — only include fields that were provided
    const updateData: Record<string, unknown> = {};
    if (dto.name !== undefined) updateData.name = dto.name;
    if (dto.phone !== undefined) updateData.phone = dto.phone;
    if (dto.preferredLanguage !== undefined)
      updateData.preferredLanguage = dto.preferredLanguage;

    if (Object.keys(updateData).length === 0) {
      throw new UnprocessableEntityException('No fields to update');
    }

    const user = await this.prisma.user.update({
      where: { id: userId },
      data: updateData,
      select: {
        id: true,
        email: true,
        name: true,
        phone: true,
        preferredLanguage: true,
        role: true,
      },
    });

    this.logger.log(`Profile updated for user: ${userId}`);

    return { user };
  }

  // ═══════════════════════════════════════════════════════════════════
  // Delete Account
  // ═══════════════════════════════════════════════════════════════════

  /**
   * DELETE /api/users/me
   * Delete current user account (JWT protected).
   * Hard-deletes the user and all associated data.
   */
  async deleteAccount(userId: string) {
    // Verify user exists
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, email: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Delete in a transaction for atomicity
    try {
      await this.prisma.$transaction(async (tx) => {
        // Delete in order of foreign key dependencies
        // Most relations have onDelete: Cascade, but we clean up
        // explicitly for safety and to handle relations without cascade deletes

        // 1. Notification preferences & notifications
        await tx.notificationPreference.deleteMany({
          where: { userId },
        });
        await tx.notification.deleteMany({ where: { userId } });

        // 2. WhatsApp consent
        await tx.whatsAppConsent.deleteMany({ where: { userId } });

        // 3. Family memberships (user leaves families)
        await tx.familyMember.deleteMany({ where: { userId } });

        // 4. API keys & OAuth clients
        await tx.apiKey.deleteMany({ where: { userId } });
        await tx.oAuthClient.deleteMany({ where: { userId } });

        // 5. Subscription
        await tx.subscription.deleteMany({ where: { userId } });

        // 6. Support tickets (reassign or delete)
        await tx.supportCSAT.deleteMany({
          where: { ticket: { userId } },
        });
        await tx.supportMessage.deleteMany({
          where: { ticket: { userId } },
        });
        await tx.supportEscalation.deleteMany({
          where: { ticket: { userId } },
        });
        await tx.sLATracking.deleteMany({
          where: { ticket: { userId } },
        });
        await tx.supportTicket.deleteMany({ where: { userId } });

        // 7. Invitations sent by this user
        await tx.invitation.deleteMany({
          where: { inviterId: userId },
        });

        // 8. Community memberships, posts, reactions, comments
        await tx.reaction.deleteMany({ where: { userId } });
        await tx.comment.deleteMany({ where: { authorId: userId } });
        await tx.communityPost.deleteMany({ where: { authorId: userId } });
        await tx.communityMember.deleteMany({ where: { userId } });

        // 9. Content reports & moderation
        await tx.contentReport.deleteMany({
          where: { reporterId: userId },
        });
        await tx.moderationAction.deleteMany({
          where: { moderatorId: userId },
        });

        // 10. Finally delete the user (remaining cascade relations auto-delete)
        await tx.user.delete({ where: { id: userId } });
      });

      this.logger.log(`Account deleted: ${userId} (${user.email})`);

      return { success: true, message: 'Account deleted' };
    } catch (error) {
      this.logger.error(`Failed to delete account ${userId}:`, error);
      throw error;
    }
  }
}
