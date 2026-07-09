import {
  Controller,
  Post,
  Get,
  Body,
  Query,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ThinkingService } from './thinking.service';
import { SendTapDto } from './dto/send-tap.dto';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('v1/thinking')
export class ThinkingController {
  constructor(private readonly thinkingService: ThinkingService) {}

  @Post('tap')
  @HttpCode(HttpStatus.CREATED)
  async sendTap(
    @CurrentUser('id') userId: string,
    @Body() dto: SendTapDto,
  ) {
    return this.thinkingService.sendTap(userId, dto);
  }

  @Get('received')
  async getReceived(
    @CurrentUser('id') userId: string,
    @Query('limit') limit = 20,
    @Query('page') page = 1,
  ) {
    return this.thinkingService.getReceivedTaps(userId, +limit, +page);
  }
}
