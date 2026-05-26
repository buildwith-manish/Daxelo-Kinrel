import { IsString, IsIn } from 'class-validator';

export class JoinCommunityDto {
  @IsString()
  @IsIn(['join', 'leave'])
  action!: 'join' | 'leave';
}
