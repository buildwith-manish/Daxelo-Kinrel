import { Module } from '@nestjs/common';
import { KnowledgeBaseController, AdminKBController, AdminSlaController } from './knowledge-base.controller';
import { KnowledgeBaseService } from './knowledge-base.service';

@Module({
  controllers: [KnowledgeBaseController, AdminKBController, AdminSlaController],
  providers: [KnowledgeBaseService],
  exports: [KnowledgeBaseService],
})
export class KnowledgeBaseModule {}
