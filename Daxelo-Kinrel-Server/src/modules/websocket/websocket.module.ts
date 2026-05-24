import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { WebSocketGatewayService } from './websocket.gateway';
import { WebSocketService } from './websocket.service';

@Module({
  imports: [
    JwtModule.registerAsync({
      imports: [ConfigModule],
      useFactory: (config: ConfigService) => ({
        secret: config.get<string>('JWT_ACCESS_SECRET') ?? 'fallback-dev-secret',
      }),
      inject: [ConfigService],
    }),
  ],
  providers: [WebSocketGatewayService, WebSocketService],
  exports: [WebSocketService, WebSocketGatewayService],
})
export class WebSocketModule {}
