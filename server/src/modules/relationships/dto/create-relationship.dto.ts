import { IsString, IsNotEmpty, IsUUID, MaxLength } from 'class-validator';

export class CreateRelationshipDto {
  @IsUUID()
  @IsNotEmpty()
  fromPersonId!: string;

  @IsUUID()
  @IsNotEmpty()
  toPersonId!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(50)
  relationshipKey!: string;
}
