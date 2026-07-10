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
  BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiTags, ApiOperation, ApiBearerAuth, ApiConsumes, ApiBody } from '@nestjs/swagger';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { SparqService } from './sparq.service';
import { CreateSparqDto, SparqFeedDto } from './dto/sparq.dto';

/** Shared file filter logic for Sparq uploads */
const sparqFileFilter = (_req: any, file: Express.Multer.File, cb: (error: any, acceptFile: boolean) => void) => {
  const allowed = [
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'video/mp4',
    'video/quicktime',
    'video/webm',
    'audio/mpeg',
    'audio/mp4',
    'audio/webm',
    'audio/ogg',
  ];
  if (allowed.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(
      new BadRequestException({
        statusCode: 400,
        errorCode: 'UNSUPPORTED_FORMAT',
        message: 'File format not supported. Use JPG, PNG, WebP, GIF, MP4, MOV, WebM, MP3, M4A, or OGG.',
      }),
      false,
    );
  }
};

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
  @UseInterceptors(
    FileInterceptor('media', {
      limits: { fileSize: 50 * 1024 * 1024 }, // 50 MB — covers videos
      fileFilter: sparqFileFilter,
    }),
  )
  @ApiConsumes('multipart/form-data')
  @ApiOperation({ summary: 'Create a new Sparq' })
  @ApiBody({
    schema: {
      type: 'object',
      required: ['type'],
      properties: {
        type: { type: 'string', enum: ['IMAGE', 'VIDEO', 'TEXT', 'VOICE'] },
        text: { type: 'string' },
        backgroundColor: { type: 'string' },
        duration: { type: 'integer' },
        audience: { type: 'string', enum: ['PUBLIC', 'FAMILY_ONLY', 'VIP_CIRCLE'] },
        mood: { type: 'string', enum: ['happy', 'hype', 'love', 'sad', 'celebrate', 'angry'] },
        intensity: { type: 'string', enum: ['calm', 'warm', 'fire'] },
        allowChain: { type: 'boolean' },
        allowReplies: { type: 'boolean' },
        isTimeCapsule: { type: 'boolean' },
        revealAt: { type: 'string', format: 'date-time' },
        parentSparqId: { type: 'string' },
        media: { type: 'string', format: 'binary' },
      },
    },
  })
  create(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateSparqDto,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    return this.sparqService.createSparq(userId, dto, file);
  }

  @Get('user/:userId')
  @ApiOperation({ summary: 'Get active Sparqs for a specific user' })
  getUserSparqs(
    @CurrentUser('id') viewerId: string,
    @Param('userId') userId: string,
  ) {
    return this.sparqService.getUserSparqs(userId, viewerId);
  }

  @Post(':id/echo')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Toggle echo on a Sparq' })
  toggleEcho(@CurrentUser('id') userId: string, @Param('id') sparqId: string) {
    return this.sparqService.toggleEcho(sparqId, userId);
  }

  @Get(':id/chain')
  @ApiOperation({ summary: 'Get all Sparqs in a chain' })
  getChain(@Param('id') sparqId: string, @CurrentUser('id') userId: string) {
    return this.sparqService.getChain(sparqId);
  }

  @Post(':id/chain')
  @HttpCode(HttpStatus.CREATED)
  @UseInterceptors(
    FileInterceptor('media', {
      limits: { fileSize: 50 * 1024 * 1024 },
      fileFilter: sparqFileFilter,
    }),
  )
  @ApiConsumes('multipart/form-data')
  @ApiOperation({ summary: 'Add a Sparq to an existing chain' })
  @ApiBody({
    schema: {
      type: 'object',
      required: ['type'],
      properties: {
        type: { type: 'string', enum: ['IMAGE', 'VIDEO', 'TEXT', 'VOICE'] },
        text: { type: 'string' },
        backgroundColor: { type: 'string' },
        duration: { type: 'integer' },
        audience: { type: 'string', enum: ['PUBLIC', 'FAMILY_ONLY', 'VIP_CIRCLE'] },
        mood: { type: 'string', enum: ['happy', 'hype', 'love', 'sad', 'celebrate', 'angry'] },
        intensity: { type: 'string', enum: ['calm', 'warm', 'fire'] },
        allowChain: { type: 'boolean' },
        allowReplies: { type: 'boolean' },
        isTimeCapsule: { type: 'boolean' },
        revealAt: { type: 'string', format: 'date-time' },
        media: { type: 'string', format: 'binary' },
      },
    },
  })
  addToChain(
    @CurrentUser('id') userId: string,
    @Param('id') parentSparqId: string,
    @Body() dto: CreateSparqDto,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    return this.sparqService.addToChain(parentSparqId, userId, dto, file);
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
