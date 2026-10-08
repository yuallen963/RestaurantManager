import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';

export enum PriceChangeSort {
  LARGEST_PERCENT_INCREASE = 'largestPercentIncrease',
  LARGEST_MONTHLY_IMPACT = 'largestMonthlyImpact',
  MOST_RECENT = 'mostRecent',
  VENDOR = 'vendor',
}

export enum PriceChangeDirection {
  INCREASE = 'increase',
  DECREASE = 'decrease',
}

export class PriceIntelligenceQuery {
  @IsUUID()
  restaurantLocationId!: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(30)
  @Max(365)
  lookbackDays = 90;

  @IsOptional()
  @IsEnum(PriceChangeSort)
  sort = PriceChangeSort.LARGEST_PERCENT_INCREASE;

  @IsOptional()
  @IsUUID()
  vendorId?: string;

  @IsOptional()
  @IsEnum(PriceChangeDirection)
  direction?: PriceChangeDirection;
}

export class PriceHistoryQuery {
  @IsUUID()
  restaurantLocationId!: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(30)
  @Max(365)
  lookbackDays = 90;
}
