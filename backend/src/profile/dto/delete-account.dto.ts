import { IsString, IsOptional, IsIn, MaxLength } from 'class-validator';

export class DeleteAccountDto {
  @IsString()
  password: string;

  @IsString()
  @IsIn(['DELETE'])
  confirmation: string;
}
