import { Module, forwardRef } from '@nestjs/common';
import { KinshipController } from './kinship.controller';
import { KinshipService } from './kinship.service';
import { GraphModule } from '../graph/graph.module';
import { CanonicalIdService } from './canonical-id.service';
import { RelationshipNormalizerService } from './relationship-normalizer.service';

// NOTE: GraphModule and KinshipModule form a circular dependency
// (GraphModule uses forwardRef(() => KinshipModule), and KinshipService
// injects GraphEngineService). Both sides MUST use forwardRef() — otherwise
// NestJS resolves the importing module before it's constructed and crashes
// at startup with "The module at index [0] of the KinshipModule 'imports'
// array is undefined" (UndefinedModuleException).
//
// Reproduction: any commit that drops forwardRef() here will fail to boot on
// Render — the runtime exits with code 1 and the health check never returns.
@Module({
  imports: [forwardRef(() => GraphModule)],
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
