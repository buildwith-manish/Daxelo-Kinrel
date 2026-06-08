import {
  Controller,
  Get,
  Post,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { StoriesService } from './stories.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { CreateStoryDto } from './dto/create-story.dto';

@ApiTags('Stories')
@Controller('stories')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class StoriesController {
  constructor(private storiesService: StoriesService) {}

  @Get()
  @ApiOperation({ summary: 'Get stories grouped by user for a family' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns stories grouped by user' })
  async findByFamily(
    @CurrentUser('id') userId: string,
    @Query('familyId') familyId: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.storiesService.findByFamily(
      familyId,
      userId,
      limit ? parseInt(limit, 10) : 50,
      cursor,
    );
  }

  @Get('mine')
  @ApiOperation({ summary: "Get current user's stories" })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns the current user stories' })
  async findByUser(
    @CurrentUser('id') userId: string,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.storiesService.findByUser(
      userId,
      limit ? parseInt(limit, 10) : 50,
      cursor,
    );
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a new story' })
  @ApiResponse({ status: HttpStatus.CREATED, description: 'Story created successfully' })
  @ApiResponse({ status: HttpStatus.BAD_REQUEST, description: 'Invalid input data' })
  async create(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateStoryDto,
  ) {
    return this.storiesService.create(userId, dto);
  }

  @Post(':id/view')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Mark a story as viewed' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Story marked as viewed' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Story not found' })
  async markViewed(
    @Param('id') storyId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.storiesService.markViewed(storyId, userId);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Delete a story' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Story deleted successfully' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Story not found' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Not the story owner' })
  async remove(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ) {
    return this.storiesService.remove(id, userId);
  }
}
