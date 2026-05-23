import {
  Controller,
  Get,
  Patch,
  Delete,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
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
   * Response: { user: { id, email, name, phone, preferredLanguage, role, createdAt, updatedAt } }
   */
  @Get('me')
  @UseGuards(JwtAuthGuard)
  async getProfile(@CurrentUser('id') userId: string) {
    return this.userService.getProfile(userId);
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
