import { Module } from '@nestjs/common';
import { KinshipController } from './kinship.controller';
import { KinshipService } from './kinship.service';
import { GraphModule } from '../graph/graph.module';
import { CanonicalIdService } from './canonical-id.service';
import { RelationshipNormalizerService } from './relationship-normalizer.service';

@Module({
  imports: [GraphModule],
  controllers: [KinshipController],
  providers: [
    KinshipService,
    CanonicalIdService,
    RelationshipNormalizerService,
  ],
  exports: [
    KinshipService,
    CanonicalIdService,
    RelationshipNormalizerService,
  ],
})
export class KinshipModule {}
