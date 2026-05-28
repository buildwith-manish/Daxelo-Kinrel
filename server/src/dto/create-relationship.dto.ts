import { IsString, IsNotEmpty, IsOptional } from 'class-validator';

export class CreateRelationshipDto {
  @IsString()
  @IsNotEmpty()
  fromPersonId!: string;

  @IsString()
  @IsNotEmpty()
  toPersonId!: string;

  @IsString()
  @IsNotEmpty()
  type!: string;

  @IsString()
  @IsOptional()
  relationshipKey?: string;

  @IsString()
  @IsOptional()
  direction?: string;

  @IsString()
  @IsOptional()
  label?: string;
}
