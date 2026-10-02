// server/src/modules/admin/admin.controller.spec.ts
//
// Unit tests for the admin controller, focused on the
// /admin/predictions/backfill endpoint. We verify:
//   - non-admin users are rejected with ForbiddenException
//   - invalid `hours` query param (non-numeric, <1, >168) returns a
//     validation error
//   - valid call delegates to PredictionsScheduler.backfill with the
//     parsed hours value
//
// We don't test the full Nest boot — just the controller method with
// mocked dependencies.

import { Test, TestingModule } from '@nestjs/testing';
import { ForbiddenException } from '@nestjs/common';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { ChatAnalyticsService } from '../analytics/chat-analytics.service';
import { PredictionsScheduler } from '../predictions/predictions.scheduler';

describe('AdminController — /predictions/backfill', () => {
  let controller: AdminController;
  let predictionsScheduler: { backfill: jest.Mock };

  beforeAll(async () => {
    predictionsScheduler = { backfill: jest.fn().mockResolvedValue(undefined) };

    const module: TestingModule = await Test.createTestingModule({
      controllers: [AdminController],
      providers: [
        { provide: AdminService, useValue: {} },
        { provide: ChatAnalyticsService, useValue: {} },
        { provide: PredictionsScheduler, useValue: predictionsScheduler },
      ],
    }).compile();

    controller = module.get<AdminController>(AdminController);
  });

  afterEach(() => {
    predictionsScheduler.backfill.mockClear();
  });

  it('rejects non-admin users with ForbiddenException', async () => {
    // The controller checks `role !== 'admin'` BEFORE validating hours.
    // We expect a ForbiddenException, NOT a return value.
    await expect(
      controller.backfillPredictions('user' /* role */, '24'),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(predictionsScheduler.backfill).not.toHaveBeenCalled();
  });

  it('rejects empty hours query', async () => {
    const result = await controller.backfillPredictions('admin', '');
    expect(result).toEqual({
      ok: false,
      error: 'hours must be an integer between 1 and 168',
    });
    expect(predictionsScheduler.backfill).not.toHaveBeenCalled();
  });

  it('rejects non-numeric hours', async () => {
    const result = await controller.backfillPredictions('admin', 'abc');
    expect(result).toEqual({
      ok: false,
      error: 'hours must be an integer between 1 and 168',
    });
    expect(predictionsScheduler.backfill).not.toHaveBeenCalled();
  });

  it('rejects hours < 1', async () => {
    const result = await controller.backfillPredictions('admin', '0');
    expect(result).toEqual({
      ok: false,
      error: 'hours must be an integer between 1 and 168',
    });
    expect(predictionsScheduler.backfill).not.toHaveBeenCalled();
  });

  it('rejects hours > 168', async () => {
    const result = await controller.backfillPredictions('admin', '169');
    expect(result).toEqual({
      ok: false,
      error: 'hours must be an integer between 1 and 168',
    });
    expect(predictionsScheduler.backfill).not.toHaveBeenCalled();
  });

  it('accepts hours = 1 (minimum valid)', async () => {
    const result = await controller.backfillPredictions('admin', '1');
    expect(result).toEqual({ ok: true, hours: 1 });
    expect(predictionsScheduler.backfill).toHaveBeenCalledWith(1);
  });

  it('accepts hours = 168 (maximum valid = 7 days)', async () => {
    const result = await controller.backfillPredictions('admin', '168');
    expect(result).toEqual({ ok: true, hours: 168 });
    expect(predictionsScheduler.backfill).toHaveBeenCalledWith(168);
  });

  it('defaults to 24h when hours is undefined', async () => {
    const result = await controller.backfillPredictions('admin', undefined);
    expect(result).toEqual({ ok: true, hours: 24 });
    expect(predictionsScheduler.backfill).toHaveBeenCalledWith(24);
  });

  it('accepts a typical "catch up after deploy" call (hours=6)', async () => {
    const result = await controller.backfillPredictions('admin', '6');
    expect(result).toEqual({ ok: true, hours: 6 });
    expect(predictionsScheduler.backfill).toHaveBeenCalledWith(6);
  });
});
