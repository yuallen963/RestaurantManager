import { IsBoolean, IsIn, IsOptional, IsString, IsUUID } from 'class-validator';

export class PosOrganizationDto { @IsUUID() organizationId!: string; }
export class PosMapLocationDto {
  @IsUUID() restaurantLocationId!: string;
  @IsString() providerLocationId!: string;
  @IsOptional() @IsBoolean() active?: boolean;
}
export class ResolveRevenueConflictDto { @IsIn(['MANUAL', 'SQUARE']) resolution!: 'MANUAL' | 'SQUARE'; }
