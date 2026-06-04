import { plainToClass } from 'class-transformer';
import {
  IsNotEmpty,
  IsString,
  validateSync,
} from 'class-validator';

class EnvironmentVariables {
  @IsNotEmpty()
  @IsString()
  JWT_ACCESS_SECRET: string;

  @IsNotEmpty()
  @IsString()
  JWT_REFRESH_SECRET: string;

  @IsNotEmpty()
  @IsString()
  DATABASE_URL: string;

  @IsNotEmpty()
  @IsString()
  SUPABASE_URL: string;

  @IsNotEmpty()
  @IsString()
  SUPABASE_SERVICE_ROLE_KEY: string;

  @IsNotEmpty()
  @IsString()
  GOOGLE_AI_API_KEY: string;

  @IsNotEmpty()
  @IsString()
  ENCRYPTION_KEY: string;
}

export function validate(config: Record<string, unknown>) {
  const validated = plainToClass(EnvironmentVariables, config);
  const errors = validateSync(validated);
  if (errors.length > 0) {
    throw new Error(errors.toString());
  }
  return validated;
}
