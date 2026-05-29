"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AuthService = void 0;
const common_1 = require("@nestjs/common");
const config_1 = require("@nestjs/config");
const jwt_1 = require("@nestjs/jwt");
const prisma_service_1 = require("../../prisma/prisma.service");
const bcrypt = __importStar(require("bcryptjs"));
const crypto = __importStar(require("crypto"));
const uuid_1 = require("uuid");
const speakeasy = __importStar(require("speakeasy"));
let AuthService = class AuthService {
    constructor(prisma, jwt, config) {
        this.prisma = prisma;
        this.jwt = jwt;
        this.config = config;
    }
    async register(dto) {
        const existing = await this.prisma.user.findUnique({
            where: { email: dto.email.trim().toLowerCase() },
        });
        if (existing) {
            throw new common_1.ConflictException('An account with this email already exists');
        }
        const passwordHash = await bcrypt.hash(dto.password, 12);
        const result = await this.prisma.$transaction(async (tx) => {
            const user = await tx.user.create({
                data: {
                    email: dto.email.trim().toLowerCase(),
                    name: dto.name.trim(),
                    passwordHash,
                    role: 'user',
                    preferredLanguage: 'en',
                },
                select: { id: true, email: true, name: true },
            });
            const family = await tx.family.create({
                data: {
                    name: 'My Family',
                    createdBy: user.id,
                    primaryLanguage: 'en',
                    privacyMode: 'private',
                    memberCount: 1,
                    lastActivityAt: new Date(),
                },
            });
            await tx.familyMember.create({
                data: {
                    familyId: family.id,
                    userId: user.id,
                    role: 'admin',
                },
            });
            return { user, familyId: family.id };
        });
        return result;
    }
    async login(dto, userAgent, ipAddress) {
        const user = await this.prisma.user.findUnique({
            where: { email: dto.email.trim().toLowerCase() },
        });
        if (!user || !user.passwordHash) {
            throw new common_1.UnauthorizedException('Invalid email or password');
        }
        let passwordValid = await bcrypt.compare(dto.password, user.passwordHash);
        if (!passwordValid && user.passwordHash.startsWith('sha256:')) {
            const legacyHash = user.passwordHash.replace('sha256:', '');
            const inputHash = this.hashSha256(dto.password);
            if (inputHash === legacyHash) {
                passwordValid = true;
                const newHash = await bcrypt.hash(dto.password, 12);
                await this.prisma.user.update({
                    where: { id: user.id },
                    data: { passwordHash: newHash },
                });
            }
        }
        if (!passwordValid) {
            throw new common_1.UnauthorizedException('Invalid email or password');
        }
        const tokens = await this.generateTokenPair(user.id, user.email, user.role, undefined, userAgent, ipAddress);
        return {
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            user: {
                id: user.id,
                email: user.email,
                name: user.name,
                role: user.role,
                preferredLanguage: user.preferredLanguage,
            },
        };
    }
    async refresh(oldRefreshToken) {
        const stored = await this.prisma.refreshToken.findUnique({
            where: { token: oldRefreshToken },
            include: { user: true },
        });
        if (!stored) {
            throw new common_1.UnauthorizedException('Invalid refresh token');
        }
        if (stored.expiresAt < new Date()) {
            await this.prisma.refreshToken.delete({
                where: { token: oldRefreshToken },
            });
            throw new common_1.UnauthorizedException('Refresh token has expired');
        }
        if (stored.revokedAt) {
            await this.revokeTokenFamily(stored.familyId);
            throw new common_1.UnauthorizedException('Refresh token reuse detected. All sessions have been revoked.');
        }
        await this.prisma.refreshToken.update({
            where: { token: oldRefreshToken },
            data: { revokedAt: new Date() },
        });
        const newTokens = await this.generateTokenPair(stored.user.id, stored.user.email, stored.user.role, stored.familyId);
        return newTokens;
    }
    async logout(refreshToken) {
        if (refreshToken) {
            const stored = await this.prisma.refreshToken.findUnique({
                where: { token: refreshToken },
            });
            if (stored && !stored.revokedAt) {
                await this.prisma.refreshToken.update({
                    where: { token: refreshToken },
                    data: { revokedAt: new Date() },
                });
            }
        }
        return { success: true };
    }
    async changePassword(userId, dto) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
        });
        if (!user || !user.passwordHash) {
            throw new common_1.NotFoundException('User not found');
        }
        const passwordValid = await bcrypt.compare(dto.currentPassword, user.passwordHash);
        if (!passwordValid) {
            throw new common_1.UnauthorizedException('Current password is incorrect');
        }
        const newHash = await bcrypt.hash(dto.newPassword, 12);
        await this.prisma.$transaction(async (tx) => {
            await tx.user.update({
                where: { id: userId },
                data: { passwordHash: newHash },
            });
            await tx.refreshToken.updateMany({
                where: { userId, revokedAt: null },
                data: { revokedAt: new Date() },
            });
        });
        return { message: 'Password changed successfully' };
    }
    async me(userId) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: {
                id: true,
                email: true,
                name: true,
                phone: true,
                preferredLanguage: true,
                role: true,
                avatarUrl: true,
                twoFactorEnabled: true,
            },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        return { user };
    }
    async setup2FA(userId) {
        const secret = speakeasy.generateSecret({
            name: `Daxelo Kinrel`,
            length: 32,
        });
        await this.prisma.user.update({
            where: { id: userId },
            data: { twoFactorSecret: secret.base32 },
        });
        return {
            secret: secret.base32,
            qrCodeUrl: secret.otpauth_url,
        };
    }
    async verify2FA(userId, code) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
        });
        if (!user || !user.twoFactorSecret) {
            throw new common_1.BadRequestException('2FA setup not initiated. Call setup first.');
        }
        const verified = speakeasy.totp.verify({
            secret: user.twoFactorSecret,
            encoding: 'base32',
            token: code,
            window: 2,
        });
        if (!verified) {
            throw new common_1.UnauthorizedException('Invalid 2FA code');
        }
        await this.prisma.user.update({
            where: { id: userId },
            data: { twoFactorEnabled: true },
        });
        return { verified: true };
    }
    async disable2FA(userId, password) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        const passwordValid = user.passwordHash
            ? await bcrypt.compare(password, user.passwordHash)
            : false;
        if (!passwordValid) {
            throw new common_1.UnauthorizedException('Password is incorrect');
        }
        await this.prisma.user.update({
            where: { id: userId },
            data: {
                twoFactorEnabled: false,
                twoFactorSecret: null,
            },
        });
        return { disabled: true };
    }
    async validateUser(payload) {
        const user = await this.prisma.user.findUnique({
            where: { id: payload.sub },
            select: {
                id: true,
                email: true,
                name: true,
                username: true,
                role: true,
                avatarUrl: true,
                preferredLanguage: true,
                twoFactorEnabled: true,
            },
        });
        if (!user) {
            return null;
        }
        return user;
    }
    async generateTokenPair(userId, email, role, existingFamilyId, userAgent, ipAddress) {
        const accessToken = this.jwt.sign({ sub: userId, email, role, type: 'access' }, {
            secret: this.config.get('JWT_ACCESS_SECRET'),
            expiresIn: this.config.get('JWT_ACCESS_EXPIRATION', '15m'),
        });
        const refreshToken = (0, uuid_1.v4)();
        const familyId = existingFamilyId || (0, uuid_1.v4)();
        const refreshExpiration = this.config.get('JWT_REFRESH_EXPIRATION', '7d');
        const expiresAt = this.computeExpiryDate(refreshExpiration);
        await this.prisma.refreshToken.create({
            data: {
                token: refreshToken,
                userId,
                familyId,
                expiresAt,
                userAgent: userAgent || null,
                ipAddress: ipAddress || null,
            },
        });
        return { accessToken, refreshToken };
    }
    hashSha256(password) {
        return crypto.createHash('sha256').update(password).digest('hex');
    }
    computeExpiryDate(duration) {
        const now = new Date();
        const match = duration.match(/^(\d+)([smhd])$/);
        if (!match)
            return new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
        const value = parseInt(match[1], 10);
        const unit = match[2];
        const multipliers = {
            s: 1000,
            m: 60000,
            h: 3600000,
            d: 86400000,
        };
        return new Date(now.getTime() + value * (multipliers[unit] || 86400000));
    }
    async revokeTokenFamily(familyId) {
        await this.prisma.refreshToken.updateMany({
            where: { familyId, revokedAt: null },
            data: { revokedAt: new Date() },
        });
    }
    async getUserSessions(userId, currentRefreshToken) {
        const tokens = await this.prisma.refreshToken.findMany({
            where: {
                userId,
                revokedAt: null,
                expiresAt: { gt: new Date() },
            },
            orderBy: { createdAt: 'desc' },
        });
        let currentTokenFamily = null;
        if (currentRefreshToken) {
            const currentToken = await this.prisma.refreshToken.findUnique({
                where: { token: currentRefreshToken },
                select: { familyId: true },
            });
            currentTokenFamily = currentToken?.familyId || null;
        }
        return tokens.map((token) => {
            const ua = token.userAgent || '';
            const parsed = this.parseUserAgent(ua);
            return {
                id: token.id,
                deviceName: parsed.deviceName,
                deviceType: parsed.deviceType,
                location: token.ipAddress || null,
                lastActiveAt: token.createdAt,
                isCurrentDevice: token.familyId === currentTokenFamily,
            };
        });
    }
    async revokeSession(sessionId, userId) {
        const token = await this.prisma.refreshToken.findFirst({
            where: { id: sessionId, userId },
        });
        if (!token) {
            throw new common_1.NotFoundException('Session not found');
        }
        await this.prisma.refreshToken.update({
            where: { id: sessionId },
            data: { revokedAt: new Date() },
        });
        return { success: true, message: 'Session revoked' };
    }
    async revokeAllSessionsExceptCurrent(userId, currentRefreshToken) {
        let currentTokenFamily = null;
        if (currentRefreshToken) {
            const currentToken = await this.prisma.refreshToken.findUnique({
                where: { token: currentRefreshToken },
                select: { familyId: true },
            });
            currentTokenFamily = currentToken?.familyId || null;
        }
        const whereClause = {
            userId,
            revokedAt: null,
        };
        if (currentTokenFamily) {
            whereClause.familyId = { not: currentTokenFamily };
        }
        const result = await this.prisma.refreshToken.updateMany({
            where: whereClause,
            data: { revokedAt: new Date() },
        });
        return {
            success: true,
            message: `${result.count} session(s) revoked`,
            revokedCount: result.count,
        };
    }
    parseUserAgent(ua) {
        if (!ua) {
            return { deviceName: 'Unknown Device', deviceType: 'unknown' };
        }
        let deviceName = 'Unknown Device';
        let deviceType = 'unknown';
        if (/iPhone/i.test(ua)) {
            deviceType = 'mobile';
            deviceName = 'iPhone';
        }
        else if (/iPad/i.test(ua)) {
            deviceType = 'tablet';
            deviceName = 'iPad';
        }
        else if (/Android/i.test(ua)) {
            deviceType = /Mobile/i.test(ua) ? 'mobile' : 'tablet';
            deviceName = /Mobile/i.test(ua) ? 'Android Phone' : 'Android Tablet';
        }
        else if (/Windows/i.test(ua)) {
            deviceType = 'desktop';
            deviceName = 'Windows PC';
        }
        else if (/Macintosh/i.test(ua)) {
            deviceType = 'desktop';
            deviceName = 'Mac';
        }
        else if (/Linux/i.test(ua)) {
            deviceType = 'desktop';
            deviceName = 'Linux PC';
        }
        let browser = '';
        if (/Edg\//i.test(ua)) {
            browser = 'Edge';
        }
        else if (/Chrome/i.test(ua) && !/Edg/i.test(ua)) {
            browser = 'Chrome';
        }
        else if (/Firefox/i.test(ua)) {
            browser = 'Firefox';
        }
        else if (/Safari/i.test(ua) && !/Chrome/i.test(ua)) {
            browser = 'Safari';
        }
        if (/Dart/i.test(ua)) {
            deviceType = /Mobile|iPhone|Android/i.test(ua) ? 'mobile' : deviceType;
            browser = 'Daxelo App';
        }
        if (browser && deviceName !== 'Unknown Device') {
            deviceName = `${deviceName} — ${browser}`;
        }
        else if (browser) {
            deviceName = browser;
        }
        return { deviceName, deviceType };
    }
    async cleanupExpiredTokens() {
        const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
        const result = await this.prisma.refreshToken.deleteMany({
            where: {
                OR: [
                    { expiresAt: { lt: new Date() } },
                    {
                        revokedAt: { not: null, lt: thirtyDaysAgo },
                    },
                ],
            },
        });
        return { deleted: result.count };
    }
};
exports.AuthService = AuthService;
exports.AuthService = AuthService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        jwt_1.JwtService,
        config_1.ConfigService])
], AuthService);
//# sourceMappingURL=auth.service.js.map