import { Module } from '@nestjs/common';
import { PrismaModule } from '../../prisma/prisma.module';
import { GatewayModule } from '../gateway/gateway.module';
import { FollowController } from './follow.controller';
import { FollowService } from './follow.service';

@Module({
  imports: [PrismaModule, GatewayModule],
  controllers: [FollowController],
  providers: [FollowService],
  exports: [FollowService],
})
export class FollowModule {}
