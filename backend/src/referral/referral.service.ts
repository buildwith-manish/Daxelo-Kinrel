import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { nanoid } from 'nanoid';

@Injectable()
export class ReferralService {
  constructor(private prisma: PrismaService) {}

  /**
   * Get or generate the current user's referral code
   * Generates an 8-char alphanumeric code if not exists
   */
  async getMyCode(userId: string): Promise<{ code: string; shareUrl: string }> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { referralCode: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    // If user already has a referral code, return it
    if (user.referralCode) {
      return {
        code: user.referralCode,
        shareUrl: `https://kinrel.app/invite?ref=${user.referralCode}`,
      };
    }

    // Generate a unique 8-char alphanumeric code
    let code: string;
    let attempts = 0;
    while (attempts < 10) {
      code = nanoid(8);
      // Check for uniqueness
      const existing = await this.prisma.user.findUnique({
        where: { referralCode: code },
      });
      if (!existing) break;
      attempts++;
    }

    // Also ensure no Referral record has this code
    // Update the user with the new referral code
    await this.prisma.user.update({
      where: { id: userId },
      data: { referralCode: code! },
    });

    return {
      code: code!,
      shareUrl: `https://kinrel.app/invite?ref=${code!}`,
    };
  }

  /**
   * Apply a referral code during onboarding
   * Validates: code exists, not own code, not already used
   */
  async applyReferral(userId: string, code: string): Promise<{ success: boolean }> {
    // Find the referrer by their referral code
    const referrer = await this.prisma.user.findUnique({
      where: { referralCode: code },
      select: { id: true, referralCode: true },
    });

    if (!referrer) {
      throw new NotFoundException('Invalid referral code');
    }

    // Cannot refer yourself
    if (referrer.id === userId) {
      throw new BadRequestException('You cannot use your own referral code');
    }

    // Check if the user has already been referred
    const existingReferral = await this.prisma.referral.findFirst({
      where: { referredId: userId },
    });
    if (existingReferral) {
      throw new BadRequestException('You have already used a referral code');
    }

    // Create the referral relationship
    await this.prisma.referral.create({
      data: {
        referrerId: referrer.id,
        referredId: userId,
        code,
        status: 'accepted',
        acceptedAt: new Date(),
      },
    });

    return { success: true };
  }

  /**
   * Get referral stats for the current user
   * Returns: code, totalInvited, totalJoined, pending, joined
   */
  async getStats(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { referralCode: true },
    });

    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Get the referral code (generate if not exists)
    const { code } = await this.getMyCode(userId);

    // Get all referrals sent by this user
    const referrals = await this.prisma.referral.findMany({
      where: { referrerId: userId },
      select: {
        id: true,
        referredId: true,
        status: true,
        acceptedAt: true,
      },
    });

    // Get referred user details for those who have joined
    const joinedReferralIds = referrals.filter((r) => r.acceptedAt && r.referredId);
    const joinedUsers = await this.prisma.user.findMany({
      where: {
        id: { in: joinedReferralIds.map((r) => r.referredId!).filter(Boolean) },
      },
      select: {
        id: true,
        name: true,
      },
    });

    const joinedUserMap = new Map(joinedUsers.map((u) => [u.id, u]));

    const pending = referrals
      .filter((r) => !r.acceptedAt || r.status === 'pending')
      .map((r) => ({
        id: r.id,
        joinedAt: null as string | null,
      }));

    const joined = joinedReferralIds
      .map((r) => {
        const user = joinedUserMap.get(r.referredId!);
        return {
          id: r.referredId!,
          firstName: user?.name ?? 'User',
          joinedAt: r.acceptedAt!.toISOString(),
        };
      });

    return {
      code,
      totalInvited: referrals.length,
      totalJoined: joined.length,
      pending,
      joined,
    };
  }
}
