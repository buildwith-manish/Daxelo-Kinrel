import {
  Controller,
  Post,
  Get,
  Delete,
  Body,
  Query,
  Param,
  Req,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { Request } from 'express';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // ── Register ──────────────────────────────────────────────────────
  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  async register(
    @Body() body: { name: string; email: string; password: string },
  ) {
    return this.authService.register(body);
  }

  // ── Login ─────────────────────────────────────────────────────────
  @Post('login')
  @HttpCode(HttpStatus.OK)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  async login(
    @Body() body: { email: string; password: string },
    @Req() req: Request,
  ) {
    const userAgent = req.headers['user-agent'] || '';
    const ipAddress = req.ip || req.socket.remoteAddress || '';
    return this.authService.login(body, userAgent, ipAddress);
  }

  // ── Refresh ───────────────────────────────────────────────────────
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  async refresh(@Body() body: { refreshToken: string }) {
    return this.authService.refresh(body.refreshToken);
  }

  // ── Logout ────────────────────────────────────────────────────────
  @Post('logout')
  @HttpCode(HttpStatus.OK)
  async logout(@Body() body: { refreshToken: string }) {
    return this.authService.logout(body.refreshToken);
  }

  // ── Change Password (requires JWT) ────────────────────────────────
  @Post('change-password')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  async changePassword(
    @CurrentUser('id') userId: string,
    @Body() body: { currentPassword: string; newPassword: string },
  ) {
    return this.authService.changePassword(userId, body);
  }

  // ── 2FA Setup (requires JWT) ──────────────────────────────────────
  @Post('2fa/setup')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async setup2FA(@CurrentUser('id') userId: string) {
    return this.authService.setup2FA(userId);
  }

  // ── 2FA Verify (requires JWT) ─────────────────────────────────────
  @Post('2fa/verify')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async verify2FA(
    @CurrentUser('id') userId: string,
    @Body() body: { code: string },
  ) {
    return this.authService.verify2FA(userId, body.code);
  }

  // ── 2FA Disable (requires JWT) ────────────────────────────────────
  @Delete('2fa')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async disable2FA(
    @CurrentUser('id') userId: string,
    @Body() body: { password: string },
  ) {
    return this.authService.disable2FA(userId, body.password);
  }

  // ── Get Current User (requires JWT) ───────────────────────────────
  @Get('me')
  @UseGuards(JwtAuthGuard)
  async me(@CurrentUser('id') userId: string) {
    return this.authService.me(userId);
  }

  // ── Get Active Sessions (requires JWT) ────────────────────────────
  @Get('sessions')
  @UseGuards(JwtAuthGuard)
  async getSessions(
    @CurrentUser('id') userId: string,
    @Query('refreshToken') refreshToken?: string,
  ) {
    return this.authService.getUserSessions(userId, refreshToken);
  }

  // ── Revoke a Specific Session ─────────────────────────────────────
  @Delete('sessions/:sessionId')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async revokeSession(
    @CurrentUser('id') userId: string,
    @Param('sessionId') sessionId: string,
  ) {
    return this.authService.revokeSession(sessionId, userId);
  }

  // ── Revoke All Sessions Except Current ────────────────────────────
  @Delete('sessions/all-except-current')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async revokeAllSessionsExceptCurrent(
    @CurrentUser('id') userId: string,
    @Query('refreshToken') refreshToken?: string,
  ) {
    return this.authService.revokeAllSessionsExceptCurrent(userId, refreshToken);
  }
}
