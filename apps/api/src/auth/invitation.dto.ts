import { BetaInvitationType, OrganizationRole } from '@prisma/client';
import { IsEmail, IsEnum, IsInt, IsOptional, IsString, IsUUID, Max, Min, MinLength, ValidateIf } from 'class-validator';

export class CreateBetaInvitationDto {
  @IsEmail() email!: string;
  @IsEnum(BetaInvitationType) type!: BetaInvitationType;
  @ValidateIf((value) => value.type === BetaInvitationType.JOIN_ORGANIZATION)
  @IsUUID()
  organizationId?: string;
  @ValidateIf((value) => value.type === BetaInvitationType.NEW_ORGANIZATION)
  @IsString()
  @MinLength(2)
  organizationName?: string;
  @IsOptional()
  @IsEnum(OrganizationRole)
  role?: OrganizationRole;
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(30)
  expiresInDays?: number;
}
