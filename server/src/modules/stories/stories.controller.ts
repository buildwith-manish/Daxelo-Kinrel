import {
  Controller,
  Get,
  Post,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  HttpCode,
  HttpStatus,
  BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiConsumes,
  ApiBody,
} from '@nestjs/swagger';
import { StoriesService } from './stories.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { CreateStoryDto } from './dto/create-story.dto';

/** Shared file filter logic for Story uploads */
const storyFileFilter = (
  _req: any,
  file: Express.Multer.File,
  cb: (error: any, acceptFile: boolean) => void,
) => {
  const allowed = [
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'video/mp4',
    'video/quicktime',
    'video/webm',
  ];
  if (allowed.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(
      new BadRequestException({
        statusCode: 400,
        errorCode: 'UNSUPPORTED_FORMAT',
        message:
          'File format not supported. Use JPG, PNG, WebP, GIF, MP4, MOV, or WebM.',
      }),
      false,
    );
  }
};

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
  ) {
    return this.storiesService.findByFamily(familyId, userId);
  }

  @Get('mine')
  @ApiOperation({ summary: "Get current user's stories" })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns the current user stories' })
  async findByUser(@CurrentUser('id') userId: string) {
    return this.storiesService.findByUser(userId);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @UseInterceptors(
    FileInterceptor('media', {
      limits: { fileSize: 50 * 1024 * 1024 }, // 50MB
      fileFilter: storyFileFilter,
    }),
  )
  @ApiConsumes('multipart/form-data')
  @ApiOperation({ summary: 'Create a new story' })
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        familyId: { type: 'string' },
        caption: { type: 'string' },
        mediaType: { type: 'string', enum: ['text', 'image', 'video'] },
        bgGradient: { type: 'string' },
        audience: { type: 'string', enum: ['PUBLIC', 'FAMILY_ONLY'] },
        media: { type: 'string', format: 'binary' },
      },
    },
  })
  @ApiResponse({ status: HttpStatus.CREATED, description: 'Story created successfully' })
  @ApiResponse({ status: HttpStatus.BAD_REQUEST, description: 'Invalid input data' })
  async create(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateStoryDto,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    return this.storiesService.create(userId, dto, file);
  }

  @Post(':id/view')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Mark a story as viewed' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Story marked as viewed' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Story not found' })
  async markViewed(
    @CurrentUser('id') userId: string,
    @Param('id') storyId: string,
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
