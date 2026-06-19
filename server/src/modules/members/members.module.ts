import { Module, forwardRef } from '@nestjs/common';
import { MembersController } from './members.controller';
import { MembersService } from './members.service';
import { GatewayModule } from '../gateway/gateway.module';
import { ConfigModule } from '@nestjs/config';
import { GraphModule } from '../graph/graph.module';

@Module({
  imports: [GatewayModule, ConfigModule, forwardRef(() => GraphModule)],
  controllers: [MembersController],
  providers: [MembersService],
  exports: [MembersService],
})
export class MembersModule {}
