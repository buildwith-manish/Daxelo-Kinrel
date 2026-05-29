import { IsString, IsNotEmpty, IsOptional, MaxLength } from 'class-validator';

export class CreateRelationshipDto {
  @IsString()
  @IsNotEmpty()
  fromPersonId!: string;

  @IsString()
  @IsNotEmpty()
  toPersonId!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(50)
  type!: string;

  @IsString()
  @IsOptional()
  @MaxLength(50)
  relationshipKey?: string;

  @IsString()
  @IsOptional()
  @MaxLength(20)
  direction?: string;

  @IsString()
  @IsOptional()
  @MaxLength(100)
  label?: string;
}
