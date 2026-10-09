import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';

export class SavingsOpportunitiesQuery {
  @IsUUID()
  restaurantLocationId!: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(30)
  @Max(365)
  lookbackDays = 90;
}
