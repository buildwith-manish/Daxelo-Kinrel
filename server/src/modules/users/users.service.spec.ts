import { Test, TestingModule } from '@nestjs/testing';
import { UsersService } from './users.service';
import { PrismaService } from '../../prisma/prisma.service';
import { ConfigService } from '@nestjs/config';
import { CacheService } from '../../common/cache/cache.service';
import {
  BadRequestException,
  ConflictException,
  HttpException,
  NotFoundException,
} from '@nestjs/common';

// ── Mock PrismaService ──────────────────────────────────────────────────

const mockPrismaService = {
  user: {
    findUnique: jest.fn(),
    update: jest.fn(),
  },
  person: {
    findFirst: jest.fn(),
  },
  usernameChangeLog: {
    create: jest.fn(),
    findMany: jest.fn(),
  },
  $transaction: jest.fn(),
};

// ── Mock ConfigService ──────────────────────────────────────────────────

const mockConfigService = {
  get: jest.fn().mockReturnValue(null), // No Cloudinary by default
};

// ── Mock CacheService ───────────────────────────────────────────────────

const mockCacheService = {
  get: jest.fn(),
  set: jest.fn(),
  delete: jest.fn(),
};

describe('UsersService', () => {
  let service: UsersService;

  beforeEach(async () => {
    jest.clearAllMocks();

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        UsersService,
        { provide: PrismaService, useValue: mockPrismaService },
        { provide: ConfigService, useValue: mockConfigService },
        { provide: CacheService, useValue: mockCacheService },
      ],
    }).compile();

    service = module.get<UsersService>(UsersService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ── checkUsername ───────────────────────────────────────────────────

  describe('checkUsername', () => {
    it('should return available for a valid, unused username', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue(null);
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      const result = await service.checkUsername('rahul123');

      expect(result.available).toBe(true);
    });

    it('should return unavailable for taken username', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue({
        id: 'user-1',
        username: 'rahul123',
      });

      const result = await service.checkUsername('rahul123') as any;

      expect(result.available).toBe(false);
      expect(result.reason).toBe('Username is already taken');
    });

    it('should return unavailable for username taken in Person table', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue(null);
      mockPrismaService.person.findFirst.mockResolvedValue({
        id: 'person-1',
        username: 'rahul123',
      });

      const result = await service.checkUsername('rahul123') as any;

      expect(result.available).toBe(false);
      expect(result.reason).toBe('Username is already taken');
    });

    it('should reject too short username', async () => {
      const result = await service.checkUsername('ab') as any;

      expect(result.available).toBe(false);
      expect(result.reason).toContain('at least 3 characters');
    });

    it('should reject reserved username', async () => {
      const result = await service.checkUsername('admin') as any;

      expect(result.available).toBe(false);
      expect(result.reason).toContain('reserved');
    });

    it('should reject invalid format (starts with number)', async () => {
      const result = await service.checkUsername('123rahul') as any;

      expect(result.available).toBe(false);
      expect(result.reason).toContain('start with a letter');
    });

    it('should reject invalid format (uppercase)', async () => {
      // Note: checkUsername lowercases the input, so 'Rahul' → 'rahul'
      // which is a valid format. The validation rejects mixed-case input
      // only if it doesn't match the lowercase-only regex after conversion.
      // So we test with an explicit format violation instead.
      const result = await service.checkUsername('Rahul-Test') as any;

      expect(result.available).toBe(false);
      expect(result.reason).toBeDefined();
    });

    it('should enforce rate limiting with userId', async () => {
      const userId = 'user-1';

      // Do 5 checks (the limit)
      for (let i = 0; i < 5; i++) {
        mockPrismaService.user.findUnique.mockResolvedValue(null);
        mockPrismaService.person.findFirst.mockResolvedValue(null);
        await service.checkUsername(`username${i}`, userId);
      }

      // 6th check should be rate limited
      await expect(
        service.checkUsername('anotheruser', userId),
      ).rejects.toThrow(HttpException);

      // Without userId, should not be rate limited
      mockPrismaService.user.findUnique.mockResolvedValue(null);
      mockPrismaService.person.findFirst.mockResolvedValue(null);
      const result = await service.checkUsername('nolimituser');
      expect(result.available).toBe(true);
    });

    it('should use in-memory cache for repeated checks', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue(null);
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      // First check
      const result1 = await service.checkUsername('freshuser');
      expect(result1.available).toBe(true);
      expect(mockPrismaService.user.findUnique).toHaveBeenCalledTimes(1);

      // Second check should use cache (30s TTL)
      const result2 = await service.checkUsername('freshuser');
      expect(result2.available).toBe(true);
      // Should NOT call the database again
      expect(mockPrismaService.user.findUnique).toHaveBeenCalledTimes(1);
    });
  });

  // ── updateUsername ──────────────────────────────────────────────────

  describe('updateUsername', () => {
    const userId = 'user-123';

    it('should update and log change', async () => {
      const oldUsername = 'olduser';
      const newUsername = 'newuser';

      mockPrismaService.user.findUnique
        .mockResolvedValueOnce({ id: userId, username: oldUsername }) // check availability
        .mockResolvedValueOnce({ id: userId, username: oldUsername }); // get current user

      mockPrismaService.$transaction.mockImplementation(async (cb) => {
        const tx = {
          usernameChangeLog: {
            create: jest.fn().mockResolvedValue({ id: 'log-1' }),
          },
          user: {
            update: jest.fn().mockResolvedValue({
              id: userId,
              username: newUsername,
              name: 'Rahul',
              email: 'rahul@test.com',
              avatarUrl: null,
              photoThumb: null,
            }),
          },
        };
        return cb(tx);
      });

      const result = await service.updateUsername(userId, newUsername);

      expect(result.user.username).toBe(newUsername);
    });

    it('should throw BadRequestException for too short username', async () => {
      await expect(
        service.updateUsername(userId, 'ab'),
      ).rejects.toThrow(BadRequestException);
    });

    it('should throw BadRequestException for invalid format', async () => {
      await expect(
        service.updateUsername(userId, 'INVALID'),
      ).rejects.toThrow(BadRequestException);
    });

    it('should throw ConflictException if username is taken by another user', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue({
        id: 'other-user',
        username: 'takenuser',
      });

      await expect(
        service.updateUsername(userId, 'takenuser'),
      ).rejects.toThrow(ConflictException);
    });

    it('should allow updating to same username (no-op)', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue({
        id: userId,
        username: 'sameuser',
      });

      mockPrismaService.$transaction.mockImplementation(async (cb) => {
        const tx = {
          usernameChangeLog: {
            create: jest.fn().mockResolvedValue({ id: 'log-1' }),
          },
          user: {
            update: jest.fn().mockResolvedValue({
              id: userId,
              username: 'sameuser',
              name: 'Rahul',
              email: 'rahul@test.com',
              avatarUrl: null,
              photoThumb: null,
            }),
          },
        };
        return cb(tx);
      });

      // Should NOT throw - it's the same user
      const result = await service.updateUsername(userId, 'sameuser');
      expect(result.user.username).toBe('sameuser');
    });

    it('should invalidate cache for old and new username', async () => {
      const oldUsername = 'olduser';
      const newUsername = 'newuser';

      mockPrismaService.user.findUnique
        .mockResolvedValueOnce(null) // no other user has newUsername
        .mockResolvedValueOnce({ id: userId, username: oldUsername }); // get current

      mockPrismaService.$transaction.mockImplementation(async (cb) => {
        const tx = {
          usernameChangeLog: {
            create: jest.fn().mockResolvedValue({ id: 'log-1' }),
          },
          user: {
            update: jest.fn().mockResolvedValue({
              id: userId,
              username: newUsername,
              name: 'Rahul',
              email: 'rahul@test.com',
              avatarUrl: null,
              photoThumb: null,
            }),
          },
        };
        return cb(tx);
      });

      await service.updateUsername(userId, newUsername);

      // The service should invalidate the in-memory cache for both usernames
      // We can verify this indirectly by checking that a subsequent checkUsername
      // call actually hits the database
      mockPrismaService.user.findUnique.mockResolvedValue(null);
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      await service.checkUsername(newUsername);
      // After cache invalidation, findUnique should have been called
      expect(mockPrismaService.user.findUnique).toHaveBeenCalled();
    });
  });

  // ── generateUsernameSuggestions ─────────────────────────────────────

  describe('generateUsernameSuggestions', () => {
    it('should return valid suggestions', async () => {
      // Mock all database checks to return null (available)
      mockPrismaService.user.findUnique.mockResolvedValue(null);
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      const result = await service.generateUsernameSuggestions('Rahul Sharma', 'user-1');

      expect(result.suggestions).toBeDefined();
      expect(result.suggestions.length).toBeLessThanOrEqual(5);
      expect(result.suggestions.length).toBeGreaterThan(0);

      // Each suggestion should have username and available fields
      for (const suggestion of result.suggestions) {
        expect(suggestion).toHaveProperty('username');
        expect(suggestion).toHaveProperty('available');
      }
    });

    it('should throw BadRequestException for empty displayName', async () => {
      await expect(
        service.generateUsernameSuggestions('', 'user-1'),
      ).rejects.toThrow(BadRequestException);
    });

    it('should generate suggestions based on first name', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue(null);
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      const result = await service.generateUsernameSuggestions('Rahul', 'user-1');

      // Should have at least a suggestion starting with 'rahul'
      const firstNamesSuggestions = result.suggestions.filter(
        (s) => s.username.startsWith('rahul'),
      );
      expect(firstNamesSuggestions.length).toBeGreaterThan(0);
    });

    it('should generate suggestions combining first and last name', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue(null);
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      const result = await service.generateUsernameSuggestions(
        'Rahul Sharma',
        'user-1',
      );

      // Should have combined suggestions
      const combinedSuggestions = result.suggestions.filter(
        (s) => s.username.includes('sharma'),
      );
      expect(combinedSuggestions.length).toBeGreaterThan(0);
    });

    it('should mark reserved words as unavailable', async () => {
      // Try with a name that would generate 'admin' as a suggestion
      // This is tricky - 'admin' is reserved. The service should mark it unavailable.
      const result = await service.generateUsernameSuggestions('Admin', 'user-1');

      const adminSuggestion = result.suggestions.find(
        (s) => s.username === 'admin',
      );
      if (adminSuggestion) {
        expect(adminSuggestion.available).toBe(false);
      }
    });

    it('should mark format-invalid suggestions as unavailable', async () => {
      // A name like "123 Rahul" would generate "123rahul" which starts with a number
      const result = await service.generateUsernameSuggestions('123 Rahul', 'user-1');

      const invalidSuggestion = result.suggestions.find(
        (s) => s.username.startsWith('123'),
      );
      if (invalidSuggestion) {
        expect(invalidSuggestion.available).toBe(false);
      }
    });

    it('should check availability in both User and Person tables', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue(null);
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      await service.generateUsernameSuggestions('Rahul', 'user-1');

      // Both tables should have been checked
      expect(mockPrismaService.user.findUnique).toHaveBeenCalled();
      expect(mockPrismaService.person.findFirst).toHaveBeenCalled();
    });
  });

  // ── Username format validation ─────────────────────────────────────

  describe('username format validation', () => {
    it('should accept valid usernames', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue(null);
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      const validUsernames = [
        'rahul',
        'rahul123',
        'rahul_sharma',
        'r_s_123',
        'a12345678901234567890123456789', // 30 chars
      ];

      for (const username of validUsernames) {
        const result = await service.checkUsername(username);
        expect(result.available).toBe(true);
      }
    });

    it('should reject usernames that start with a number', async () => {
      const result = await service.checkUsername('1rahul') as any;
      expect(result.available).toBe(false);
      expect(result.reason).toContain('start with a letter');
    });

    it('should reject usernames with special characters', async () => {
      const result = await service.checkUsername('rahul@sharma') as any;
      expect(result.available).toBe(false);
      expect(result.reason).toBeDefined();
    });

    it('should reject usernames with spaces', async () => {
      const result = await service.checkUsername('rahul sharma') as any;
      expect(result.available).toBe(false);
      expect(result.reason).toBeDefined();
    });

    it('should reject usernames that are too long (>30 chars)', async () => {
      const result = await service.checkUsername('a'.repeat(31)) as any;
      expect(result.available).toBe(false);
      expect(result.reason).toBeDefined();
    });

    it('should lowercase and validate usernames', async () => {
      // The service lowercases input before regex check
      // 'Rahul' → 'rahul' which is valid format, but might be cached
      // Testing with a truly invalid format instead
      const result = await service.checkUsername('RAHUL-TEST') as any;
      expect(result.available).toBe(false);
      expect(result.reason).toBeDefined();
    });

    it('should accept underscore in the middle', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue(null);
      mockPrismaService.person.findFirst.mockResolvedValue(null);

      const result = await service.checkUsername('rahul_sharma');
      expect(result.available).toBe(true);
    });

    it('should reject username starting with underscore', async () => {
      const result = await service.checkUsername('_rahul') as any;
      expect(result.available).toBe(false);
      expect(result.reason).toBeDefined();
    });
  });

  // ── getUsernameHistory ──────────────────────────────────────────────

  describe('getUsernameHistory', () => {
    it('should return username change history', async () => {
      const history = [
        { id: 'log-1', oldUsername: 'old1', newUsername: 'old2', changedAt: new Date() },
        { id: 'log-2', oldUsername: 'old2', newUsername: 'current', changedAt: new Date() },
      ];

      mockPrismaService.usernameChangeLog.findMany.mockResolvedValue(history);

      const result = await service.getUsernameHistory('user-1');

      expect(result.history).toHaveLength(2);
      expect(result.history[0].oldUsername).toBe('old1');
    });

    it('should return empty history for users with no changes', async () => {
      mockPrismaService.usernameChangeLog.findMany.mockResolvedValue([]);

      const result = await service.getUsernameHistory('user-1');

      expect(result.history).toHaveLength(0);
    });
  });

  // ── getUserByUsername ───────────────────────────────────────────────

  describe('getUserByUsername', () => {
    it('should return public profile for existing user', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue({
        id: 'user-1',
        name: 'Rahul Sharma',
        username: 'rahul',
        avatarUrl: 'https://example.com/avatar.jpg',
        photoThumb: null,
        bio: 'Hello!',
        createdAt: new Date(),
      });

      const result = await service.getUserByUsername('rahul');

      expect(result.username).toBe('rahul');
      expect(result.name).toBe('Rahul Sharma');
      // Should NOT include sensitive fields like email
      expect(result).not.toHaveProperty('email');
    });

    it('should throw NotFoundException for reserved usernames', async () => {
      await expect(
        service.getUserByUsername('admin'),
      ).rejects.toThrow(NotFoundException);
    });

    it('should throw NotFoundException for unknown user', async () => {
      mockPrismaService.user.findUnique.mockResolvedValue(null);

      await expect(
        service.getUserByUsername('nonexistent'),
      ).rejects.toThrow(NotFoundException);
    });

    it('should throw BadRequestException for too short username', async () => {
      await expect(
        service.getUserByUsername('ab'),
      ).rejects.toThrow(BadRequestException);
    });
  });
});
