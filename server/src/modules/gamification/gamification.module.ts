import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { GamificationController } from './gamification.controller';
import { GamificationService } from './gamification.service';
import { KinshipModule } from '../kinship/kinship.module';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [KinshipModule, PrismaModule, ConfigModule],
  controllers: [GamificationController],
  providers: [GamificationService],
  exports: [GamificationService],
})
export class GamificationModule {}
