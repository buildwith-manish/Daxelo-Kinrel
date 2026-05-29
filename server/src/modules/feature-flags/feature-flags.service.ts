import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class FeatureFlagsService {
  constructor(private prisma: PrismaService) {}

  async isEnabled(flagName: string): Promise<boolean> {
    try {
      const flag = await this.prisma.featureFlag.findUnique({
        where: { name: flagName },
      });
      return flag?.enabled ?? false;
    } catch {
      return false;
    }
  }

  async getAllFlags() {
    return this.prisma.featureFlag.findMany();
  }

  async setFlag(name: string, enabled: boolean, description?: string) {
    return this.prisma.featureFlag.upsert({
      where: { name },
      update: { enabled, description },
      create: { name, enabled, description },
    });
  }
}
