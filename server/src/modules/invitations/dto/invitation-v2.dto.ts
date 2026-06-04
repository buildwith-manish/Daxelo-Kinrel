import {
  IsString,
  IsOptional,
  IsEnum,
  IsInt,
  Min,
  Max,
  IsDateString,
  MaxLength,
  IsNotEmpty,
} from 'class-validator';

// ── Enums ──────────────────────────────────────────────────────────

export enum InviteChannel {
  FAMILY_ID = 'family_id',
  QR_CODE = 'qr_code',
  LINK = 'link',
}

export enum InviteStatus {
  PENDING = 'pending',
  ACCEPTED = 'accepted',
  REJECTED = 'rejected',
  EXPIRED = 'expired',
  CANCELLED = 'cancelled',
}

export enum MemberRole {
  ADMIN = 'admin',
  EDITOR = 'editor',
  MEMBER = 'member',
  VIEWER = 'viewer',
}

// ── Create Family ID Invite DTO ────────────────────────────────────

export class CreateFamilyIdInviteDto {
  @IsString()
  @IsNotEmpty()
  familyId: string;

  @IsOptional()
  @IsEnum(MemberRole)
  role?: MemberRole;
}

// ── QR Code Invite Options ─────────────────────────────────────────

export class CreateQrCodeInviteDto {
  @IsString()
  @IsNotEmpty()
  familyId: string;

  @IsOptional()
  @IsDateString()
  expiresIn?: string; // ISO duration or days, default 7d

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  maxUses?: number; // default 10

  @IsOptional()
  @IsString()
  @MaxLength(100)
  preFilledName?: string;

  @IsOptional()
  @IsEnum(MemberRole)
  role?: MemberRole;
}

// ── Link Invite Options ────────────────────────────────────────────

export class CreateLinkInviteDto {
  @IsString()
  @IsNotEmpty()
  familyId: string;

  @IsOptional()
  @IsDateString()
  expiresIn?: string; // ISO duration or days, default 7d

  @IsOptional()
  @IsInt()
  @Min(0)
  maxUses?: number; // default 0 = unlimited

  @IsOptional()
  @IsString()
  @MaxLength(100)
  preFilledName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  suggestedRelation?: string;

  @IsOptional()
  @IsEnum(MemberRole)
  role?: MemberRole;
}

// ── Accept Invite DTO ──────────────────────────────────────────────

export class AcceptInviteDto {
  @IsString()
  @IsNotEmpty()
  inviteCodeOrToken: string;
}

// ── Reject Invite DTO ──────────────────────────────────────────────

export class RejectInviteDto {
  // Route param :id is used — no body needed
}

// ── Result Types (exported for use in service) ─────────────────────

export interface InviteResult {
  inviteCode: string;
  familyId: string;
  familyName: string;
  expiresAt: Date | null;
}

export interface QrInviteResult {
  qrData: string; // deep link URL: kinrel://invite/{inviteCode}
  inviteCode: string;
  familyId: string;
  familyName: string;
  expiresAt: Date | null;
}

export interface LinkInviteResult {
  shareUrl: string; // https://kinrel.app/invite/{token}
  token: string;
  familyId: string;
  familyName: string;
  expiresAt: Date | null;
}

export interface AcceptInviteResult {
  familyId: string;
  familyName: string;
  role: string;
  personId: string;
}

export interface InvitationDetail {
  id: string;
  familyId: string;
  familyName: string;
  inviterName: string;
  status: string;
  role: string;
  channel: string;
  createdAt: Date;
  expiresAt: Date | null;
}
