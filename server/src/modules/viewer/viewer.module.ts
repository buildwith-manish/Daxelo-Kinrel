import { Module } from '@nestjs/common';
import { ViewerController } from './viewer.controller';
import { ViewerService } from './viewer.service';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule],
  controllers: [ViewerController],
  providers: [ViewerService],
  exports: [ViewerService],
})
export class ViewerModule {}
