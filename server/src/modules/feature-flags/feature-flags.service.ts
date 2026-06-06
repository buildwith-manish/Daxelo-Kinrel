import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class FeatureFlagsService {
  constructor(private prisma: PrismaService) {}

  /** Checks whether a feature flag is enabled, returning false on error. */
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

  /** Returns all feature flags from the database. */
  async getAllFlags() {
    return this.prisma.featureFlag.findMany();
  }

  /** Creates or updates a feature flag with the given name and enabled state. */
  async setFlag(name: string, enabled: boolean, description?: string) {
    return this.prisma.featureFlag.upsert({
      where: { name },
      update: { enabled, description },
      create: { name, enabled, description },
    });
  }
}
