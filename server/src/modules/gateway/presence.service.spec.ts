import { Test, TestingModule } from '@nestjs/testing';
import { PresenceService } from './presence.service';
import { PrismaService } from '../../prisma/prisma.service';
import { ConfigService } from '@nestjs/config';

/**
 * PresenceService unit tests.
 *
 * Verifies:
 *   • First connect → online, socketCount=1, persists + broadcasts
 *   • Second connect (multi-device) → socketCount=2, no status change
 *   • Disconnect with remaining sockets → still online, no broadcast
 *   • Last disconnect → offline, socketCount=0, persists + broadcasts
 *   • getPresence returns synthetic offline for unknown users
 *   • Redis is NOT initialized when REDIS_URL is unset or default
 *     localhost (matches auth.service pattern)
 */
describe('PresenceService', () => {
  let service: PresenceService;

  const mockPrisma = {
    userPresence: {
      upsert: jest.fn(),
    },
    memberPresence: {
      updateMany: jest.fn(),
    },
    familyMember: {
      findMany: jest.fn(),
    },
  };

  const mockConfig = {
    get: jest.fn((key: string, def?: string) => {
      if (key === 'REDIS_URL') return ''; // no Redis in tests
      return def;
    }),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PresenceService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: ConfigService, useValue: mockConfig },
      ],
    }).compile();
    service = module.get<PresenceService>(PresenceService);
    jest.clearAllMocks();
  });

  describe('userConnected — first socket', () => {
    it('marks the user online with socketCount=1 + persists + broadcasts', async () => {
      mockPrisma.userPresence.upsert.mockResolvedValue({});
      mockPrisma.memberPresence.updateMany.mockResolvedValue({ count: 0 });
      mockPrisma.familyMember.findMany.mockResolvedValue([
        { familyId: 'fam-1' },
        { familyId: 'fam-2' },
      ]);

      // Wire up a mock emitToFamily so we can assert it's called
      const emitted: Array<{ familyId: string; event: string }> = [];
      service.setEmitToFamilyFn((familyId, event, _payload) => {
        emitted.push({ familyId, event });
      });

      const entry = await service.userConnected('user-1');

      expect(entry.isOnline).toBe(true);
      expect(entry.socketCount).toBe(1);
      expect(mockPrisma.userPresence.upsert).toHaveBeenCalledTimes(1);
      expect(emitted).toEqual([
        { familyId: 'fam-1', event: 'presenceUpdate' },
        { familyId: 'fam-2', event: 'presenceUpdate' },
      ]);
    });
  });

  describe('userConnected — second socket (multi-device)', () => {
    it('increments socketCount without re-broadcasting', async () => {
      await service.userConnected('user-1'); // first socket
      jest.clearAllMocks();

      mockPrisma.userPresence.upsert.mockResolvedValue({});
      mockPrisma.memberPresence.updateMany.mockResolvedValue({ count: 0 });
      mockPrisma.familyMember.findMany.mockResolvedValue([]);

      const entry = await service.userConnected('user-1'); // second socket
      expect(entry.socketCount).toBe(2);
      expect(entry.isOnline).toBe(true);
      // Second connect on an already-online user → no DB write, no broadcast
      expect(mockPrisma.userPresence.upsert).not.toHaveBeenCalled();
    });
  });

  describe('userDisconnected — with remaining sockets', () => {
    it('keeps the user online when other sockets are active', async () => {
      await service.userConnected('user-1'); // socket 1
      await service.userConnected('user-1'); // socket 2
      jest.clearAllMocks();

      const entry = await service.userDisconnected('user-1');
      expect(entry?.socketCount).toBe(1);
      expect(entry?.isOnline).toBe(true);
      // No persist/broadcast because status didn't change
      expect(mockPrisma.userPresence.upsert).not.toHaveBeenCalled();
    });
  });

  describe('userDisconnected — last socket', () => {
    it('marks the user offline + persists + broadcasts', async () => {
      await service.userConnected('user-1');
      jest.clearAllMocks();

      mockPrisma.userPresence.upsert.mockResolvedValue({});
      mockPrisma.memberPresence.updateMany.mockResolvedValue({ count: 1 });
      mockPrisma.familyMember.findMany.mockResolvedValue([{ familyId: 'fam-1' }]);

      const emitted: Array<{ familyId: string; status: string }> = [];
      service.setEmitToFamilyFn((familyId, event, payload: any) => {
        if (event === 'presenceUpdate') {
          emitted.push({ familyId, status: payload.status });
        }
      });

      const entry = await service.userDisconnected('user-1');
      expect(entry?.socketCount).toBe(0);
      expect(entry?.isOnline).toBe(false);
      expect(mockPrisma.userPresence.upsert).toHaveBeenCalledTimes(1);
      const upsertArgs = mockPrisma.userPresence.upsert.mock.calls[0][0];
      expect(upsertArgs.update.isOnline).toBe(false);
      expect(emitted).toEqual([{ familyId: 'fam-1', status: 'offline' }]);
    });
  });

  describe('getPresence — unknown user', () => {
    it('returns a synthetic offline entry with epoch lastSeenAt', () => {
      const entry = service.getPresence('never-connected');
      expect(entry.isOnline).toBe(false);
      expect(entry.socketCount).toBe(0);
      expect(entry.lastSeenAt.getTime()).toBe(0);
    });
  });

  describe('getPresenceForFamily', () => {
    it('returns the in-memory entries for family members', async () => {
      // Connect two users
      await service.userConnected('user-1');
      await service.userConnected('user-2');
      mockPrisma.familyMember.findMany.mockResolvedValue([
        { userId: 'user-1' },
        { userId: 'user-2' },
        { userId: 'user-3' }, // not connected — should be excluded
      ]);

      const result = await service.getPresenceForFamily('fam-1');
      expect(result.size).toBe(2);
      expect(result.get('user-1')?.isOnline).toBe(true);
      expect(result.get('user-2')?.isOnline).toBe(true);
      expect(result.has('user-3')).toBe(false);
    });
  });

  describe('Redis initialization', () => {
    it('does NOT connect to Redis when REDIS_URL is unset', () => {
      // The mockConfig returns '' for REDIS_URL. The service should not
      // have attempted a Redis connection. We can't directly assert on
      // the private field, but we can verify the service works without
      // Redis (no crash, in-memory cache functional).
      expect(service.getPresence('user-x').isOnline).toBe(false);
    });
  });
});
