import { ArrayUnique, IsArray, IsIn, IsInt, IsOptional, IsString, Max, Min, MinLength } from 'class-validator';

export const onboardingDataSources = ['INVOICES', 'POS', 'BANK'] as const;

export class UpdateOnboardingDto {
  @IsInt() @Min(1) @Max(6) currentStep!: number;
  @IsOptional() @IsArray() @ArrayUnique() @IsIn(onboardingDataSources, { each: true }) selectedDataSources?: string[];
}

export class SetupRestaurantDto {
  @IsString() @MinLength(2) organizationName!: string;
  @IsString() @MinLength(2) locationName!: string;
  @IsOptional() @IsString() addressLine1?: string;
  @IsOptional() @IsString() city?: string;
  @IsOptional() @IsString() state?: string;
  @IsOptional() @IsString() postalCode?: string;
  @IsString() @MinLength(3) timezone!: string;
}
