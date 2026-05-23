import { Module } from '@nestjs/common';
import { KinshipController } from './kinship.controller';
import { KinshipService } from './kinship.service';

@Module({
  controllers: [KinshipController],
  providers: [KinshipService],
  exports: [KinshipService],
})
export class KinshipModule {}
