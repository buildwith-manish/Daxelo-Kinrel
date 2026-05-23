import { Module } from '@nestjs/common';
import { DeveloperController } from './developer.controller';
import { WebhookController } from './webhook.controller';
import { DeveloperService } from './developer.service';

@Module({
  controllers: [DeveloperController, WebhookController],
  providers: [DeveloperService],
  exports: [DeveloperService],
})
export class DeveloperModule {}
