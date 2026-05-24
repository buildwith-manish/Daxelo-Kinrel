import { Module } from '@nestjs/common';
import { AiCardsController } from './ai-cards.controller';
import { AiCardsService } from './ai-cards.service';
import { KinshipModule } from '../kinship/kinship.module';

@Module({
  imports: [KinshipModule],
  controllers: [AiCardsController],
  providers: [AiCardsService],
  exports: [AiCardsService],
})
export class AiCardsModule {}
