import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { HealthController } from './health.controller';
import { PrismaModule } from '../prisma/prisma.module';

@Module({
  imports: [PrismaModule],
  controllers: [HealthController],
})
export class HealthModule {}
