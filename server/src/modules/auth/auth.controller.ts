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
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
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

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // ── Register ──────────────────────────────────────────────────────
  @Public()
  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  @ApiOperation({ summary: 'Register a new user account' })
  @ApiResponse({ status: HttpStatus.CREATED, description: 'User successfully registered' })
  @ApiResponse({ status: HttpStatus.CONFLICT, description: 'Email already exists' })
  async register(@Body() dto: RegisterDto) {
    return this.authService.register(dto);
  }

  // ── Login ─────────────────────────────────────────────────────────
  @Public()
  @Post('login')
  @HttpCode(HttpStatus.OK)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  @ApiOperation({ summary: 'Login with email and password' })
  @ApiResponse({ status: HttpStatus.OK, description: 'User successfully logged in' })
  @ApiResponse({ status: HttpStatus.UNAUTHORIZED, description: 'Invalid credentials' })
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
  @ApiOperation({ summary: 'Refresh access token using refresh token' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Access token refreshed successfully' })
  @ApiResponse({ status: HttpStatus.UNAUTHORIZED, description: 'Invalid or expired refresh token' })
  async refresh(@Body() dto: RefreshDto) {
    return this.authService.refresh(dto.refreshToken);
  }

  // ── Logout ────────────────────────────────────────────────────────
  @Public()
  @Post('logout')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Logout and revoke refresh token' })
  @ApiResponse({ status: HttpStatus.OK, description: 'User logged out successfully' })
  async logout(@Body() dto: RefreshDto) {
    return this.authService.logout(dto.refreshToken);
  }

  // ── Change Password (requires JWT) ────────────────────────────────
  @ApiBearerAuth()
  @Post('change-password')
  @HttpCode(HttpStatus.OK)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  @ApiOperation({ summary: 'Change user password' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Password changed successfully' })
  @ApiResponse({ status: HttpStatus.UNAUTHORIZED, description: 'Invalid current password' })
  async changePassword(
    @CurrentUser('id') userId: string,
    @Body() dto: ChangePasswordDto,
  ) {
    return this.authService.changePassword(userId, dto);
  }

  // ── 2FA Setup (requires JWT, exempt from 2FA check) ───────────────
  @ApiBearerAuth()
  @TwoFactorExempt()
  @Post('2fa/setup')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Set up 2FA for the current user' })
  @ApiResponse({ status: HttpStatus.OK, description: '2FA setup initiated, returns QR code and secret' })
  async setup2FA(@CurrentUser('id') userId: string) {
    return this.authService.setup2FA(userId);
  }

  // ── 2FA Verify (requires JWT, exempt from 2FA check) ──────────────
  @ApiBearerAuth()
  @TwoFactorExempt()
  @Post('2fa/verify')
  @HttpCode(HttpStatus.OK)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  @ApiOperation({ summary: 'Verify 2FA setup code' })
  @ApiResponse({ status: HttpStatus.OK, description: '2FA setup verified successfully' })
  @ApiResponse({ status: HttpStatus.BAD_REQUEST, description: 'Invalid 2FA code' })
  async verify2FA(
    @CurrentUser('id') userId: string,
    @Body() dto: Verify2FADto,
  ) {
    return this.authService.verify2FA(userId, dto.code);
  }

  // ── 2FA Login Verify (requires JWT, exempt from 2FA check) ────────
  @ApiBearerAuth()
  @TwoFactorExempt()
  @Post('2fa/login-verify')
  @HttpCode(HttpStatus.OK)
  @Throttle({ auth: { limit: 5, ttl: 60000 } })
  @ApiOperation({ summary: 'Verify 2FA code during login' })
  @ApiResponse({ status: HttpStatus.OK, description: '2FA login verified successfully' })
  @ApiResponse({ status: HttpStatus.UNAUTHORIZED, description: 'Invalid 2FA code' })
  async loginVerify2FA(
    @CurrentUser('id') userId: string,
    @Body() dto: Verify2FADto,
  ) {
    return this.authService.loginVerify2FA(userId, dto.code);
  }

  // ── 2FA Disable (requires JWT) ────────────────────────────────────
  @ApiBearerAuth()
  @Delete('2fa')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Disable 2FA for the current user' })
  @ApiResponse({ status: HttpStatus.OK, description: '2FA disabled successfully' })
  @ApiResponse({ status: HttpStatus.UNAUTHORIZED, description: 'Invalid password' })
  async disable2FA(
    @CurrentUser('id') userId: string,
    @Body() dto: Disable2FADto,
  ) {
    return this.authService.disable2FA(userId, dto.password);
  }

  // ── Get Current User (requires JWT, exempt from 2FA check) ────────
  @ApiBearerAuth()
  @TwoFactorExempt()
  @Get('me')
  @ApiOperation({ summary: 'Get current authenticated user profile' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns the current user profile' })
  async me(@CurrentUser('id') userId: string) {
    return this.authService.me(userId);
  }

  // ── Get Active Sessions (requires JWT) ────────────────────────────
  @ApiBearerAuth()
  @Get('sessions')
  @ApiOperation({ summary: 'Get all active sessions for the current user' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns list of active sessions' })
  async getSessions(
    @CurrentUser('id') userId: string,
    @Query('refreshToken') refreshToken?: string,
  ) {
    return this.authService.getUserSessions(userId, refreshToken);
  }

  // ── Revoke a Specific Session ─────────────────────────────────────
  @ApiBearerAuth()
  @Delete('sessions/:sessionId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Revoke a specific session' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Session revoked successfully' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Session not found' })
  async revokeSession(
    @CurrentUser('id') userId: string,
    @Param('sessionId') sessionId: string,
  ) {
    return this.authService.revokeSession(sessionId, userId);
  }

  // ── Revoke All Sessions Except Current ────────────────────────────
  @ApiBearerAuth()
  @Delete('sessions/all-except-current')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Revoke all sessions except current' })
  @ApiResponse({ status: HttpStatus.OK, description: 'All other sessions revoked successfully' })
  async revokeAllSessionsExceptCurrent(
    @CurrentUser('id') userId: string,
    @Query('refreshToken') refreshToken?: string,
  ) {
    return this.authService.revokeAllSessionsExceptCurrent(userId, refreshToken);
  }
}
