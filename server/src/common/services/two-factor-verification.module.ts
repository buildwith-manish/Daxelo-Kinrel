import { Global, Module } from '@nestjs/common';
import { TwoFactorVerificationService } from './two-factor-verification.service';

/**
 * TwoFactorVerificationModule — Global module that provides
 * the TwoFactorVerificationService to all other modules.
 *
 * Marked @Global() so it only needs to be imported once (in AppModule)
 * and the service will be available everywhere.
 */
@Global()
@Module({
  providers: [TwoFactorVerificationService],
  exports: [TwoFactorVerificationService],
})
export class TwoFactorVerificationModule {}
