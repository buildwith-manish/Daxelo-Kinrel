import { Module } from '@nestjs/common';
import { HealthController, RootController } from './health.controller';

@Module({
  controllers: [HealthController, RootController],
})
export class HealthModule {}
