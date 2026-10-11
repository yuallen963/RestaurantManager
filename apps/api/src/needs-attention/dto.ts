import { InsightStatus } from '@prisma/client';
import { IsEnum, IsISO8601, IsOptional, IsUUID } from 'class-validator';

export class NeedsAttentionQuery {
  @IsUUID()
  restaurantLocationId!: string;

  @IsOptional()
  @IsISO8601()
  startDate?: string;

  @IsOptional()
  @IsISO8601()
  endDate?: string;
}

export class UpdateAttentionStatusDto {
  @IsEnum(InsightStatus)
  status!: InsightStatus;
}
