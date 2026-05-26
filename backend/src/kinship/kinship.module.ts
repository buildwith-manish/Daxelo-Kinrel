import { Module } from '@nestjs/common';
import { KinshipController } from './kinship.controller';
import { KinshipService } from './kinship.service';
import { KinshipValidatorService } from './kinship-validator.service';

@Module({
  controllers: [KinshipController],
  providers: [KinshipService, KinshipValidatorService],
  exports: [KinshipService, KinshipValidatorService],
})
export class KinshipModule {}
