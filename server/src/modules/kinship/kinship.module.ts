import { Module } from '@nestjs/common';
import { KinshipController } from './kinship.controller';
import { KinshipService } from './kinship.service';
import { GraphModule } from '../graph/graph.module';

@Module({
  imports: [GraphModule],
  controllers: [KinshipController],
  providers: [KinshipService],
  exports: [KinshipService],
})
export class KinshipModule {}
