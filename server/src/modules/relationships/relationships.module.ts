import { Module, forwardRef } from '@nestjs/common';
import { RelationshipsController } from './relationships.controller';
import { RelationshipsService } from './relationships.service';
import { GatewayModule } from '../gateway/gateway.module';
import { GraphModule } from '../graph/graph.module';

@Module({
  imports: [GatewayModule, forwardRef(() => GraphModule)],
  controllers: [RelationshipsController],
  providers: [RelationshipsService],
  exports: [RelationshipsService],
})
export class RelationshipsModule {}
