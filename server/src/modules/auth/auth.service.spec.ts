import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  ConflictException,
  UnauthorizedException,
  BadRequestException,
  NotFoundException,
  InternalServerErrorException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { TwoFactorVerificationService } from '../../common/services/two-factor-verification.service';
import { AuthService } from './auth.service';
import * as bcrypt from 'bcryptjs';
import * as crypto from 'crypto';
import { authenticator } from '@otplib/preset-default';
import { encrypt, decrypt } from '../../common/utils/encryption.util';

// ── Constants ──────────────────────────────────────────────────────────

const ENCRYPTION_KEY = 'a'.repeat(64); // 32 bytes = 64 hex chars for AES-256
const ACCESS_SECRET = 'test-access-secret';
const REFRESH_SECRET = 'test-refresh-secret';

// ── Mock PrismaService ─────────────────────────────────────────────────

const mockPrisma = {
  user: {
    create: jest.fn(),
    findUnique: jest.fn(),
    findFirst: jest.fn(),
    update: jest.fn(),
  },
  family: {
    create: jest.fn(),
  },
  familyMember: {
    create: jest.fn(),
  },
  refreshToken: {
    create: jest.fn(),
    findUnique: jest.fn(),
    findFirst: jest.fn(),
    update: jest.fn(),
    updateMany: jest.fn(),
    delete: jest.fn(),
    deleteMany: jest.fn(),
    findMany: jest.fn(),
  },
  $transaction: jest.fn(),
};

// ── Mock ConfigService ─────────────────────────────────────────────────

const mockConfig = {
  get: jest.fn((key: string, defaultValue?: any) => {
    switch (key) {
      case 'JWT_ACCESS_SECRET':
        return ACCESS_SECRET;
      case 'JWT_REFRESH_SECRET':
        return REFRESH_SECRET;
      case 'JWT_ACCESS_EXPIRATION':
        return '15m';
      case 'JWT_REFRESH_EXPIRATION':
        return '7d';
      case 'ENCRYPTION_KEY':
        return ENCRYPTION_KEY;
      case 'REDIS_URL':
        return ''; // No Redis in tests
      default:
        return defaultValue ?? undefined;
    }
  }),
};

// ── Mock JwtService ────────────────────────────────────────────────────

const mockJwt = {
  sign: jest.fn().mockReturnValue('mocked-jwt-token'),
  signAsync: jest.fn().mockResolvedValue('mocked-jwt-token'),
};

// ── Mock TwoFactorVerificationService ──────────────────────────────────

const mockTwoFactorVerification = {
  markVerified: jest.fn().mockResolvedValue(undefined),
  clearVerification: jest.fn().mockResolvedValue(undefined),
  isVerified: jest.fn().mockResolvedValue(false),
};

// ── Test Suite ─────────────────────────────────────────────────────────

describe('AuthService', () => {
  let service: AuthService;

  beforeEach(async () => {
    jest.clearAllMocks();

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: JwtService, useValue: mockJwt },
        { provide: ConfigService, useValue: mockConfig },
        { provide: TwoFactorVerificationService, useValue: mockTwoFactorVerification },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ── register() ──────────────────────────────────────────────────────

  describe('register', () => {
    const registerDto = {
      name: 'John Doe',
      email: 'john@example.com',
      password: 'SecurePass123!',
    };

    it('should create a user and auto-create "My Family"', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null); // no existing user

      const createdUser = {
        id: 'user-1',
        email: 'john@example.com',
        name: 'John Doe',
      };
      const createdFamily = {
        id: 'family-1',
        name: 'My Family',
        createdBy: 'user-1',
        primaryLanguage: 'en',
        privacyMode: 'private',
        memberCount: 1,
        lastActivityAt: expect.any(Date),
      };

      mockPrisma.$transaction.mockImplementation(async (cb: any) => {
        const tx = {
          user: {
            create: jest.fn().mockResolvedValue(createdUser),
          },
          family: {
            create: jest.fn().mockResolvedValue(createdFamily),
          },
          familyMember: {
            create: jest.fn().mockResolvedValue({
              id: 'member-1',
              familyId: 'family-1',
              userId: 'user-1',
              role: 'admin',
            }),
          },
        };
        return cb(tx);
      });

      const result = await service.register(registerDto);

      expect(result.user).toEqual(createdUser);
      expect(result.familyId).toBe('family-1');
    });

    it('should throw ConflictException if email already exists', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: 'existing-user',
        email: 'john@example.com',
      });

      await expect(service.register(registerDto)).rejects.toThrow(
        ConflictException,
      );
      await expect(service.register(registerDto)).rejects.toThrow(
        'An account with this email already exists',
      );
    });

    it('should throw ConflictException on race condition (P2002 error)', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null); // passes first check

      const prismaError: any = new Error('Unique constraint failed');
      prismaError.code = 'P2002';
      prismaError.meta = { target: ['email'] };

      mockPrisma.$transaction.mockRejectedValue(prismaError);

      await expect(service.register(registerDto)).rejects.toThrow(
        ConflictException,
      );
    });

    it('should trim and lowercase the email', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);

      mockPrisma.$transaction.mockImplementation(async (cb: any) => {
        const tx = {
          user: {
            create: jest.fn().mockImplementation(({ data }) => {
              expect(data.email).toBe('john@example.com'); // trimmed & lowered
              return Promise.resolve({ id: 'user-1', email: data.email, name: data.name });
            }),
          },
          family: {
            create: jest.fn().mockResolvedValue({ id: 'family-1', name: 'My Family', createdBy: 'user-1', primaryLanguage: 'en', privacyMode: 'private', memberCount: 1, lastActivityAt: new Date() }),
          },
          familyMember: {
            create: jest.fn().mockResolvedValue({ id: 'member-1' }),
          },
        };
        return cb(tx);
      });

      await service.register({
        ...registerDto,
        email: '  John@Example.COM  ',
      });
    });
  });

  // ── login() ─────────────────────────────────────────────────────────

  describe('login', () => {
    const loginDto = {
      email: 'john@example.com',
      password: 'SecurePass123!',
    };

    const passwordHash = bcrypt.hashSync('SecurePass123!', 12);

    const mockUser = {
      id: 'user-1',
      email: 'john@example.com',
      name: 'John Doe',
      role: 'user',
      preferredLanguage: 'en',
      passwordHash,
      twoFactorEnabled: false,
    };

    it('should return tokens on successful login with correct password', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(mockUser);
      mockJwt.sign.mockReturnValue('access-token-abc');
      mockPrisma.refreshToken.create.mockResolvedValue({
        token: 'refresh-token-xyz',
      });

      const result = await service.login(loginDto);

      expect(result.accessToken).toBe('access-token-abc');
      expect(result.refreshToken).toBeDefined();
      expect(typeof result.refreshToken).toBe('string');
      expect(result.user.id).toBe('user-1');
      expect(result.user.email).toBe('john@example.com');
    });

    it('should throw UnauthorizedException with wrong password', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(mockUser);

      await expect(
        service.login({ email: 'john@example.com', password: 'WrongPassword!' }),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('should throw UnauthorizedException for non-existent user', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);

      await expect(
        service.login({ email: 'nobody@example.com', password: 'anything' }),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('should throw UnauthorizedException for user without passwordHash', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        ...mockUser,
        passwordHash: null,
      });

      await expect(
        service.login(loginDto),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('should return 2FA challenge when twoFactorEnabled is true', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        ...mockUser,
        twoFactorEnabled: true,
        twoFactorSecret: 'some-encrypted-secret',
      });
      mockJwt.sign.mockReturnValue('challenge-token-xyz');

      const result = await service.login(loginDto);

      expect(result.requiresTwoFactor).toBe(true);
      expect(result.challengeToken).toBe('challenge-token-xyz');
      // Should NOT return access/refresh tokens
      expect(result.accessToken).toBeUndefined();
      expect(result.refreshToken).toBeUndefined();
    });

    it('should auto-upgrade legacy SHA-256 password to bcrypt', async () => {
      // Compute SHA-256 hash of the password
      const sha256Hash = crypto
        .createHash('sha256')
        .update('LegacyPass123!')
        .digest('hex');

      const legacyUser = {
        ...mockUser,
        passwordHash: `sha256:${sha256Hash}`,
      };

      mockPrisma.user.findUnique.mockResolvedValue(legacyUser);
      mockPrisma.user.update.mockResolvedValue({
        ...legacyUser,
        passwordHash: 'new-bcrypt-hash',
      });
      mockJwt.sign.mockReturnValue('access-token-after-upgrade');
      mockPrisma.refreshToken.create.mockResolvedValue({
        token: 'refresh-token-after-upgrade',
      });

      const result = await service.login({
        email: 'john@example.com',
        password: 'LegacyPass123!',
      });

      // Should have called update to upgrade the password hash
      expect(mockPrisma.user.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'user-1' },
          data: { passwordHash: expect.any(String) },
        }),
      );
      // The new hash should be a bcrypt hash (starts with $2a$ or $2b$)
      const updateCall = mockPrisma.user.update.mock.calls[0][0];
      expect(updateCall.data.passwordHash).toMatch(/^\$2[ab]\$/);
      expect(result.accessToken).toBe('access-token-after-upgrade');
    });
  });

  // ── refresh() ───────────────────────────────────────────────────────

  describe('refresh', () => {
    const oldToken = 'old-refresh-token-uuid';
    const familyId = 'family-uuid-123';

    const storedToken = {
      token: oldToken,
      userId: 'user-1',
      familyId,
      expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000), // 7 days in future
      revokedAt: null,
      user: {
        id: 'user-1',
        email: 'john@example.com',
        role: 'user',
      },
    };

    it('should return new token pair on valid refresh', async () => {
      mockPrisma.refreshToken.findUnique.mockResolvedValue(storedToken);
      mockPrisma.refreshToken.update.mockResolvedValue({
        ...storedToken,
        revokedAt: new Date(),
      });
      mockJwt.sign.mockReturnValue('new-access-token');
      mockPrisma.refreshToken.create.mockResolvedValue({
        token: 'new-refresh-token',
      });

      const result = await service.refresh(oldToken);

      expect(result.accessToken).toBe('new-access-token');
      expect(result.refreshToken).toBeDefined();
      // Old token should be revoked
      expect(mockPrisma.refreshToken.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { token: oldToken },
          data: { revokedAt: expect.any(Date) },
        }),
      );
    });

    it('should throw UnauthorizedException for invalid token', async () => {
      mockPrisma.refreshToken.findUnique.mockResolvedValue(null);

      await expect(service.refresh('nonexistent-token')).rejects.toThrow(
        UnauthorizedException,
      );
      await expect(service.refresh('nonexistent-token')).rejects.toThrow(
        'Invalid refresh token',
      );
    });

    it('should throw UnauthorizedException for expired token', async () => {
      mockPrisma.refreshToken.findUnique.mockResolvedValue({
        ...storedToken,
        expiresAt: new Date(Date.now() - 1000), // expired
      });
      mockPrisma.refreshToken.delete.mockResolvedValue({});

      await expect(service.refresh(oldToken)).rejects.toThrow(
        UnauthorizedException,
      );
      await expect(service.refresh(oldToken)).rejects.toThrow(
        'Refresh token has expired',
      );
      // Expired token should be deleted
      expect(mockPrisma.refreshToken.delete).toHaveBeenCalledWith({
        where: { token: oldToken },
      });
    });

    it('should revoke entire token family on token reuse detection', async () => {
      const revokedToken = {
        ...storedToken,
        revokedAt: new Date(), // Already revoked = reuse detected
      };
      mockPrisma.refreshToken.findUnique.mockResolvedValue(revokedToken);
      mockPrisma.refreshToken.updateMany.mockResolvedValue({ count: 3 });

      await expect(service.refresh(oldToken)).rejects.toThrow(
        UnauthorizedException,
      );
      await expect(service.refresh(oldToken)).rejects.toThrow(
        'Refresh token reuse detected',
      );

      // Should revoke all tokens in the family
      expect(mockPrisma.refreshToken.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { familyId, revokedAt: null },
          data: { revokedAt: expect.any(Date) },
        }),
      );
    });

    it('should keep the same familyId when rotating tokens', async () => {
      mockPrisma.refreshToken.findUnique.mockResolvedValue(storedToken);
      mockPrisma.refreshToken.update.mockResolvedValue({
        ...storedToken,
        revokedAt: new Date(),
      });
      mockJwt.sign.mockReturnValue('new-access-token');
      mockPrisma.refreshToken.create.mockImplementation(({ data }) => {
        expect(data.familyId).toBe(familyId); // Same family
        return Promise.resolve({ token: data.token });
      });

      await service.refresh(oldToken);
    });
  });

  // ── logout() ────────────────────────────────────────────────────────

  describe('logout', () => {
    it('should revoke the refresh token on logout', async () => {
      const storedToken = {
        token: 'refresh-token-abc',
        userId: 'user-1',
        revokedAt: null,
      };
      mockPrisma.refreshToken.findUnique.mockResolvedValue(storedToken);
      mockPrisma.refreshToken.update.mockResolvedValue({
        ...storedToken,
        revokedAt: new Date(),
      });

      const result = await service.logout('refresh-token-abc');

      expect(result.success).toBe(true);
      expect(mockPrisma.refreshToken.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { token: 'refresh-token-abc' },
          data: { revokedAt: expect.any(Date) },
        }),
      );
      // Should also clear 2FA verification status
      expect(mockTwoFactorVerification.clearVerification).toHaveBeenCalledWith('user-1');
    });

    it('should return success even if token not found', async () => {
      mockPrisma.refreshToken.findUnique.mockResolvedValue(null);

      const result = await service.logout('nonexistent-token');

      expect(result.success).toBe(true);
    });

    it('should not throw if token is already revoked', async () => {
      const storedToken = {
        token: 'already-revoked',
        userId: 'user-1',
        revokedAt: new Date(), // already revoked
      };
      mockPrisma.refreshToken.findUnique.mockResolvedValue(storedToken);

      const result = await service.logout('already-revoked');

      expect(result.success).toBe(true);
      // Should NOT update again since already revoked
      expect(mockPrisma.refreshToken.update).not.toHaveBeenCalled();
      // Should still clear 2FA verification
      expect(mockTwoFactorVerification.clearVerification).toHaveBeenCalledWith('user-1');
    });
  });

  // ── changePassword() ────────────────────────────────────────────────

  describe('changePassword', () => {
    const userId = 'user-1';
    const currentPassword = 'OldPassword123!';
    const newPassword = 'NewPassword456!';
    const currentHash = bcrypt.hashSync('OldPassword123!', 12);

    it('should change password and revoke all refresh tokens', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: userId,
        passwordHash: currentHash,
      });
      mockPrisma.$transaction.mockImplementation(async (cb: any) => {
        const tx = {
          user: {
            update: jest.fn().mockResolvedValue({ id: userId }),
          },
          refreshToken: {
            updateMany: jest.fn().mockResolvedValue({ count: 3 }),
          },
        };
        return cb(tx);
      });

      const result = await service.changePassword(userId, {
        currentPassword,
        newPassword,
      });

      expect(result.message).toBe('Password changed successfully');
      // Verify the transaction was called (password update + token revocation)
      expect(mockPrisma.$transaction).toHaveBeenCalled();
    });

    it('should throw UnauthorizedException if current password is wrong', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: userId,
        passwordHash: currentHash,
      });

      await expect(
        service.changePassword(userId, {
          currentPassword: 'WrongPassword!',
          newPassword,
        }),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('should throw NotFoundException if user not found', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);

      await expect(
        service.changePassword(userId, {
          currentPassword,
          newPassword,
        }),
      ).rejects.toThrow(NotFoundException);
    });

    it('should throw NotFoundException if user has no passwordHash', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: userId,
        passwordHash: null,
      });

      await expect(
        service.changePassword(userId, {
          currentPassword,
          newPassword,
        }),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ── setup2FA() ──────────────────────────────────────────────────────

  describe('setup2FA', () => {
    const userId = 'user-1';

    it('should generate TOTP secret and QR code URL', async () => {
      mockPrisma.user.update.mockResolvedValue({ id: userId });

      const result = await service.setup2FA(userId);

      expect(result.secret).toBeDefined();
      expect(result.qrCodeUrl).toBeDefined();
      expect(result.qrCodeUrl).toContain('otpauth://totp/');
      // Should store encrypted secret in DB
      expect(mockPrisma.user.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: userId },
          data: { twoFactorSecret: expect.any(String) },
        }),
      );
      // The stored secret should be encrypted (contains colons from iv:tag:ciphertext format)
      const storedSecret = mockPrisma.user.update.mock.calls[0][0].data.twoFactorSecret;
      expect(storedSecret).toContain(':'); // Encrypted format iv:tag:ciphertext
    });

    it('should throw InternalServerErrorException if ENCRYPTION_KEY is missing', async () => {
      // Override config to return undefined for ENCRYPTION_KEY
      mockConfig.get.mockImplementation((key: string) => {
        if (key === 'ENCRYPTION_KEY') return undefined;
        if (key === 'REDIS_URL') return '';
        return 'test-value';
      });

      await expect(service.setup2FA(userId)).rejects.toThrow(
        InternalServerErrorException,
      );
      await expect(service.setup2FA(userId)).rejects.toThrow(
        'ENCRYPTION_KEY is not configured',
      );

      // Restore config
      mockConfig.get.mockImplementation((key: string, defaultValue?: any) => {
        switch (key) {
          case 'JWT_ACCESS_SECRET': return ACCESS_SECRET;
          case 'JWT_REFRESH_SECRET': return REFRESH_SECRET;
          case 'JWT_ACCESS_EXPIRATION': return '15m';
          case 'JWT_REFRESH_EXPIRATION': return '7d';
          case 'ENCRYPTION_KEY': return ENCRYPTION_KEY;
          case 'REDIS_URL': return '';
          default: return defaultValue ?? undefined;
        }
      });
    });
  });

  // ── verify2FA() ─────────────────────────────────────────────────────

  describe('verify2FA', () => {
    const userId = 'user-1';

    it('should verify a valid TOTP code and enable 2FA', async () => {
      // Generate a real TOTP secret for testing
      const secret = authenticator.generateSecret();
      const encryptedSecret = encrypt(secret, ENCRYPTION_KEY);

      // Generate a valid TOTP code
      const validCode = authenticator.generate(secret);

      mockPrisma.user.findUnique.mockResolvedValue({
        id: userId,
        twoFactorSecret: encryptedSecret,
      });
      mockPrisma.user.update.mockResolvedValue({
        id: userId,
        twoFactorEnabled: true,
      });

      const result = await service.verify2FA(userId, validCode);

      expect(result.verified).toBe(true);
      expect(mockPrisma.user.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: userId },
          data: { twoFactorEnabled: true },
        }),
      );
    });

    it('should throw UnauthorizedException with wrong TOTP code', async () => {
      const secret = authenticator.generateSecret();
      const encryptedSecret = encrypt(secret, ENCRYPTION_KEY);

      mockPrisma.user.findUnique.mockResolvedValue({
        id: userId,
        twoFactorSecret: encryptedSecret,
      });

      await expect(
        service.verify2FA(userId, '000000'), // Almost certainly invalid
      ).rejects.toThrow(UnauthorizedException);
    });

    it('should throw BadRequestException if 2FA setup not initiated', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: userId,
        twoFactorSecret: null,
      });

      await expect(
        service.verify2FA(userId, '123456'),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.verify2FA(userId, '123456'),
      ).rejects.toThrow('2FA setup not initiated');
    });

    it('should throw InternalServerErrorException if ENCRYPTION_KEY is missing', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: userId,
        twoFactorSecret: 'some-encrypted-secret',
      });

      mockConfig.get.mockImplementation((key: string) => {
        if (key === 'ENCRYPTION_KEY') return undefined;
        if (key === 'REDIS_URL') return '';
        return 'test-value';
      });

      await expect(
        service.verify2FA(userId, '123456'),
      ).rejects.toThrow(InternalServerErrorException);

      // Restore config
      mockConfig.get.mockImplementation((key: string, defaultValue?: any) => {
        switch (key) {
          case 'JWT_ACCESS_SECRET': return ACCESS_SECRET;
          case 'JWT_REFRESH_SECRET': return REFRESH_SECRET;
          case 'JWT_ACCESS_EXPIRATION': return '15m';
          case 'JWT_REFRESH_EXPIRATION': return '7d';
          case 'ENCRYPTION_KEY': return ENCRYPTION_KEY;
          case 'REDIS_URL': return '';
          default: return defaultValue ?? undefined;
        }
      });
    });
  });

  // ── loginVerify2FA() ────────────────────────────────────────────────

  describe('loginVerify2FA', () => {
    const userId = 'user-1';

    it('should return tokens on valid 2FA login verification', async () => {
      const secret = authenticator.generateSecret();
      const encryptedSecret = encrypt(secret, ENCRYPTION_KEY);
      const validCode = authenticator.generate(secret);

      mockPrisma.user.findUnique.mockResolvedValue({
        id: userId,
        email: 'john@example.com',
        role: 'user',
        twoFactorEnabled: true,
        twoFactorSecret: encryptedSecret,
      });
      mockJwt.sign.mockReturnValue('access-token-2fa');
      mockPrisma.refreshToken.create.mockResolvedValue({
        token: 'refresh-token-2fa',
      });

      const result = await service.loginVerify2FA(userId, validCode);

      expect(result.verified).toBe(true);
      expect(result.accessToken).toBe('access-token-2fa');
      expect(result.refreshToken).toBeDefined();
      expect(typeof result.refreshToken).toBe('string');
      expect(mockTwoFactorVerification.markVerified).toHaveBeenCalledWith(userId);
    });

    it('should throw UnauthorizedException if user not found', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);

      await expect(
        service.loginVerify2FA(userId, '123456'),
      ).rejects.toThrow(UnauthorizedException);
      await expect(
        service.loginVerify2FA(userId, '123456'),
      ).rejects.toThrow('User not found');
    });

    it('should throw BadRequestException if 2FA not enabled', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: userId,
        twoFactorEnabled: false,
        twoFactorSecret: null,
      });

      await expect(
        service.loginVerify2FA(userId, '123456'),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.loginVerify2FA(userId, '123456'),
      ).rejects.toThrow('2FA is not enabled');
    });

    it('should throw UnauthorizedException with wrong TOTP code', async () => {
      const secret = authenticator.generateSecret();
      const encryptedSecret = encrypt(secret, ENCRYPTION_KEY);

      mockPrisma.user.findUnique.mockResolvedValue({
        id: userId,
        email: 'john@example.com',
        role: 'user',
        twoFactorEnabled: true,
        twoFactorSecret: encryptedSecret,
      });

      await expect(
        service.loginVerify2FA(userId, '000000'),
      ).rejects.toThrow(UnauthorizedException);
    });
  });

  // ── disable2FA() ────────────────────────────────────────────────────

  describe('disable2FA', () => {
    const userId = 'user-1';
    const password = 'SecurePass123!';
    const passwordHash = bcrypt.hashSync('SecurePass123!', 12);

    it('should disable 2FA with correct password', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: userId,
        passwordHash,
      });
      mockPrisma.user.update.mockResolvedValue({
        id: userId,
        twoFactorEnabled: false,
        twoFactorSecret: null,
      });

      const result = await service.disable2FA(userId, password);

      expect(result.disabled).toBe(true);
      expect(mockPrisma.user.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: userId },
          data: { twoFactorEnabled: false, twoFactorSecret: null },
        }),
      );
    });

    it('should throw UnauthorizedException with wrong password', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: userId,
        passwordHash,
      });

      await expect(
        service.disable2FA(userId, 'WrongPassword'),
      ).rejects.toThrow(UnauthorizedException);
    });

    it('should throw NotFoundException if user not found', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);

      await expect(
        service.disable2FA(userId, password),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ── validateUser() ──────────────────────────────────────────────────

  describe('validateUser', () => {
    it('should return user for valid payload', async () => {
      const mockUser = {
        id: 'user-1',
        email: 'john@example.com',
        name: 'John Doe',
        username: null,
        role: 'user',
        avatarUrl: null,
        preferredLanguage: 'en',
        twoFactorEnabled: false,
      };
      mockPrisma.user.findUnique.mockResolvedValue(mockUser);

      const result = await service.validateUser({
        sub: 'user-1',
        email: 'john@example.com',
      });

      expect(result).toEqual(mockUser);
    });

    it('should return null for non-existent user', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);

      const result = await service.validateUser({
        sub: 'nonexistent',
        email: 'nobody@example.com',
      });

      expect(result).toBeNull();
    });
  });

  // ── me() ────────────────────────────────────────────────────────────

  describe('me', () => {
    it('should return user profile', async () => {
      const mockUser = {
        id: 'user-1',
        email: 'john@example.com',
        name: 'John Doe',
        phone: null,
        preferredLanguage: 'en',
        role: 'user',
        avatarUrl: null,
        twoFactorEnabled: false,
      };
      mockPrisma.user.findUnique.mockResolvedValue(mockUser);

      const result = await service.me('user-1');

      expect(result.user).toEqual(mockUser);
    });

    it('should throw NotFoundException if user not found', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);

      await expect(service.me('nonexistent')).rejects.toThrow(NotFoundException);
    });
  });

  // ── generateTokenPair() ─────────────────────────────────────────────

  describe('generateTokenPair', () => {
    it('should generate access and refresh tokens', async () => {
      mockJwt.sign.mockReturnValue('generated-access-token');
      mockPrisma.refreshToken.create.mockResolvedValue({
        token: 'generated-refresh-token',
      });

      const result = await service.generateTokenPair(
        'user-1',
        'john@example.com',
        'user',
      );

      expect(result.accessToken).toBe('generated-access-token');
      expect(result.refreshToken).toBeDefined();
      expect(mockPrisma.refreshToken.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            userId: 'user-1',
            userAgent: null,
            ipAddress: null,
          }),
        }),
      );
    });

    it('should use existing familyId when provided', async () => {
      mockJwt.sign.mockReturnValue('access-token');
      mockPrisma.refreshToken.create.mockImplementation(({ data }) => {
        expect(data.familyId).toBe('existing-family-id');
        return Promise.resolve({ token: data.token });
      });

      await service.generateTokenPair(
        'user-1',
        'john@example.com',
        'user',
        'existing-family-id',
      );
    });

    it('should store userAgent and ipAddress when provided', async () => {
      mockJwt.sign.mockReturnValue('access-token');
      mockPrisma.refreshToken.create.mockImplementation(({ data }) => {
        expect(data.userAgent).toBe('Mozilla/5.0');
        expect(data.ipAddress).toBe('192.168.1.1');
        return Promise.resolve({ token: data.token });
      });

      await service.generateTokenPair(
        'user-1',
        'john@example.com',
        'user',
        undefined,
        'Mozilla/5.0',
        '192.168.1.1',
      );
    });
  });

  // ── cleanupExpiredTokens() ──────────────────────────────────────────

  describe('cleanupExpiredTokens', () => {
    it('should delete expired and old revoked tokens', async () => {
      mockPrisma.refreshToken.deleteMany.mockResolvedValue({ count: 5 });

      const result = await service.cleanupExpiredTokens();

      expect(result.deleted).toBe(5);
      expect(mockPrisma.refreshToken.deleteMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            OR: expect.arrayContaining([
              expect.objectContaining({ expiresAt: expect.any(Object) }),
              expect.objectContaining({ revokedAt: expect.any(Object) }),
            ]),
          }),
        }),
      );
    });
  });

  // ── Security Edge Cases ─────────────────────────────────────────────

  describe('security edge cases', () => {
    it('should trim and lowercase email on login', async () => {
      const passwordHash = bcrypt.hashSync('SecurePass123!', 12);
      mockPrisma.user.findUnique.mockImplementation(({ where }) => {
        // Verify the email was trimmed and lowercased
        expect(where.email).toBe('john@example.com');
        return Promise.resolve({
          id: 'user-1',
          email: 'john@example.com',
          name: 'John Doe',
          role: 'user',
          preferredLanguage: 'en',
          passwordHash,
          twoFactorEnabled: false,
        });
      });
      mockJwt.sign.mockReturnValue('token');
      mockPrisma.refreshToken.create.mockResolvedValue({ token: 'rt' });

      await service.login({
        email: '  John@Example.COM  ',
        password: 'SecurePass123!',
      });
    });

    it('encrypt/decrypt roundtrip should preserve the original value', () => {
      const original = 'my-secret-totp-key-base32';
      const encrypted = encrypt(original, ENCRYPTION_KEY);
      const decrypted = decrypt(encrypted, ENCRYPTION_KEY);

      expect(decrypted).toBe(original);
      // Encrypted should be different from original
      expect(encrypted).not.toBe(original);
    });
  });
});
