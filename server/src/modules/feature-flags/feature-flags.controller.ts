import { Controller, Get, Post, Body, Param } from '@nestjs/common';
import { FeatureFlagsService } from './feature-flags.service';

@Controller('feature-flags')
export class FeatureFlagsController {
  constructor(private readonly featureFlagsService: FeatureFlagsService) {}

  @Get()
  async getAllFlags() {
    return this.featureFlagsService.getAllFlags();
  }

  @Get(':name')
  async isFlagEnabled(@Param('name') name: string) {
    const enabled = await this.featureFlagsService.isEnabled(name);
    return { name, enabled };
  }

  @Post()
  async setFlag(
    @Body() body: { name: string; enabled: boolean; description?: string },
  ) {
    return this.featureFlagsService.setFlag(
      body.name,
      body.enabled,
      body.description,
    );
  }
}
