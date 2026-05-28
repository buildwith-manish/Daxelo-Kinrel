import { IsString, MinLength, MaxLength, Matches } from 'class-validator';

export class CheckUsernameDto {
  @IsString()
  @MinLength(3)
  @MaxLength(20)
  @Matches(/^[a-z0-9_]+$/, {
    message: 'Username can only contain lowercase letters, numbers, and underscores',
  })
  username: string;
}
