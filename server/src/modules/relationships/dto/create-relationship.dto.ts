import { IsString, IsNotEmpty, MaxLength } from 'class-validator';

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
  relationshipKey!: string;
}
