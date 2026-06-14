import { Module, forwardRef } from '@nestjs/common';
import { ProfileController } from './profile.controller';
import { ProfileService } from './profile.service';
import { GraphModule } from '../graph/graph.module';
import { KinshipModule } from '../kinship/kinship.module';
import { FamiliesModule } from '../families/families.module';

@Module({
  imports: [
    forwardRef(() => GraphModule),
    KinshipModule,
    FamiliesModule,
  ],
  controllers: [ProfileController],
  providers: [ProfileService],
  exports: [ProfileService],
})
export class ProfileModule {}
