import {
  Controller,
  Post,
  Get,
  Delete,
  Body,
  Query,
  Param,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiConsumes } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { SparqService } from './sparq.service';
import { CreateSparqDto, SparqFeedDto } from './dto/sparq.dto';

@ApiTags('Sparq')
@Controller('sparq')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class SparqController {
  constructor(private readonly sparqService: SparqService) {}

  @Get('feed')
  @ApiOperation({ summary: 'Get Sparq feed for home screen' })
  getFeed(@CurrentUser('id') userId: string, @Query() dto: SparqFeedDto) {
    return this.sparqService.getFeed(userId, dto);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiConsumes('multipart/form-data')
  @ApiOperation({ summary: 'Create a new Sparq' })
  create(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateSparqDto,
  ) {
    return this.sparqService.createSparq(userId, dto);
  }

  @Get('user/:userId')
  @ApiOperation({ summary: 'Get active Sparqs for a specific user' })
  getUserSparqs(
    @CurrentUser('id') viewerId: string,
    @Param('userId') userId: string,
  ) {
    return this.sparqService.getUserSparqs(userId, viewerId);
  }

  @Post(':id/view')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Mark a Sparq as viewed' })
  markViewed(@CurrentUser('id') userId: string, @Param('id') sparqId: string) {
    return this.sparqService.markViewed(sparqId, userId);
  }

  @Get(':id/viewers')
  @ApiOperation({ summary: 'Get viewers for a Sparq (creator only)' })
  getViewers(@CurrentUser('id') userId: string, @Param('id') sparqId: string) {
    return this.sparqService.getViewers(sparqId, userId);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Delete your own Sparq' })
  deleteSparq(@CurrentUser('id') userId: string, @Param('id') sparqId: string) {
    return this.sparqService.deleteSparq(sparqId, userId);
  }
}
