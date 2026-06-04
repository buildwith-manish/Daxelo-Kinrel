import {
  Controller,
  Post,
  Get,
  Delete,
  Body,
  Query,
  Param,
  Req,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { IsEmail, IsString, MinLength, IsNotEmpty, IsOptional } from 'class-validator';
import { AuthService } from './auth.service';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Public } from '../../common/decorators/public.decorator';
import { TwoFactorExempt } from '../../common/decorators/two-factor-exempt.decorator';
import type { Request } from 'express';

// ── DTOs with proper validation ──────────────────────────────────────

class RegisterDto {
  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(8)
  password!: string;
}

class LoginDto {
  @IsEmail()
  email!: string;

  @IsString()
  @IsNotEmpty()
  password!: string;
}

class RefreshDto {
  @IsString()
  @IsNotEmpty()
  refreshToken!: string;
}

class ChangePasswordDto {
  @IsString()
  @IsNotEmpty()
  currentPassword!: string;

  @IsString()
  @MinLength(8)
  newPassword!: string;
}

class Verify2FADto {
  @IsString()
  @IsNotEmpty()
  code!: string;
}

class Disable2FADto {
  @IsString()
  @IsNotEmpty()
  password!: string;
}

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // ── Register ──────────────────────────────────────────────────────
  @Public()
  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  async register(@Body() dto: RegisterDto) {
    return this.authService.register(dto);
  }

  // ── Login ─────────────────────────────────────────────────────────
  @Public()
  @Post('login')
  @HttpCode(HttpStatus.OK)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  async login(@Body() dto: LoginDto, @Req() req: Request) {
    const userAgent = req.headers['user-agent'] || '';
    const ipAddress = req.ip || req.socket.remoteAddress || '';
    return this.authService.login(dto, userAgent, ipAddress);
  }

  // ── Refresh ───────────────────────────────────────────────────────
  @Public()
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  async refresh(@Body() dto: RefreshDto) {
    return this.authService.refresh(dto.refreshToken);
  }

  // ── Logout ────────────────────────────────────────────────────────
  @Public()
  @Post('logout')
  @HttpCode(HttpStatus.OK)
  async logout(@Body() dto: RefreshDto) {
    return this.authService.logout(dto.refreshToken);
  }

  // ── Change Password (requires JWT) ────────────────────────────────
  @Post('change-password')
  @HttpCode(HttpStatus.OK)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  async changePassword(
    @CurrentUser('id') userId: string,
    @Body() dto: ChangePasswordDto,
  ) {
    return this.authService.changePassword(userId, dto);
  }

  // ── 2FA Setup (requires JWT, exempt from 2FA check) ───────────────
  @TwoFactorExempt()
  @Post('2fa/setup')
  @HttpCode(HttpStatus.OK)
  async setup2FA(@CurrentUser('id') userId: string) {
    return this.authService.setup2FA(userId);
  }

  // ── 2FA Verify (requires JWT, exempt from 2FA check) ──────────────
  @TwoFactorExempt()
  @Post('2fa/verify')
  @HttpCode(HttpStatus.OK)
  async verify2FA(
    @CurrentUser('id') userId: string,
    @Body() dto: Verify2FADto,
  ) {
    return this.authService.verify2FA(userId, dto.code);
  }

  // ── 2FA Login Verify (requires JWT, exempt from 2FA check) ────────
  @TwoFactorExempt()
  @Post('2fa/login-verify')
  @HttpCode(HttpStatus.OK)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  async loginVerify2FA(
    @CurrentUser('id') userId: string,
    @Body() dto: Verify2FADto,
  ) {
    return this.authService.loginVerify2FA(userId, dto.code);
  }

  // ── 2FA Disable (requires JWT) ────────────────────────────────────
  @Delete('2fa')
  @HttpCode(HttpStatus.OK)
  async disable2FA(
    @CurrentUser('id') userId: string,
    @Body() dto: Disable2FADto,
  ) {
    return this.authService.disable2FA(userId, dto.password);
  }

  // ── Get Current User (requires JWT, exempt from 2FA check) ────────
  @TwoFactorExempt()
  @Get('me')
  async me(@CurrentUser('id') userId: string) {
    return this.authService.me(userId);
  }

  // ── Get Active Sessions (requires JWT) ────────────────────────────
  @Get('sessions')
  async getSessions(
    @CurrentUser('id') userId: string,
    @Query('refreshToken') refreshToken?: string,
  ) {
    return this.authService.getUserSessions(userId, refreshToken);
  }

  // ── Revoke a Specific Session ─────────────────────────────────────
  @Delete('sessions/:sessionId')
  @HttpCode(HttpStatus.OK)
  async revokeSession(
    @CurrentUser('id') userId: string,
    @Param('sessionId') sessionId: string,
  ) {
    return this.authService.revokeSession(sessionId, userId);
  }

  // ── Revoke All Sessions Except Current ────────────────────────────
  @Delete('sessions/all-except-current')
  @HttpCode(HttpStatus.OK)
  async revokeAllSessionsExceptCurrent(
    @CurrentUser('id') userId: string,
    @Query('refreshToken') refreshToken?: string,
  ) {
    return this.authService.revokeAllSessionsExceptCurrent(userId, refreshToken);
  }
}
