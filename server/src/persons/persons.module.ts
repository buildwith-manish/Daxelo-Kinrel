import { Module } from '@nestjs/common';
import { PersonsController, PersonController } from './persons.controller';
import { PersonsService } from './persons.service';

@Module({
  controllers: [PersonsController, PersonController],
  providers: [PersonsService],
  exports: [PersonsService],
})
export class PersonsModule {}
