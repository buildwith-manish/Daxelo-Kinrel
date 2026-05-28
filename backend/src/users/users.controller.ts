import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
  Request,
} from '@nestjs/common';
import { UsersService } from './users.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { UpdateUserDto } from './dto/update-user.dto';

@Controller('users')
@UseGuards(JwtAuthGuard)
export class UsersController {
  constructor(private usersService: UsersService) {}

  /**
   * GET /api/users/me
   * Matches Next.js: { user: {...} }
   */
  @Get('me')
  async getProfile(@CurrentUser() user: { id: string }) {
    return this.usersService.getProfile(user.id);
  }

  /**
   * PATCH /api/users/me
   * Matches Next.js: { user: {...} }
   */
  @Patch('me')
  async updateProfile(
    @CurrentUser() user: { id: string },
    @Body() dto: UpdateUserDto,
  ) {
    return this.usersService.updateProfile(user.id, dto);
  }

  /**
   * POST /api/users/me/fcm-token
   * Update the user's FCM token for push notifications
   */
  @Post('me/fcm-token')
  @HttpCode(HttpStatus.OK)
  async updateFcmToken(
    @Request() req: any,
    @Body() body: { fcmToken: string },
  ) {
    return this.usersService.updateFcmToken(req.user.id, body.fcmToken);
  }

  /**
   * DELETE /api/users/me
   * Matches Next.js: { success: true, message: 'Account deleted' }
   */
  @Delete('me')
  @HttpCode(HttpStatus.OK)
  async deleteAccount(@CurrentUser() user: { id: string }) {
    return this.usersService.deleteAccount(user.id);
  }
}
