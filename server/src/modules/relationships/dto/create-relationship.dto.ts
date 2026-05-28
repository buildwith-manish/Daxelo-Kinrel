import { IsString, IsNotEmpty } from 'class-validator';

export class CreateRelationshipDto {
  @IsString()
  @IsNotEmpty()
  fromPersonId!: string;

  @IsString()
  @IsNotEmpty()
  toPersonId!: string;

  @IsString()
  @IsNotEmpty()
  relationshipKey!: string;
}
