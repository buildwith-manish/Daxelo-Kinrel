import { Module } from '@nestjs/common';
import { PrismaModule } from '../../prisma/prisma.module';
import { ConfigModule } from '@nestjs/config';
import { SparqController } from './sparq.controller';
import { SparqService } from './sparq.service';

@Module({
  imports: [PrismaModule, ConfigModule],
  controllers: [SparqController],
  providers: [SparqService],
  exports: [SparqService],
})
export class SparqModule {}
