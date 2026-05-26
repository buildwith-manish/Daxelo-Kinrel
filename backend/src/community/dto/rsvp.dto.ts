import { IsString, IsIn, IsOptional, IsBoolean } from 'class-validator';

export class RsvpDto {
  @IsString()
  @IsIn(['going', 'maybe', 'not_going'])
  status!: 'going' | 'maybe' | 'not_going';

  @IsOptional()
  @IsBoolean()
  plusOne?: boolean;

  @IsOptional()
  @IsString()
  note?: string;
}
