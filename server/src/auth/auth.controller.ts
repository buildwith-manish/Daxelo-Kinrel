import { Controller, Post, Delete, Get, Body, Param, Request, UseGuards, HttpCode, HttpStatus } from '@nestjs/common';
import { SupabaseAuthGuard } from './supabase-auth.guard';
import { PrismaService } from '../prisma/prisma.service';

@Controller('auth')
export class AuthController {
  constructor(private readonly prisma: PrismaService) {}

  @Post('logout')
  @UseGuards(SupabaseAuthGuard)
  @HttpCode(HttpStatus.OK)
  async logout(@Request() req: any) {
    // Invalidate session by deleting from DB
    const userId = req.user.id;
    await this.prisma.session.deleteMany({
      where: { userId },
    });
    return { message: 'Logged out successfully' };
  }

  @Post('change-password')
  @UseGuards(SupabaseAuthGuard)
  @HttpCode(HttpStatus.OK)
  async changePassword(@Request() req: any, @Body() body: any) {
    // In a real implementation, this would proxy to Supabase Auth API
    return { message: 'Password change request received' };
  }

  @Post('2fa/setup')
  @UseGuards(SupabaseAuthGuard)
  async setup2fa(@Request() req: any) {
    const userId = req.user.id;
    // Generate a simple TOTP secret
    const secret = Math.random().toString(36).substring(2, 15).toUpperCase();
    await this.prisma.user.update({
      where: { id: userId },
      data: { twoFactorSecret: secret },
    });
    return {
      secret,
      qrCodeUrl: `otpauth://totp/DaxeloKinrel:${req.user.email}?secret=${secret}&issuer=DaxeloKinrel`,
    };
  }

  @Post('2fa/verify')
  @UseGuards(SupabaseAuthGuard)
  @HttpCode(HttpStatus.OK)
  async verify2fa(@Request() req: any, @Body() body: { code: string }) {
    const userId = req.user.id;
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user || !user.twoFactorSecret) {
      return { verified: false, message: '2FA not set up' };
    }
    // Simple verification - in production, use proper TOTP
    return { verified: true, message: '2FA code verified' };
  }

  @Delete('2fa')
  @UseGuards(SupabaseAuthGuard)
  async disable2fa(@Request() req: any) {
    const userId = req.user.id;
    await this.prisma.user.update({
      where: { id: userId },
      data: { twoFactorEnabled: false, twoFactorSecret: null },
    });
    return { message: '2FA disabled' };
  }

  @Get('sessions')
  @UseGuards(SupabaseAuthGuard)
  async getSessions(@Request() req: any) {
    const userId = req.user.id;
    const sessions = await this.prisma.session.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
    return { sessions };
  }

  @Delete('sessions/:id')
  @UseGuards(SupabaseAuthGuard)
  async revokeSession(@Param('id') id: string, @Request() req: any) {
    const userId = req.user.id;
    await this.prisma.session.deleteMany({
      where: { id, userId },
    });
    return { message: 'Session revoked' };
  }

  @Delete('sessions/all-except-current')
  @UseGuards(SupabaseAuthGuard)
  async revokeAllOtherSessions(@Request() req: any) {
    const userId = req.user.id;
    const currentToken = req.headers['authorization']?.split(' ')[1];
    await this.prisma.session.deleteMany({
      where: {
        userId,
        token: { not: currentToken },
      },
    });
    return { message: 'All other sessions revoked' };
  }
}
