"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var ReferralService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.ReferralService = void 0;
const common_1 = require("@nestjs/common");
const REWARD_TIERS = [
    {
        name: 'Bronze',
        referralsRequired: 3,
        description: 'Bronze Referrer — You\'re getting started!',
        badge: '🥉',
        benefits: ['Custom profile badge', '1 free AI card generation per week'],
    },
    {
        name: 'Silver',
        referralsRequired: 10,
        description: 'Silver Referrer — Building your community!',
        badge: '🥈',
        benefits: [
            'Custom profile badge',
            '3 free AI card generations per week',
            'Priority quiz leaderboard display',
        ],
    },
    {
        name: 'Gold',
        referralsRequired: 25,
        description: 'Gold Referrer — A true kinship ambassador!',
        badge: '🥇',
        benefits: [
            'Custom profile badge',
            'Unlimited AI card generations',
            'Priority quiz leaderboard display',
            'Early access to new features',
        ],
    },
    {
        name: 'Platinum',
        referralsRequired: 50,
        description: 'Platinum Referrer — The ultimate kinship champion!',
        badge: '💎',
        benefits: [
            'Custom profile badge',
            'Unlimited AI card generations',
            'Priority quiz leaderboard display',
            'Early access to new features',
            'Dedicated support channel',
            'Family tree premium features',
        ],
    },
];
let ReferralService = ReferralService_1 = class ReferralService {
    constructor() {
        this.logger = new common_1.Logger(ReferralService_1.name);
        this.referrals = new Map();
        this.userReferrals = new Map();
    }
    generateCode(userId) {
        const existing = [...this.referrals.values()].find((r) => r.userId === userId && !r.referredBy);
        if (existing) {
            return { code: existing.code, createdAt: existing.createdAt };
        }
        const code = this.generateUniqueCode();
        const record = {
            code,
            userId,
            createdAt: new Date(),
        };
        this.referrals.set(code, record);
        const userCodes = this.userReferrals.get(userId) || [];
        userCodes.push(code);
        this.userReferrals.set(userId, userCodes);
        return { code, createdAt: record.createdAt };
    }
    getStats(userId) {
        const ownCode = [...this.referrals.values()].find((r) => r.userId === userId && !r.referredBy);
        const userCodes = this.userReferrals.get(userId) || [];
        const successfulReferrals = [];
        for (const code of userCodes) {
            const refs = [...this.referrals.values()].filter((r) => r.referredBy === code);
            successfulReferrals.push(...refs);
        }
        const totalReferrals = successfulReferrals.length;
        let currentTier = 'None';
        let nextTier = null;
        let referralsToNextTier = 0;
        for (let i = REWARD_TIERS.length - 1; i >= 0; i--) {
            if (totalReferrals >= REWARD_TIERS[i].referralsRequired) {
                currentTier = REWARD_TIERS[i].name;
                if (i < REWARD_TIERS.length - 1) {
                    nextTier = REWARD_TIERS[i + 1].name;
                    referralsToNextTier = REWARD_TIERS[i + 1].referralsRequired - totalReferrals;
                }
                break;
            }
        }
        if (currentTier === 'None' && REWARD_TIERS.length > 0) {
            nextTier = REWARD_TIERS[0].name;
            referralsToNextTier = REWARD_TIERS[0].referralsRequired - totalReferrals;
        }
        const recentReferrals = successfulReferrals
            .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
            .slice(0, 10)
            .map((r) => ({ code: r.code, referredAt: r.createdAt }));
        return {
            totalReferrals,
            referralCode: ownCode?.code || null,
            currentTier,
            nextTier,
            referralsToNextTier,
            recentReferrals,
        };
    }
    applyCode(userId, code) {
        const referral = this.referrals.get(code);
        if (!referral) {
            throw new common_1.BadRequestException('Invalid referral code');
        }
        if (referral.userId === userId) {
            throw new common_1.BadRequestException('You cannot use your own referral code');
        }
        const existingReferral = [...this.referrals.values()].find((r) => r.userId === userId && r.referredBy);
        if (existingReferral) {
            throw new common_1.BadRequestException('You have already applied a referral code');
        }
        const newUserCode = this.generateUniqueCode();
        const record = {
            code: newUserCode,
            userId,
            referredBy: code,
            createdAt: new Date(),
        };
        this.referrals.set(newUserCode, record);
        const userCodes = this.userReferrals.get(userId) || [];
        userCodes.push(newUserCode);
        this.userReferrals.set(userId, userCodes);
        return {
            success: true,
            message: 'Referral code applied successfully! Welcome to Daxelo Kinrel!',
            referrer: referral.userId,
        };
    }
    getRewardTiers() {
        return REWARD_TIERS;
    }
    generateUniqueCode() {
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        let code = '';
        for (let i = 0; i < 8; i++) {
            code += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        if (this.referrals.has(code)) {
            return this.generateUniqueCode();
        }
        return code;
    }
};
exports.ReferralService = ReferralService;
exports.ReferralService = ReferralService = ReferralService_1 = __decorate([
    (0, common_1.Injectable)()
], ReferralService);
//# sourceMappingURL=referral.service.js.map