import { IsISO8601, IsOptional, IsUUID } from 'class-validator';

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
