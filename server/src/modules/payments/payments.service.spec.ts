import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { BadRequestException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { PaymentsService } from './payments.service';
import * as crypto from 'crypto';

// ── Mock PrismaService ─────────────────────────────────────────────────

const mockPrisma = {
  subscription: {
    upsert: jest.fn(),
    findUnique: jest.fn(),
    update: jest.fn(),
  },
};

// ── Mock ConfigService ─────────────────────────────────────────────────

const mockConfig = {
  get: jest.fn((key: string) => {
    switch (key) {
      case 'RAZORPAY_KEY_SECRET':
        return 'test-razorpay-secret';
      case 'NODE_ENV':
        return 'development';
      default:
        return undefined;
    }
  }),
};

// ── Test Suite ─────────────────────────────────────────────────────────

describe('PaymentsService', () => {
  let service: PaymentsService;

  beforeEach(async () => {
    jest.clearAllMocks();

    // Reset config mock to default implementation
    mockConfig.get.mockImplementation((key: string) => {
      switch (key) {
        case 'RAZORPAY_KEY_SECRET':
          return 'test-razorpay-secret';
        case 'NODE_ENV':
          return 'development';
        default:
          return undefined;
      }
    });

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PaymentsService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: ConfigService, useValue: mockConfig },
      ],
    }).compile();

    service = module.get<PaymentsService>(PaymentsService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ── createOrder() ──────────────────────────────────────────────────

  describe('createOrder', () => {
    it('should create an order with valid plan and amount', async () => {
      const result = await service.createOrder('user-1', 'pro_monthly', 299);

      expect(result).toEqual(
        expect.objectContaining({
          orderId: expect.stringMatching(/^order_[0-9a-f]{32}$/),
          amount: 299,
          currency: 'INR',
          plan: 'pro_monthly',
        }),
      );
    });

    it('should throw BadRequestException for invalid plan', async () => {
      await expect(
        service.createOrder('user-1', 'invalid_plan', 299),
      ).rejects.toThrow(BadRequestException);

      await expect(
        service.createOrder('user-1', 'invalid_plan', 299),
      ).rejects.toThrow('Invalid plan: invalid_plan');
    });

    it('should throw BadRequestException for invalid amount', async () => {
      await expect(
        service.createOrder('user-1', 'pro_monthly', 0),
      ).rejects.toThrow(BadRequestException);

      await expect(
        service.createOrder('user-1', 'pro_monthly', 0),
      ).rejects.toThrow('Amount must be a positive number');

      await expect(
        service.createOrder('user-1', 'pro_monthly', -100),
      ).rejects.toThrow(BadRequestException);

      // Also test undefined / falsy amount
      await expect(
        service.createOrder('user-1', 'pro_monthly', undefined as any),
      ).rejects.toThrow(BadRequestException);
    });
  });

  // ── verifyAndActivate() ────────────────────────────────────────────

  describe('verifyAndActivate', () => {
    const mockSubscription = {
      id: 'sub-1',
      userId: 'user-1',
      plan: 'pro_monthly',
      status: 'active',
      supportTier: 'standard',
      startDate: expect.any(Date),
    };

    it('should reject without signature in production mode', async () => {
      mockConfig.get.mockImplementation((key: string) => {
        switch (key) {
          case 'NODE_ENV':
            return 'production';
          case 'RAZORPAY_KEY_SECRET':
            return 'test-razorpay-secret';
          default:
            return undefined;
        }
      });

      await expect(
        service.verifyAndActivate('user-1', {}),
      ).rejects.toThrow(BadRequestException);

      await expect(
        service.verifyAndActivate('user-1', {}),
      ).rejects.toThrow('Payment signature is required in production');
    });

    it('should allow without signature in development mode (with warning)', async () => {
      mockConfig.get.mockImplementation((key: string) => {
        switch (key) {
          case 'NODE_ENV':
            return 'development';
          case 'RAZORPAY_KEY_SECRET':
            return 'test-razorpay-secret';
          default:
            return undefined;
        }
      });

      mockPrisma.subscription.upsert.mockResolvedValue(mockSubscription);

      const result = await service.verifyAndActivate('user-1', {});

      expect(result).toEqual(mockSubscription);
      expect(mockPrisma.subscription.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { userId: 'user-1' },
        }),
      );
    });

    it('should activate subscription with valid Razorpay signature', async () => {
      const orderId = 'order_test123';
      const paymentId = 'pay_test456';
      const secret = 'test-razorpay-secret';
      const validSignature = crypto
        .createHmac('sha256', secret)
        .update(`${orderId}|${paymentId}`)
        .digest('hex');

      mockPrisma.subscription.upsert.mockResolvedValue(mockSubscription);

      const result = await service.verifyAndActivate('user-1', {
        razorpayOrderId: orderId,
        razorpayPaymentId: paymentId,
        razorpaySignature: validSignature,
        plan: 'pro_annual',
      });

      expect(result).toEqual(mockSubscription);
      expect(mockPrisma.subscription.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { userId: 'user-1' },
          update: expect.objectContaining({ plan: 'pro_annual', status: 'active' }),
          create: expect.objectContaining({ userId: 'user-1', plan: 'pro_annual', status: 'active' }),
        }),
      );
    });

    it('should throw BadRequestException for invalid Razorpay signature', async () => {
      // Must be 64 hex chars (same length as SHA-256 HMAC) for timingSafeEqual
      const invalidSignature = '0'.repeat(64);

      await expect(
        service.verifyAndActivate('user-1', {
          razorpayOrderId: 'order_test123',
          razorpayPaymentId: 'pay_test456',
          razorpaySignature: invalidSignature,
          plan: 'pro_monthly',
        }),
      ).rejects.toThrow(BadRequestException);
    });

    it('should throw BadRequestException if RAZORPAY_KEY_SECRET is missing', async () => {
      mockConfig.get.mockImplementation((key: string) => {
        switch (key) {
          case 'RAZORPAY_KEY_SECRET':
            return undefined; // Missing secret
          case 'NODE_ENV':
            return 'development';
          default:
            return undefined;
        }
      });

      await expect(
        service.verifyAndActivate('user-1', {
          razorpayOrderId: 'order_test123',
          razorpayPaymentId: 'pay_test456',
          razorpaySignature: 'some_signature',
        }),
      ).rejects.toThrow(BadRequestException);

      await expect(
        service.verifyAndActivate('user-1', {
          razorpayOrderId: 'order_test123',
          razorpayPaymentId: 'pay_test456',
          razorpaySignature: 'some_signature',
        }),
      ).rejects.toThrow('Payment verification is not configured');
    });

    it('should throw BadRequestException for invalid plan', async () => {
      mockPrisma.subscription.upsert.mockResolvedValue(mockSubscription);

      await expect(
        service.verifyAndActivate('user-1', {
          plan: 'nonexistent_plan',
        }),
      ).rejects.toThrow(BadRequestException);

      await expect(
        service.verifyAndActivate('user-1', {
          plan: 'nonexistent_plan',
        }),
      ).rejects.toThrow('Invalid plan: nonexistent_plan');
    });
  });

  // ── getSubscription() ──────────────────────────────────────────────

  describe('getSubscription', () => {
    it('should return subscription for user', async () => {
      const mockSub = {
        id: 'sub-1',
        userId: 'user-1',
        plan: 'pro_monthly',
        status: 'active',
      };
      mockPrisma.subscription.findUnique.mockResolvedValue(mockSub);

      const result = await service.getSubscription('user-1');

      expect(result).toEqual(mockSub);
      expect(mockPrisma.subscription.findUnique).toHaveBeenCalledWith({
        where: { userId: 'user-1' },
      });
    });

    it('should return null when no subscription exists', async () => {
      mockPrisma.subscription.findUnique.mockResolvedValue(null);

      const result = await service.getSubscription('user-1');

      expect(result).toBeNull();
    });
  });

  // ── cancelSubscription() ───────────────────────────────────────────

  describe('cancelSubscription', () => {
    it('should cancel subscription and set status to cancelled', async () => {
      const existingSub = {
        id: 'sub-1',
        userId: 'user-1',
        plan: 'pro_monthly',
        status: 'active',
      };
      const cancelledSub = {
        ...existingSub,
        status: 'cancelled',
      };

      mockPrisma.subscription.findUnique.mockResolvedValue(existingSub);
      mockPrisma.subscription.update.mockResolvedValue(cancelledSub);

      const result = await service.cancelSubscription('user-1');

      expect(result).toEqual(cancelledSub);
      expect(mockPrisma.subscription.update).toHaveBeenCalledWith({
        where: { userId: 'user-1' },
        data: { status: 'cancelled' },
      });
    });

    it('should throw NotFoundException when no subscription exists', async () => {
      mockPrisma.subscription.findUnique.mockResolvedValue(null);

      await expect(
        service.cancelSubscription('user-1'),
      ).rejects.toThrow(NotFoundException);

      await expect(
        service.cancelSubscription('user-1'),
      ).rejects.toThrow('No active subscription found');
    });
  });
});
