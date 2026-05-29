import { Module } from '@nestjs/common';
import { AiChatController } from './ai-chat.controller';
import { AiChatService } from './ai-chat.service';
import { AiFeaturesController } from './ai-features.controller';
import { AiFeaturesService } from './ai-features.service';
import { KinshipModule } from '../kinship/kinship.module';
import { GraphModule } from '../graph/graph.module';
import { PrismaModule } from '../../prisma/prisma.module';

@Module({
  imports: [KinshipModule, GraphModule, PrismaModule],
  controllers: [AiChatController, AiFeaturesController],
  providers: [AiChatService, AiFeaturesService],
  exports: [AiChatService, AiFeaturesService],
})
export class AiChatModule {}
