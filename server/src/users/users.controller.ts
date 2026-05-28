import {
  Controller,
  Get,
  Patch,
  Put,
  Post,
  Delete,
  Body,
  Query,
  Param,
  UseGuards,
  Request,
  UploadedFile,
  UseInterceptors,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { SupabaseAuthGuard } from '../auth/supabase-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { UsersService } from './users.service';
import { PrismaService } from '../prisma/prisma.service';

@Controller('users')
export class UsersController {
  constructor(
    private readonly usersService: UsersService,
    private readonly prisma: PrismaService,
  ) {}

  @Get('me')
  @UseGuards(SupabaseAuthGuard)
  async getProfile(@CurrentUser() user: any) {
    const userId = user.id;
    const profile = await this.usersService.getOrCreateUser(userId, user.email || '');
    const { twoFactorSecret, ...safeUser } = profile as any;
    return { user: safeUser };
  }

  @Patch('me')
  @UseGuards(SupabaseAuthGuard)
  async updateProfile(@CurrentUser() user: any, @Body() body: any) {
    const updated = await this.usersService.updateProfile(user.id, body);
    const { twoFactorSecret, ...safeUser } = updated as any;
    return { user: safeUser };
  }

  @Put('me/avatar')
  @UseGuards(SupabaseAuthGuard)
  async uploadAvatar(@CurrentUser() user: any, @Body() body: { avatarUrl: string }) {
    const updated = await this.usersService.updateAvatar(user.id, body.avatarUrl);
    const { twoFactorSecret, ...safeUser } = updated as any;
    return { user: safeUser };
  }

  @Get('me/stats')
  @UseGuards(SupabaseAuthGuard)
  async getStats(@CurrentUser() user: any) {
    const stats = await this.usersService.getStats(user.id);
    return stats;
  }

  @Get('check-username')
  async checkUsername(@Query('username') username: string) {
    return this.usersService.checkUsername(username);
  }

  @Patch('me/username')
  @UseGuards(SupabaseAuthGuard)
  async setUsername(@CurrentUser() user: any, @Body() body: { username: string }) {
    const result = await this.usersService.setUsername(user.id, body.username);
    if (result && (result as any).error) {
      return { error: (result as any).error };
    }
    const { twoFactorSecret, ...safeUser } = result as any;
    return { user: safeUser };
  }

  @Get('me/families')
  @UseGuards(SupabaseAuthGuard)
  async getFamilies(@CurrentUser() user: any) {
    const families = await this.usersService.getFamilies(user.id);
    return { families };
  }

  @Get('me/invitations')
  @UseGuards(SupabaseAuthGuard)
  async getInvitations(@CurrentUser() user: any) {
    const invitations = await this.usersService.getInvitations(user.id);
    return { invitations };
  }

  @Get('me/blocked')
  @UseGuards(SupabaseAuthGuard)
  async getBlocked(@CurrentUser() user: any) {
    return this.usersService.getBlocked(user.id);
  }

  @Delete('me/blocked/:userId')
  @UseGuards(SupabaseAuthGuard)
  async unblockUser(@CurrentUser() user: any, @Param('userId') blockedUserId: string) {
    return this.usersService.unblockUser(user.id, blockedUserId);
  }

  @Post('me/data-export')
  @UseGuards(SupabaseAuthGuard)
  async requestDataExport(@CurrentUser() user: any) {
    return this.usersService.requestDataExport(user.id);
  }

  @Delete('me')
  @UseGuards(SupabaseAuthGuard)
  @HttpCode(HttpStatus.OK)
  async deleteAccount(@CurrentUser() user: any) {
    return this.usersService.deleteAccount(user.id);
  }

  @Put('me/quiet-hours')
  @UseGuards(SupabaseAuthGuard)
  async updateQuietHours(@CurrentUser() user: any, @Body() body: any) {
    return this.usersService.updateQuietHours(user.id, body);
  }
}
