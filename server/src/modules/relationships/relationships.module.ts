import { Module, forwardRef } from '@nestjs/common';
import { RelationshipsController } from './relationships.controller';
import { RelationshipsService } from './relationships.service';
import { RelationshipValidator } from './relationship.validator';
import { GatewayModule } from '../gateway/gateway.module';
import { GraphModule } from '../graph/graph.module';
import { KinshipModule } from '../kinship/kinship.module';

@Module({
  // KinshipModule provides CanonicalIdService + RelationshipNormalizerService
  imports: [
    GatewayModule,
    forwardRef(() => GraphModule),
    forwardRef(() => KinshipModule),
  ],
  controllers: [RelationshipsController],
  providers: [RelationshipsService, RelationshipValidator],
  exports: [RelationshipsService, RelationshipValidator],
})
export class RelationshipsModule {}
