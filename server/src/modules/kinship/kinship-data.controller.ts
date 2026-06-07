import {
  Controller,
  Get,
  Param,
  Res,
  NotFoundException,
} from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Response } from 'express';
import { join } from 'path';
import { existsSync, createReadStream, statSync } from 'fs';
import { Public } from '../../common/decorators/public.decorator';

@ApiTags('Kinship Data')
@Controller('v1/kinship/data')
export class KinshipDataController {
  /**
   * Directory where kinship JSON data files are stored on the server.
   * In production, this should be populated with the production JSON files
   * that were previously bundled in the Flutter app's assets/data/global/.
   *
   * Set the KINSHIP_DATA_DIR env var to override the default path.
   */
  private readonly dataDir: string;

  constructor() {
    this.dataDir =
      process.env.KINSHIP_DATA_DIR ||
      join(process.cwd(), 'kinship-assets');
  }

  /**
   * Valid language codes that can be served.
   * Prevents directory traversal attacks by whitelisting known codes.
   */
  private static readonly VALID_LANGUAGE_CODES = new Set([
    'arabic',
    'korean',
    'japanese',
    'vietnamese',
    'vietnamese_v2',
    'russian',
    'russian_v2',
    'chinese',
  ]);

  /**
   * Maps a cultureKey from the Flutter app to the corresponding filename
   * on the server's filesystem.
   */
  private static readonly FILENAME_MAP: Record<string, string> = {
    arabic: 'arabic_kinship_production.json',
    korean: 'korean_kinship_production.json',
    japanese: 'japanese_kinship_production.json',
    vietnamese: 'vietnamese_kinship_production_v2.json',
    vietnamese_v2: 'vietnamese_kinship_production_v2.json',
    russian: 'russian_kinship_production_v2.json',
    russian_v2: 'russian_kinship_production_v2.json',
    chinese: 'chinese_kinship_production.json',
  };

  /**
   * GET /api/v1/kinship/data/:languageCode
   *
   * Serves the full kinship JSON data for a given language/culture.
   * This endpoint is public (no auth required) because kinship data
   * is not user-specific — it's a shared cultural dictionary.
   *
   * Responses are streamed directly from disk with aggressive caching
   * headers (24 hours) since the data changes infrequently.
   */
  @Public()
  @Get(':languageCode')
  async getKinshipData(
    @Param('languageCode') languageCode: string,
    @Res() res: Response,
  ) {
    // Validate language code against whitelist
    if (!KinshipDataController.VALID_LANGUAGE_CODES.has(languageCode)) {
      throw new NotFoundException(
        `Kinship data not available for: ${languageCode}`,
      );
    }

    const filename = KinshipDataController.FILENAME_MAP[languageCode];
    if (!filename) {
      throw new NotFoundException(
        `Kinship data not available for: ${languageCode}`,
      );
    }

    const filePath = join(this.dataDir, filename);

    // Check file exists
    if (!existsSync(filePath)) {
      throw new NotFoundException(
        `Kinship data file not found for: ${languageCode}. ` +
          `Ensure the file '${filename}' exists in the KINSHIP_DATA_DIR directory.`,
      );
    }

    // Stream the file with appropriate headers
    const stat = statSync(filePath);
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Content-Length', stat.size);
    res.setHeader(
      'Cache-Control',
      'public, max-age=86400, s-maxage=86400', // Cache for 24 hours
    );
    res.setHeader('X-Content-Type-Options', 'nosniff');

    createReadStream(filePath).pipe(res);
  }

  /**
   * GET /api/v1/kinship/data
   *
   * Returns a list of available language codes that have data files.
   */
  @Public()
  @Get()
  async listAvailableLanguages() {
    const available: string[] = [];

    for (const [code, filename] of Object.entries(
      KinshipDataController.FILENAME_MAP,
    )) {
      // Skip duplicate entries (e.g., vietnamese and vietnamese_v2)
      if (available.includes(code)) continue;

      const filePath = join(this.dataDir, filename);
      if (existsSync(filePath)) {
        available.push(code);
      }
    }

    return {
      availableLanguages: available,
      totalSizeMB: this._calculateTotalSizeMB(),
    };
  }

  private _calculateTotalSizeMB(): number {
    let totalBytes = 0;
    for (const filename of new Set(
      Object.values(KinshipDataController.FILENAME_MAP),
    )) {
      const filePath = join(this.dataDir, filename);
      if (existsSync(filePath)) {
        totalBytes += statSync(filePath).size;
      }
    }
    return Math.round((totalBytes / (1024 * 1024)) * 10) / 10;
  }
}
