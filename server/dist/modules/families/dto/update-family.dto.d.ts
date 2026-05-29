import { CreateFamilyDto } from './create-family.dto';
declare const UpdateFamilyDto_base: import("@nestjs/mapped-types").MappedType<Partial<CreateFamilyDto>>;
export declare class UpdateFamilyDto extends UpdateFamilyDto_base {
    username?: string;
    avatarUrl?: string;
    region?: string;
}
export {};
