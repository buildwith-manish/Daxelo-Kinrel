import { Module } from '@nestjs/common';
import { GraphController } from './graph.controller';
import { GraphService } from './graph.service';
import { GraphEngineService } from './graph-engine.service';
import { RelationshipsModule } from '../relationships/relationships.module';

@Module({
  imports: [RelationshipsModule],
  controllers: [GraphController],
  providers: [GraphService, GraphEngineService],
  exports: [GraphService, GraphEngineService],
})
export class GraphModule {}
