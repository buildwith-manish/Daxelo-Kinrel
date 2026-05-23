import {
  Module,
  OnModuleInit,
  OnModuleDestroy,
  Logger,
  Provider,
} from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './strategies/jwt.strategy';
import { GoogleStrategy } from './strategies/google.strategy';

/**
 * Conditionally provide GoogleStrategy only when OAuth credentials are configured.
 * This prevents the OAuth2Strategy from throwing "requires a clientID" at startup.
 * When credentials are missing, we provide a no-op placeholder to avoid DI errors.
 */
const googleStrategyProvider: Provider = {
  provide: GoogleStrategy,
  useFactory: (config: ConfigService) => {
    const clientId = config.get<string>('GOOGLE_CLIENT_ID');
    const clientSecret = config.get<string>('GOOGLE_CLIENT_SECRET');

    if (!clientId || !clientSecret) {
      // Google OAuth not configured — provide a no-op placeholder
      class NoOpGoogleStrategy {
        validate(): never {
          throw new Error('Google OAuth is not configured');
        }
      }
      return new NoOpGoogleStrategy() as unknown as GoogleStrategy;
    }

    return new GoogleStrategy(config);
  },
  inject: [ConfigService],
};

@Module({
  imports: [
    PassportModule.register({ defaultStrategy: 'jwt' }),
    JwtModule.registerAsync({
      imports: [ConfigModule],
      useFactory: (config: ConfigService) => ({
        secret: config.get<string>('JWT_ACCESS_SECRET') ?? 'fallback-dev-secret',
        signOptions: {
          expiresIn: config.get<string>('JWT_ACCESS_EXPIRATION', '15m') as any,
        },
      }),
      inject: [ConfigService],
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy, googleStrategyProvider],
  exports: [AuthService, JwtModule],
})
export class AuthModule implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(AuthModule.name);
  private cleanupInterval?: ReturnType<typeof setInterval>;

  constructor(private readonly authService: AuthService) {}

  onModuleInit() {
    // Periodically clean up expired refresh tokens (every 1 hour)
    this.cleanupInterval = setInterval(
      () => {
        this.authService.cleanupExpiredTokens();
      },
      60 * 60 * 1000,
    );

    this.logger.log('AuthModule initialized — refresh token cleanup scheduled');
  }

  onModuleDestroy() {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
    }
    this.logger.log('AuthModule destroyed — cleanup interval cleared');
  }
}
