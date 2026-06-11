import { Module, forwardRef } from '@nestjs/common';
import { GraphController } from './graph.controller';
import { GraphService } from './graph.service';
import { GraphEngineService } from './graph-engine.service';

@Module({
  imports: [],
  controllers: [GraphController],
  providers: [GraphService, GraphEngineService],
  exports: [GraphService, GraphEngineService],
})
export class GraphModule {}
