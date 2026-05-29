export interface RewardTier {
    name: string;
    referralsRequired: number;
    description: string;
    badge: string;
    benefits: string[];
}
export declare class ReferralService {
    private readonly logger;
    private readonly referrals;
    private readonly userReferrals;
    generateCode(userId: string): {
        code: string;
        createdAt: Date;
    };
    getStats(userId: string): {
        totalReferrals: number;
        referralCode: string | null;
        currentTier: string;
        nextTier: string | null;
        referralsToNextTier: number;
        recentReferrals: Array<{
            code: string;
            referredAt: Date;
        }>;
    };
    applyCode(userId: string, code: string): {
        success: boolean;
        message: string;
        referrer?: string;
    };
    getRewardTiers(): RewardTier[];
    private generateUniqueCode;
}
