import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class SupportService {
  constructor(private readonly prisma: PrismaService) {}

  async createTicket(userId: string, data: { subject: string; message: string }) {
    const ticket = await this.prisma.supportTicket.create({
      data: {
        userId,
        subject: data.subject,
        message: data.message,
      },
    });
    return ticket;
  }
}
