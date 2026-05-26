import { Module } from '@nestjs/common';
import { DeveloperController } from './developer.controller';
import { DeveloperService } from './developer.service';
import { ApiKeyGuard } from './guards/api-key.guard';

@Module({
  controllers: [DeveloperController],
  providers: [DeveloperService, ApiKeyGuard],
  exports: [DeveloperService, ApiKeyGuard],
})
export class DeveloperModule {}
