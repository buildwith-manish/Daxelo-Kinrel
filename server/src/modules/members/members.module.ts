import { Module } from '@nestjs/common';
import { MembersController } from './members.controller';
import { MembersService } from './members.service';
import { GatewayModule } from '../gateway/gateway.module';
import { ConfigModule } from '@nestjs/config';

@Module({
  imports: [GatewayModule, ConfigModule],
  controllers: [MembersController],
  providers: [MembersService],
  exports: [MembersService],
})
export class MembersModule {}
