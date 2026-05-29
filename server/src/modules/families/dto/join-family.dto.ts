import { IsString, IsOptional, IsIn, Matches } from 'class-validator';

/**
 * DTO for joining a family using a Family ID.
 *
 * Family ID format: KIN-XXXXXXXX where X is [A-Z0-9]
 * Example: KIN-AB12CD34
 *
 * 8 chars × 36 possible values = ~2.8 trillion possible IDs
 * (collision extremely unlikely at any realistic scale)
 */
export class JoinFamilyDto {
  @IsString()
  @Matches(/^KIN-[A-Z0-9]{8}$/, {
    message:
      'Family ID must follow the format KIN-XXXXXXXX (e.g. KIN-AB12CD34)',
  })
  familyId!: string;

  @IsOptional()
  @IsIn(['admin', 'member', 'viewer'], {
    message: 'Role must be one of: admin, member, viewer',
  })
  role?: string;
}

/**
 * DTO for searching a family by its Family ID.
 */
export class SearchFamilyDto {
  @IsString()
  @Matches(/^KIN-[A-Z0-9]{8}$/, {
    message:
      'Family ID must follow the format KIN-XXXXXXXX (e.g. KIN-AB12CD34)',
  })
  familyId!: string;
}
