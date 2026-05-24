import { Module } from '@nestjs/common';
import { GraphService } from './graph.service';
import {
  GraphController,
  GraphTreeController,
  GraphPathController,
} from './graph.controller';
import { KinshipModule } from '@/modules/kinship/kinship.module';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [KinshipModule, AuthModule],
  controllers: [GraphController, GraphTreeController, GraphPathController],
  providers: [GraphService],
  exports: [GraphService],
})
export class GraphModule {}
