// server/src/modules/predictions/predictions.module.spec.ts
//
// Smoke test — verifies that the PredictionsModule can be instantiated
// and that Nest's DI graph resolves correctly. We mock the heavy
// dependencies (FcmService, NotificationsService, PrismaService) so the
// test doesn't need real Firebase or DB connections.

import { Test, TestingModule } from '@nestjs/testing';
import { ConfigModule } from '@nestjs/config';
import { PredictionsModule } from './predictions.module';
import { PredictionsScheduler } from './predictions.scheduler';
import { FcmService } from '../notifications/fcm.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../../prisma/prisma.service';

// Minimal mocks — only the methods the scheduler touches in the
// constructor + the cron entry path. The cron body is exercised in a
// separate test (predictions.scheduler.spec.ts covers pure helpers).
const mockFcm = { sendToUser: jest.fn().mockResolvedValue(true) };
const mockNotifications = { create: jest.fn().mockResolvedValue({}) };
const mockPrisma = {
  familyMember: { findMany: jest.fn().mockResolvedValue([]) },
  notification: {
    findFirst: jest.fn().mockResolvedValue(null),
    findMany: jest.fn().mockResolvedValue([]),
    deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
  },
};

describe('PredictionsModule', () => {
  let module: TestingModule;
  let scheduler: PredictionsScheduler;

  beforeAll(async () => {
    module = await Test.createTestingModule({
      imports: [
        ConfigModule.forRoot({ isGlobal: false }),
        PredictionsModule,
      ],
    })
      .overrideProvider(FcmService)
      .useValue(mockFcm)
      .overrideProvider(NotificationsService)
      .useValue(mockNotifications)
      .overrideProvider(PrismaService)
      .useValue(mockPrisma)
      .compile();

    scheduler = module.get<PredictionsScheduler>(PredictionsScheduler);
  });

  afterAll(async () => {
    if (module) await module.close();
  });

  it('should instantiate the scheduler without throwing', () => {
    expect(scheduler).toBeDefined();
    expect(scheduler).toBeInstanceOf(PredictionsScheduler);
  });

  it('handlePredictionNotifications should be a no-op when supabase is not configured', async () => {
    // SUPABASE_URL is not set in the test env, so the scheduler
    // should bail early without throwing.
    await expect(scheduler.handlePredictionNotifications()).resolves.toBeUndefined();
  });

  it('backfill should be a no-op when supabase is not configured', async () => {
    // Same: SUPABASE_URL is not set in test env. Backfill should bail
    // early without throwing — and critically, without blocking. The
    // OnModuleInit hook fires backfill as fire-and-forget; if it threw,
    // the unhandled rejection would log noise but not crash the app.
    await expect(scheduler.backfill(24)).resolves.toBeUndefined();
  });

  it('backfill should accept a custom hours parameter without throwing', async () => {
    // Even with supabase not configured, the parameter validation
    // should not throw — the function bails before validating the
    // numeric range (which is intentional; the admin controller does
    // the validation).
    await expect(scheduler.backfill(1)).resolves.toBeUndefined();
    await expect(scheduler.backfill(168)).resolves.toBeUndefined();
  });
});
