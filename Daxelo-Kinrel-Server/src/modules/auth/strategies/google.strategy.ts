import { Injectable, Logger } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { Strategy, VerifyCallback } from 'passport-google-oauth20';
import { ConfigService } from '@nestjs/config';

export interface GoogleProfile {
  id: string;
  email: string;
  name?: string;
  firstName?: string;
  lastName?: string;
  picture?: string;
  googleId: string;
}

@Injectable()
export class GoogleStrategy extends PassportStrategy(Strategy, 'google') {
  private readonly logger = new Logger(GoogleStrategy.name);

  constructor(config: ConfigService) {
    super({
      clientID: config.get<string>('GOOGLE_CLIENT_ID') ?? '',
      clientSecret: config.get<string>('GOOGLE_CLIENT_SECRET') ?? '',
      callbackURL: config.get<string>('GOOGLE_CALLBACK_URL') ?? '',
      scope: ['email', 'profile'],
      passReqToCallback: false,
    });
  }

  async validate(
    accessToken: string,
    refreshToken: string,
    profile: any,
    done: VerifyCallback,
  ): Promise<void> {
    try {
      const { id, name, emails, photos } = profile;

      const email = emails?.[0]?.value;
      if (!email) {
        return done(new Error('No email found in Google profile'), undefined);
      }

      const googleProfile: GoogleProfile = {
        id,
        email,
        name: name
          ? `${name.givenName ?? ''} ${name.familyName ?? ''}`.trim()
          : undefined,
        firstName: name?.givenName,
        lastName: name?.familyName,
        picture: photos?.[0]?.value,
        googleId: id,
      };

      this.logger.log(`Google OAuth validated for: ${email}`);

      // Pass the profile to the controller via done()
      // The controller will call authService.validateOAuthUser()
      done(null, googleProfile);
    } catch (error) {
      this.logger.error('Google OAuth validation failed', error);
      done(error as Error, undefined);
    }
  }
}
