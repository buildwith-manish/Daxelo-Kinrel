import {
  IsString,
  IsNotEmpty,
  MinLength,
  MaxLength,
} from 'class-validator';

export class CreateRelationshipDto {
  @IsString()
  @IsNotEmpty({ message: 'fromPersonId is required' })
  @MinLength(1)
  fromPersonId!: string;

  @IsString()
  @IsNotEmpty({ message: 'toPersonId is required' })
  @MinLength(1)
  toPersonId!: string;

  @IsString()
  @IsNotEmpty({ message: 'Relationship type is required' })
  @MinLength(1, { message: 'Relationship type must not be empty' })
  @MaxLength(100, { message: 'Relationship type must not exceed 100 characters' })
  type!: string;
}
