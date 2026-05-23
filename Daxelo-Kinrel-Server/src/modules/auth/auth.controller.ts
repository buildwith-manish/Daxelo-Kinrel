import {
  Controller,
  Post,
  Get,
  Body,
  UseGuards,
  Req,
  Res,
  HttpCode,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { AuthGuard } from '@nestjs/passport';
import { AuthService } from './auth.service';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';
import { JwtAuthGuard } from '@/common/guards/jwt-auth.guard';
import { CurrentUser } from '@/common/decorators/current-user.decorator';
import { GoogleProfile } from './strategies/google.strategy';
import { ConfigService } from '@nestjs/config';

@Controller('auth')
export class AuthController {
  private readonly logger = new Logger(AuthController.name);

  constructor(
    private readonly authService: AuthService,
    private readonly config: ConfigService,
  ) {}

  // ── POST /api/auth/register ─────────────────────────────────────
  /**
   * Register a new user.
   * Body: { name, email, password }
   * Response: { user: { id, email, name }, familyId } (201)
   */
  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  async register(@Body() dto: RegisterDto) {
    return this.authService.register(dto);
  }

  // ── POST /api/auth/login ────────────────────────────────────────
  /**
   * Login with email and password.
   * Body: { email, password }
   * Response: { accessToken, refreshToken, user: { id, email, name, role, preferredLanguage } }
   */
  @Post('login')
  @HttpCode(HttpStatus.OK)
  async login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  // ── POST /api/auth/refresh ──────────────────────────────────────
  /**
   * Refresh JWT token pair.
   * Body: { refreshToken }
   * Response: { accessToken, refreshToken }
   */
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  async refresh(@Body() dto: RefreshTokenDto) {
    return this.authService.refresh(dto.refreshToken);
  }

  // ── POST /api/auth/logout ───────────────────────────────────────
  /**
   * Logout — invalidate refresh token.
   * Body: { refreshToken }
   * Response: { success: true }
   */
  @Post('logout')
  @HttpCode(HttpStatus.OK)
  async logout(@Body() dto: RefreshTokenDto) {
    return this.authService.logout(dto.refreshToken);
  }

  // ── GET /api/auth/google ────────────────────────────────────────
  /**
   * Initiates Google OAuth flow — redirects to Google consent screen.
   * Only works when GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET are configured.
   */
  @Get('google')
  @UseGuards(AuthGuard('google'))
  googleAuth() {
    // Guard handles the redirect to Google automatically
  }

  // ── GET /api/auth/google/callback ───────────────────────────────
  /**
   * Google redirects back here after user consents.
   * Creates/finds user, then redirects to frontend with tokens.
   */
  @Get('google/callback')
  @UseGuards(AuthGuard('google'))
  async googleCallback(@Req() req: Request, @Res() res: Response) {
    try {
      const googleProfile = req.user as GoogleProfile;
      const result = await this.authService.validateOAuthUser(googleProfile);

      // Redirect to frontend with tokens in query params
      const frontendUrl =
        this.config.get<string>('FRONTEND_URL') ?? 'http://localhost:3000';

      const redirectUrl = new URL('/auth/callback', frontendUrl);
      redirectUrl.searchParams.set('accessToken', result.accessToken);
      redirectUrl.searchParams.set('refreshToken', result.refreshToken);
      redirectUrl.searchParams.set('userId', result.user.id);
      redirectUrl.searchParams.set('email', result.user.email);
      redirectUrl.searchParams.set('name', result.user.name ?? '');

      return res.redirect(redirectUrl.toString());
    } catch (error) {
      this.logger.error('Google OAuth callback failed', error);

      const frontendUrl =
        this.config.get<string>('FRONTEND_URL') ?? 'http://localhost:3000';
      const redirectUrl = new URL('/sign-in', frontendUrl);
      redirectUrl.searchParams.set('error', 'oauth_failed');

      return res.redirect(redirectUrl.toString());
    }
  }

  // ── GET /api/auth/me ────────────────────────────────────────────
  /**
   * Get current authenticated user profile (JWT protected).
   * Response: { user: { id, email, name, phone, preferredLanguage, role, createdAt, updatedAt } }
   */
  @Get('me')
  @UseGuards(JwtAuthGuard)
  async me(@CurrentUser('id') userId: string) {
    return this.authService.me(userId);
  }
}
