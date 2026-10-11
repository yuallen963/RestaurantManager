import { IsNotEmpty, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';

export class CreateLocationDto {
  @IsString() @IsNotEmpty() @MinLength(2) @MaxLength(120) name!: string;
  @IsString() @IsNotEmpty() @MaxLength(180) addressLine1!: string;
  @IsString() @IsNotEmpty() @MaxLength(100) city!: string;
  @IsString() @Matches(/^[A-Za-z]{2}$/, { message: 'state must be a two-letter code' }) state!: string;
  @IsString() @Matches(/^\d{5}(?:-\d{4})?$/, { message: 'postalCode must be a US ZIP code' }) postalCode!: string;
  @IsString() @IsNotEmpty() @MaxLength(100) timezone!: string;
}

export class UpdateLocationDto {
  @IsOptional() @IsString() @IsNotEmpty() @MinLength(2) @MaxLength(120) name?: string;
  @IsOptional() @IsString() @IsNotEmpty() @MaxLength(180) addressLine1?: string;
  @IsOptional() @IsString() @IsNotEmpty() @MaxLength(100) city?: string;
  @IsOptional() @IsString() @Matches(/^[A-Za-z]{2}$/, { message: 'state must be a two-letter code' }) state?: string;
  @IsOptional() @IsString() @Matches(/^\d{5}(?:-\d{4})?$/, { message: 'postalCode must be a US ZIP code' }) postalCode?: string;
  @IsOptional() @IsString() @IsNotEmpty() @MaxLength(100) timezone?: string;
}
