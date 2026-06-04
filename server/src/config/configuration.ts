import { plainToClass } from 'class-transformer';
import {
  IsNotEmpty,
  IsString,
  IsOptional,
  validateSync,
} from 'class-validator';

/**
 * Required environment variables — validated at startup.
 *
 * In production, ALL of these must be set. In development/CI,
 * missing vars produce a warning but don't crash the app,
 * allowing the Docker image to build and pass health checks
 * even before all secrets are configured.
 */
class EnvironmentVariables {
  @IsString()
  @IsNotEmpty({ groups: ['production'] })
  @IsOptional({ groups: ['development'] })
  JWT_ACCESS_SECRET: string;

  @IsString()
  @IsNotEmpty({ groups: ['production'] })
  @IsOptional({ groups: ['development'] })
  JWT_REFRESH_SECRET: string;

  @IsString()
  @IsNotEmpty({ groups: ['production'] })
  @IsOptional({ groups: ['development'] })
  DATABASE_URL: string;

  @IsString()
  @IsNotEmpty({ groups: ['production'] })
  @IsOptional({ groups: ['development'] })
  SUPABASE_URL: string;

  @IsString()
  @IsNotEmpty({ groups: ['production'] })
  @IsOptional({ groups: ['development'] })
  SUPABASE_SERVICE_ROLE_KEY: string;

  @IsString()
  @IsNotEmpty({ groups: ['production'] })
  @IsOptional({ groups: ['development'] })
  GOOGLE_AI_API_KEY: string;

  @IsString()
  @IsNotEmpty({ groups: ['production'] })
  @IsOptional({ groups: ['development'] })
  ENCRYPTION_KEY: string;
}

export function validate(config: Record<string, unknown>) {
  const validated = plainToClass(EnvironmentVariables, config);
  const env = (config.NODE_ENV as string) || 'development';
  const groups = [env === 'production' ? 'production' : 'development'];
  const errors = validateSync(validated, { groups });

  if (errors.length > 0) {
    if (env === 'production') {
      // In production, fail hard — missing config is a critical error
      throw new Error(
        `Missing required environment variables: ${errors
          .map((e) => Object.keys(e.constraints || {}).join(', '))
          .join('; ')}`,
      );
    }
    // In non-production, just warn — allows Docker health check to pass
    // before all secrets are configured
    console.warn(
      `⚠️  Missing environment variables (non-fatal in ${env}): ${errors
        .map((e) => Object.keys(e.constraints || {}).join(', '))
        .join('; ')}`,
    );
  }
  return validated;
}
