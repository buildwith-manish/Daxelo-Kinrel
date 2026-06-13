import { Module, forwardRef } from '@nestjs/common';
import { GraphController } from './graph.controller';
import { GraphService } from './graph.service';
import { GraphEngineService } from './graph-engine.service';
import { KinshipModule } from '../kinship/kinship.module';

@Module({
  imports: [forwardRef(() => KinshipModule)],
  controllers: [GraphController],
  providers: [GraphService, GraphEngineService],
  exports: [GraphService, GraphEngineService],
})
export class GraphModule {}
