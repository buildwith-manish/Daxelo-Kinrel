import { Module } from '@nestjs/common';
import { KinshipController } from './kinship.controller';
import { KinshipService } from './kinship.service';
import { KinshipDataController } from './kinship-data.controller';

@Module({
  controllers: [KinshipController, KinshipDataController],
  providers: [KinshipService],
  exports: [KinshipService],
})
export class KinshipModule {}
