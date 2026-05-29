import {
  Controller,
  Post,
  Get,
  Put,
  Patch,
  Delete,
  Body,
  Query,
  Param,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  HttpStatus,
  HttpCode,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { UsersService } from './users.service';

@Controller('users')
@UseGuards(JwtAuthGuard)
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  // ── Get Profile ───────────────────────────────────────────────────
  @Get('me')
  async getProfile(@CurrentUser('id') userId: string) {
    return this.usersService.getProfile(userId);
  }

  // ── Get Stats ─────────────────────────────────────────────────────
  @Get('me/stats')
  async getStats(@CurrentUser('id') userId: string) {
    return this.usersService.getStats(userId);
  }

  // ── Update Profile (enhanced) ────────────────────────────────────
  @Patch('me')
  async updateProfile(
    @CurrentUser('id') userId: string,
    @Body()
    body: {
      name?: string;
      phone?: string;
      preferredLanguage?: string;
      username?: string;
      bio?: string;
      dateOfBirth?: string;
      gender?: string;
      avatarUrl?: string;
      profileVisibility?: string;
      invitePermission?: string;
    },
  ) {
    return this.usersService.updateProfile(userId, body);
  }

  // ── Upload Avatar (POST — existing endpoint) ─────────────────────
  @Post('me/avatar')
  @UseInterceptors(
    FileInterceptor('avatar', {
      limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
      fileFilter: (_req, file, cb) => {
        const allowed = ['image/jpeg', 'image/png', 'image/webp'];
        if (allowed.includes(file.mimetype)) {
          cb(null, true);
        } else {
          cb(new Error('Only JPEG, PNG, and WebP images are allowed'), false);
        }
      },
    }),
  )
  async uploadAvatarPost(
    @CurrentUser('id') userId: string,
    @UploadedFile() file: Express.Multer.File,
  ) {
    return this.usersService.uploadAvatar(userId, file);
  }

  // ── Upload Avatar (PUT — Flutter uses PUT) ───────────────────────
  @Put('me/avatar')
  @UseInterceptors(
    FileInterceptor('avatar', {
      limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
      fileFilter: (_req, file, cb) => {
        const allowed = ['image/jpeg', 'image/png', 'image/webp'];
        if (allowed.includes(file.mimetype)) {
          cb(null, true);
        } else {
          cb(new Error('Only JPEG, PNG, and WebP images are allowed'), false);
        }
      },
    }),
  )
  async uploadAvatarPut(
    @CurrentUser('id') userId: string,
    @UploadedFile() file: Express.Multer.File,
  ) {
    return this.usersService.uploadAvatar(userId, file);
  }

  // ── Check Username Availability ──────────────────────────────────
  @Get('check-username')
  async checkUsername(@Query('username') username: string) {
    return this.usersService.checkUsername(username);
  }

  // ── Update Username ──────────────────────────────────────────────
  @Patch('me/username')
  async updateUsername(
    @CurrentUser('id') userId: string,
    @Body() body: { username: string },
  ) {
    return this.usersService.updateUsername(userId, body.username);
  }

  // ── Get User's Families ──────────────────────────────────────────
  @Get('me/families')
  async getFamilies(@CurrentUser('id') userId: string) {
    return this.usersService.getFamilies(userId);
  }

  // ── Get User's Pending Invitations ───────────────────────────────
  @Get('me/invitations')
  async getInvitations(@CurrentUser('id') userId: string) {
    return this.usersService.getInvitations(userId);
  }

  // ── Get Blocked Users ────────────────────────────────────────────
  @Get('me/blocked')
  async getBlockedUsers(@CurrentUser('id') userId: string) {
    return this.usersService.getBlockedUsers(userId);
  }

  // ── Unblock a User ───────────────────────────────────────────────
  @Delete('me/blocked/:userId')
  @HttpCode(HttpStatus.OK)
  async unblockUser(
    @CurrentUser('id') currentUserId: string,
    @Param('userId') blockedUserId: string,
  ) {
    return this.usersService.unblockUser(currentUserId, blockedUserId);
  }

  // ── Request Data Export ──────────────────────────────────────────
  @Post('me/data-export')
  @HttpCode(HttpStatus.OK)
  async requestDataExport(@CurrentUser('id') userId: string) {
    return this.usersService.requestDataExport(userId);
  }

  // ── Delete Account (with optional password confirmation) ─────────
  @Delete('me')
  @HttpCode(HttpStatus.OK)
  async deleteAccount(
    @CurrentUser('id') userId: string,
    @Body() body?: { password?: string },
  ) {
    return this.usersService.deleteAccount(userId, body?.password);
  }

  // ── Set Quiet Hours ──────────────────────────────────────────────
  @Put('me/quiet-hours')
  async setQuietHours(
    @CurrentUser('id') userId: string,
    @Body() body: { start?: string; end?: string; enabled?: boolean },
  ) {
    return this.usersService.setQuietHours(userId, body);
  }

  // ── Get Quiet Hours ──────────────────────────────────────────────
  @Get('me/quiet-hours')
  async getQuietHours(@CurrentUser('id') userId: string) {
    return this.usersService.getQuietHours(userId);
  }

  // ── Register / Update FCM Token ──────────────────────────────────
  @Post('me/fcm-token')
  @HttpCode(HttpStatus.OK)
  async registerFcmToken(
    @CurrentUser('id') userId: string,
    @Body() body: { fcmToken: string; deviceType?: string },
  ) {
    return this.usersService.registerFcmToken(userId, body);
  }

  // ── Delete FCM Token ─────────────────────────────────────────────
  @Delete('me/fcm-token')
  @HttpCode(HttpStatus.OK)
  async deleteFcmToken(
    @CurrentUser('id') userId: string,
    @Body() body: { fcmToken: string },
  ) {
    return this.usersService.deleteFcmToken(userId, body.fcmToken);
  }
}
