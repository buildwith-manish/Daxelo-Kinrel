import {
  Controller,
  Post,
  Delete,
  Get,
  Param,
  Body,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth, ApiConsumes } from '@nestjs/swagger';
import { SparqService } from './sparq.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { CreateSparqDto } from './dto/create-sparq.dto';

@ApiTags('Sparqs')
@Controller('sparqs')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
export class SparqController {
  constructor(private readonly sparqService: SparqService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiConsumes('multipart/form-data')
  @ApiOperation({ summary: 'Create a new Sparq' })
  @ApiResponse({ status: HttpStatus.CREATED, description: 'Sparq created successfully' })
  @UseInterceptors(
    FileInterceptor('mediaFile', {
      limits: { fileSize: 50 * 1024 * 1024 }, // 50MB
      fileFilter: (_req, file, cb) => {
        const allowed = [
          'image/jpeg',
          'image/png',
          'image/webp',
          'video/mp4',
          'video/webm',
          'audio/mpeg',
          'audio/mp4',
          'audio/webm',
          'audio/ogg',
        ];
        if (allowed.includes(file.mimetype)) {
          cb(null, true);
        } else {
          cb(new Error('Unsupported media type'), false);
        }
      },
    }),
  )
  async create(
    @CurrentUser('id') userId: string,
    @Body() dto: CreateSparqDto,
    @UploadedFile() mediaFile?: Express.Multer.File,
  ) {
    return this.sparqService.create(userId, dto, mediaFile);
  }

  @Delete(':sparqId')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Delete own Sparq' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Sparq deleted successfully' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Sparq not found' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Can only delete own Sparqs' })
  async delete(
    @CurrentUser('id') userId: string,
    @Param('sparqId') sparqId: string,
  ) {
    return this.sparqService.delete(sparqId, userId);
  }

  @Get('feed')
  @ApiOperation({ summary: 'Get Sparq feed grouped by user' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns Sparq feed' })
  async getFeed(@CurrentUser('id') userId: string) {
    return this.sparqService.getFeed(userId);
  }

  @Get('my')
  @ApiOperation({ summary: "Get current user's active Sparqs" })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns own Sparqs' })
  async getMySparqs(@CurrentUser('id') userId: string) {
    return this.sparqService.getMySparqs(userId);
  }

  @Post(':sparqId/view')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Mark a Sparq as viewed' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Sparq marked as viewed' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Sparq not found' })
  async markViewed(
    @Param('sparqId') sparqId: string,
    @CurrentUser('id') userId: string,
  ) {
    return this.sparqService.markViewed(sparqId, userId);
  }

  @Get(':sparqId/viewers')
  @ApiOperation({ summary: 'Get viewers list for own Sparq' })
  @ApiResponse({ status: HttpStatus.OK, description: 'Returns viewers list' })
  @ApiResponse({ status: HttpStatus.NOT_FOUND, description: 'Sparq not found' })
  @ApiResponse({ status: HttpStatus.FORBIDDEN, description: 'Can only view viewers of own Sparqs' })
  async getViewers(
    @CurrentUser('id') userId: string,
    @Param('sparqId') sparqId: string,
  ) {
    return this.sparqService.getViewers(sparqId, userId);
  }
}
