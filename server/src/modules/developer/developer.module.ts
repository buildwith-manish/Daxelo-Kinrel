import { Module } from '@nestjs/common';
import { DeveloperKeysController } from './developer-keys.controller';
import { WebhooksController } from './webhooks.controller';
import { DeveloperService } from './developer.service';

@Module({
  controllers: [DeveloperKeysController, WebhooksController],
  providers: [DeveloperService],
  exports: [DeveloperService],
})
export class DeveloperModule {}
