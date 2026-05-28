import { Module } from '@nestjs/common';
import { RelationshipsController, RelationshipController } from './relationships.controller';
import { RelationshipsService } from './relationships.service';

@Module({
  controllers: [RelationshipsController, RelationshipController],
  providers: [RelationshipsService],
  exports: [RelationshipsService],
})
export class RelationshipsModule {}
