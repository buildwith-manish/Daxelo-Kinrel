import {
  Controller,
  Get,
  Put,
  Patch,
  Delete,
  Body,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  HttpCode,
  HttpStatus,
  BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { UserService } from './user.service';
import { UpdateUserDto } from './dto/update-user.dto';
import { JwtAuthGuard } from '@/common/guards/jwt-auth.guard';
import { CurrentUser } from '@/common/decorators/current-user.decorator';

@Controller('users')
export class UserController {
  constructor(private readonly userService: UserService) {}

  // ── GET /api/users/me ───────────────────────────────────────────
  /**
   * Get current user profile (JWT protected).
   * Response: { user: { id, email, name, phone, preferredLanguage, role, avatarUrl, twoFactorEnabled, createdAt, updatedAt } }
   */
  @Get('me')
  @UseGuards(JwtAuthGuard)
  async getProfile(@CurrentUser('id') userId: string) {
    return this.userService.getProfile(userId);
  }

  // ── GET /api/users/me/stats ─────────────────────────────────────
  /**
   * Get current user stats (JWT protected).
   * Response: { familyTrees, membersAdded, relations }
   */
  @Get('me/stats')
  @UseGuards(JwtAuthGuard)
  async getMyStats(@CurrentUser('id') userId: string) {
    return this.userService.getUserStats(userId);
  }

  // ── PUT /api/users/me/avatar ────────────────────────────────────
  /**
   * Upload avatar image (JWT protected, multipart form data).
   * Field name: "avatar"
   * Response: { user: { ...updated user profile } }
   */
  @Put('me/avatar')
  @UseGuards(JwtAuthGuard)
  @UseInterceptors(FileInterceptor('avatar'))
  async uploadAvatar(
    @CurrentUser('id') userId: string,
    @UploadedFile() file: Express.Multer.File,
  ) {
    if (!file) {
      throw new BadRequestException('No file uploaded');
    }
    return this.userService.updateAvatar(userId, file);
  }

  // ── PATCH /api/users/me ─────────────────────────────────────────
  /**
   * Update current user profile (JWT protected).
   * Body: { name?, phone?, preferredLanguage? }
   * Response: { user: { id, email, name, phone, preferredLanguage, role } }
   */
  @Patch('me')
  @UseGuards(JwtAuthGuard)
  async updateProfile(
    @CurrentUser('id') userId: string,
    @Body() dto: UpdateUserDto,
  ) {
    return this.userService.updateProfile(userId, dto);
  }

  // ── DELETE /api/users/me ────────────────────────────────────────
  /**
   * Delete current user account (JWT protected).
   * Response: { success: true, message: 'Account deleted' }
   */
  @Delete('me')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async deleteAccount(@CurrentUser('id') userId: string) {
    return this.userService.deleteAccount(userId);
  }
}
