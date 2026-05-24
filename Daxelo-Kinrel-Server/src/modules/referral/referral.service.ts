import { Injectable, Logger, NotFoundException, BadRequestException } from '@nestjs/common';

// ── Types ──────────────────────────────────────────────────────────────

interface ReferralRecord {
  code: string;
  userId: string;
  createdAt: Date;
  uses: number;
}

interface ReferralApplication {
  code: string;
  referrerId: string;
  newUserId: string;
  appliedAt: Date;
  reward: string;
}

interface RewardTier {
  referrals: number;
  reward: string;
  badge?: string;
  description: string;
}

// ── Reward Tiers ──────────────────────────────────────────────────────

const REWARD_TIERS: RewardTier[] = [
  {
    referrals: 5,
    reward: 'Premium 1 month free',
    description: 'Unlock Premium features for 1 month',
  },
  {
    referrals: 10,
    reward: 'Premium 3 months free',
    description: 'Unlock Premium features for 3 months',
  },
  {
    referrals: 25,
    reward: 'Premium 1 year free',
    badge: 'Family Champion',
    description: '1 year of Premium + exclusive "Family Champion" badge',
  },
  {
    referrals: 50,
    reward: 'Lifetime Premium',
    badge: 'Kinrel Ambassador',
    description: 'Lifetime Premium access + exclusive "Kinrel Ambassador" badge',
  },
];

@Injectable()
export class ReferralService {
  private readonly logger = new Logger(ReferralService.name);

  /** In-memory storage: code → ReferralRecord */
  private readonly referralCodes = new Map<string, ReferralRecord>();

  /** In-memory storage: userId → code */
  private readonly userCodes = new Map<string, string>();

  /** In-memory storage: all referral applications */
  private readonly applications: ReferralApplication[] = [];

  /** Base URL for share links */
  private readonly baseUrl = 'https://kinrel.app';

  // ── Generate Referral Code ──────────────────────────────────────────

  generateReferralCode(userId: string) {
    // Check if user already has a code
    const existingCode = this.userCodes.get(userId);
    if (existingCode) {
      const record = this.referralCodes.get(existingCode);
      if (record) {
        return {
          code: record.code,
          shareUrl: `${this.baseUrl}/ref/${record.code}`,
          shareText: `Join me on KINREL! Discover your family relationships in 15 Indian languages. Use my code: ${record.code}`,
        };
      }
    }

    // Generate unique 8-char code: KINREL-XXXX
    const codeSuffix = this.hashUserId(userId);
    const code = `KINREL-${codeSuffix}`;

    // Ensure uniqueness (very unlikely collision, but handle it)
    if (this.referralCodes.has(code)) {
      const altSuffix = this.hashUserId(userId + Date.now().toString());
      const altCode = `KINREL-${altSuffix}`;
      this.storeCode(altCode, userId);
      return {
        code: altCode,
        shareUrl: `${this.baseUrl}/ref/${altCode}`,
        shareText: `Join me on KINREL! Discover your family relationships in 15 Indian languages. Use my code: ${altCode}`,
      };
    }

    this.storeCode(code, userId);

    return {
      code,
      shareUrl: `${this.baseUrl}/ref/${code}`,
      shareText: `Join me on KINREL! Discover your family relationships in 15 Indian languages. Use my code: ${code}`,
    };
  }

  // ── Apply Referral Code ─────────────────────────────────────────────

  applyReferralCode(code: string, newUserId: string) {
    const record = this.referralCodes.get(code);

    if (!record) {
      throw new NotFoundException(`Referral code '${code}' not found`);
    }

    // Can't refer yourself
    if (record.userId === newUserId) {
      throw new BadRequestException('You cannot use your own referral code');
    }

    // Check if this user already applied this code
    const alreadyApplied = this.applications.find(
      (a) => a.code === code && a.newUserId === newUserId,
    );
    if (alreadyApplied) {
      throw new BadRequestException('You have already used this referral code');
    }

    // Record the referral
    record.uses += 1;

    const reward = this.determineReward(record.uses);

    const application: ReferralApplication = {
      code,
      referrerId: record.userId,
      newUserId,
      appliedAt: new Date(),
      reward,
    };

    this.applications.push(application);

    return {
      success: true,
      referrerId: record.userId,
      reward,
    };
  }

  // ── Get Referral Stats ──────────────────────────────────────────────

  getReferralStats(userId: string) {
    const code = this.userCodes.get(userId) ?? null;
    const userApplications = this.applications.filter(
      (a) => a.referrerId === userId,
    );

    const totalReferrals = userApplications.length;

    // Determine earned rewards
    const rewards: string[] = [];
    for (const tier of REWARD_TIERS) {
      if (totalReferrals >= tier.referrals) {
        rewards.push(tier.reward);
      }
    }

    // Recent referrals (last 10)
    const recentReferrals = userApplications.slice(-10).reverse().map((a) => ({
      name: `User ${a.newUserId.substring(0, 8)}...`,
      date: a.appliedAt.toISOString(),
    }));

    return {
      code: code ?? 'No code generated yet',
      totalReferrals,
      rewards,
      recentReferrals,
    };
  }

  // ── Get Rewards ─────────────────────────────────────────────────────

  getRewards() {
    return {
      tiers: REWARD_TIERS.map((tier) => ({
        referrals: tier.referrals,
        reward: tier.reward,
        badge: tier.badge ?? null,
        description: tier.description,
      })),
    };
  }

  // ── Private Helpers ─────────────────────────────────────────────────

  private storeCode(code: string, userId: string) {
    const record: ReferralRecord = {
      code,
      userId,
      createdAt: new Date(),
      uses: 0,
    };

    this.referralCodes.set(code, record);
    this.userCodes.set(userId, code);
  }

  private hashUserId(userId: string): string {
    // Simple deterministic hash to generate 4-char alphanumeric code
    let hash = 0;
    for (let i = 0; i < userId.length; i++) {
      const char = userId.charCodeAt(i);
      hash = ((hash << 5) - hash + char) | 0;
    }

    // Convert to base-36 and take last 4 characters, uppercase
    const base36 = Math.abs(hash).toString(36).toUpperCase();
    return base36.substring(0, 4).padEnd(4, '0');
  }

  private determineReward(currentUses: number): string {
    let reward = 'Welcome bonus';

    for (const tier of REWARD_TIERS) {
      if (currentUses >= tier.referrals) {
        reward = tier.reward;
      }
    }

    return reward;
  }
}
