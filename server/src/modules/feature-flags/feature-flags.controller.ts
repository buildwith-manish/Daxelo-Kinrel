import { Controller, Get, Post, Body, Param, UseGuards, ForbiddenException } from '@nestjs/common';
import { FeatureFlagsService } from './feature-flags.service';
import { Public } from '../../common/decorators/public.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('feature-flags')
export class FeatureFlagsController {
  constructor(private readonly featureFlagsService: FeatureFlagsService) {}

  @Public()
  @Get()
  async getAllFlags() {
    return this.featureFlagsService.getAllFlags();
  }

  @Public()
  @Get(':name')
  async isFlagEnabled(@Param('name') name: string) {
    const enabled = await this.featureFlagsService.isEnabled(name);
    return { name, enabled };
  }

  @Post()
  @UseGuards(JwtAuthGuard)
  async setFlag(
    @CurrentUser('role') role: string,
    @Body() body: { name: string; enabled: boolean; description?: string },
  ) {
    if (role !== 'admin') {
      throw new ForbiddenException('Only admins can modify feature flags');
    }
    return this.featureFlagsService.setFlag(
      body.name,
      body.enabled,
      body.description,
    );
  }
}
