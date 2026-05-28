import { Controller, Get, Post, Body } from '@nestjs/common';
import { LegalService } from './legal.service';
import { PrismaService } from '../prisma/prisma.service';
import { IsEmail, IsOptional, IsString } from 'class-validator';

class DataDeletionRequestDto {
  @IsEmail()
  email: string;

  @IsOptional()
  @IsString()
  userId?: string;

  @IsOptional()
  @IsString()
  reason?: string;
}

@Controller('legal')
export class LegalController {
  constructor(
    private readonly legalService: LegalService,
    private readonly prisma: PrismaService,
  ) {}

  @Get('privacy')
  getPrivacyPolicy(): { html: string } {
    return { html: this.legalService.getPrivacyPolicy() };
  }

  @Get('terms')
  getTermsOfService(): { html: string } {
    return { html: this.legalService.getTermsOfService() };
  }

  @Post('data-deletion-request')
  async requestDataDeletion(@Body() dto: DataDeletionRequestDto) {
    // Log the request to database
    const request = await this.prisma.dataDeletionRequest.create({
      data: {
        email: dto.email,
        userId: dto.userId,
        reason: dto.reason,
        status: 'pending',
      },
    });

    // Log to console (email service can be added later)
    console.log(
      `[DATA DELETION REQUEST] id=${request.id} email=${dto.email} userId=${dto.userId || 'N/A'} reason=${dto.reason || 'N/A'}`,
    );

    return {
      message: 'Request received. We will process your data deletion within 30 days.',
      requestId: request.id,
    };
  }
}
