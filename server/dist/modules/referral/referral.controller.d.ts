import { ReferralService } from './referral.service';
import { ApplyReferralDto } from './dto/referral.dto';
export declare class ReferralController {
    private readonly referralService;
    constructor(referralService: ReferralService);
    generateCode(userId: string): Promise<{
        code: string;
        createdAt: Date;
    }>;
    getStats(currentUserId: string, userId?: string): Promise<{
        totalReferrals: number;
        referralCode: string | null;
        currentTier: string;
        nextTier: string | null;
        referralsToNextTier: number;
        recentReferrals: Array<{
            code: string;
            referredAt: Date;
        }>;
    }>;
    applyCode(userId: string, dto: ApplyReferralDto): Promise<{
        success: boolean;
        message: string;
        referrer?: string;
    }>;
    getRewardTiers(): Promise<import("./referral.service").RewardTier[]>;
}
