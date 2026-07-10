import { Module } from '@nestjs/common';
import { ModerationController } from './moderation.controller';
import { ModerationService } from './moderation.service';
import { ModerationClassifier } from './moderation.classifier';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [PrismaModule],
  controllers: [ModerationController],
  providers: [ModerationService, ModerationClassifier],
  exports: [ModerationService, ModerationClassifier],
})
export class ModerationModule {}
