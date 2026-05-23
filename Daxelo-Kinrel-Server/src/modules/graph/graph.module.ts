import { Module } from '@nestjs/common';
import { GraphService } from './graph.service';
import {
  GraphController,
  GraphTreeController,
  GraphPathController,
} from './graph.controller';
import { KinshipModule } from '@/modules/kinship/kinship.module';

@Module({
  imports: [KinshipModule],
  controllers: [GraphController, GraphTreeController, GraphPathController],
  providers: [GraphService],
  exports: [GraphService],
})
export class GraphModule {}
