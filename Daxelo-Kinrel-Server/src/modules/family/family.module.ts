import { Module } from '@nestjs/common';
import { FamilyService } from './family.service';
import { FamilyController } from './family.controller';
import { FamilyV1Controller } from './family-v1.controller';
import { PersonController } from './person.controller';
import { PersonV1Controller } from './person-v1.controller';
import { RelationshipController } from './relationship.controller';
import { RelationshipV1Controller } from './relationship-v1.controller';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [AuthModule],
  controllers: [
    FamilyController,
    FamilyV1Controller,
    PersonController,
    PersonV1Controller,
    RelationshipController,
    RelationshipV1Controller,
  ],
  providers: [FamilyService],
  exports: [FamilyService],
})
export class FamilyModule {}
