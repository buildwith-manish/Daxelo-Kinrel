import { Module } from '@nestjs/common';
import { CircleController } from './circle.controller';
import { CircleService } from './circle.service';
import { CircleGateway } from './circle.gateway';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule],
  controllers: [CircleController],
  providers: [CircleService, CircleGateway],
  exports: [CircleService],
})
export class CircleModule {}
