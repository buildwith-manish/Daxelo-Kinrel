// server/src/modules/chat/nearby.controller.ts
//
// DAXELO KINREL — Tier 5 Feature 5.3: People Nearby — Controller

import { Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { NearbyService } from './nearby.service';

@Controller('chat/nearby')
@UseGuards(JwtAuthGuard)
export class NearbyController {
  constructor(private readonly service: NearbyService) {}

  /// POST /chat/nearby/ping
  /// Body: { lat, lng, accuracyM? }
  /// Upserts the caller's last-known location.
  @Post('ping')
  async ping(
    @CurrentUser('id') userId: string,
    @Body() body: { lat: number; lng: number; accuracyM?: number | null },
  ) {
    return this.service.pingLocation(userId, body);
  }

  /// GET /chat/nearby/users?lat=&lng=&radiusM=&limit=
  /// Returns nearby users (with distance, honoring lastSeenVisibility reciprocity).
  @Get('users')
  async users(
    @CurrentUser('id') userId: string,
    @Query('lat') lat?: string,
    @Query('lng') lng?: string,
    @Query('radiusM') radiusM?: string,
    @Query('limit') limit?: string,
  ) {
    if (!lat || !lng) {
      return { error: 'lat and lng are required' };
    }
    return this.service.getNearbyUsers(userId, {
      lat: parseFloat(lat),
      lng: parseFloat(lng),
      radiusM: radiusM ? parseInt(radiusM, 10) : 1000,
      limit: limit ? parseInt(limit, 10) : 50,
    });
  }

  /// POST /chat/nearby/discovery
  /// Body: { enabled: boolean }
  /// Opt in/out of nearby discovery.
  @Post('discovery')
  async setDiscovery(
    @CurrentUser('id') userId: string,
    @Body() body: { enabled: boolean },
  ) {
    return this.service.setDiscoveryEnabled(userId, body.enabled);
  }
}
