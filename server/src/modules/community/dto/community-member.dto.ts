import { ApiProperty } from '@nestjs/swagger';
import { IsString, IsIn } from 'class-validator';

export class UpdateMemberRoleDto {
  @ApiProperty({
    description: 'Member role',
    enum: ['member', 'moderator', 'admin'],
  })
  @IsString()
  @IsIn(['member', 'moderator', 'admin'])
  role!: string;
}
