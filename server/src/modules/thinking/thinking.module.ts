import { Module } from '@nestjs/common';
import { ThinkingController } from './thinking.controller';
import { ThinkingService } from './thinking.service';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule],
  controllers: [ThinkingController],
  providers: [ThinkingService],
  exports: [ThinkingService],
})
export class ThinkingModule {}
