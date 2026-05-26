import { Module } from '@nestjs/common';
import { GraphController } from './graph.controller';
import { GraphService } from './graph.service';
import { DualAuthGuard } from './dual-auth.guard';
import { KinshipModule } from '../kinship/kinship.module';
import { JwtModule } from '@nestjs/jwt';

@Module({
  imports: [
    KinshipModule,
    JwtModule.register({}), // needed for DualAuthGuard's JwtService
  ],
  controllers: [GraphController],
  providers: [GraphService, DualAuthGuard],
  exports: [GraphService],
})
export class GraphModule {}
