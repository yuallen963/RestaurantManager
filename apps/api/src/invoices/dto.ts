import { Type } from 'class-transformer';
import { IsDateString, IsEnum, IsInt, IsOptional, IsString, IsUUID, Max, Min, MinLength } from 'class-validator';
import { InvoiceStatus } from '@prisma/client';
export class UploadIntentDto { @IsUUID() restaurantLocationId!: string; @IsString() @MinLength(1) fileName!: string; @IsString() mimeType!: string; @Type(() => Number) @IsInt() @Min(1) @Max(15 * 1024 * 1024) fileSize!: number; @IsOptional() @IsUUID() vendorId?: string; }
export class CompleteUploadDto { @IsString() @MinLength(1) etag!: string; }
export class InvoiceListQuery { @IsUUID() restaurantLocationId!: string; @IsOptional() @IsDateString() startDate?: string; @IsOptional() @IsDateString() endDate?: string; @IsOptional() @IsUUID() vendorId?: string; @IsOptional() @IsEnum(InvoiceStatus) status?: InvoiceStatus; }
export class UpdateInvoiceDto { @IsOptional() @IsUUID() vendorId?: string | null; @IsOptional() @IsString() invoiceNumber?: string | null; @IsOptional() @IsDateString() invoiceDate?: string | null; @IsOptional() @IsString() subtotal?: string | number | null; @IsOptional() @IsString() tax?: string | number | null; @IsOptional() @IsString() total?: string | number | null; @IsOptional() @IsString() notes?: string | null; @IsOptional() @IsEnum(InvoiceStatus) status?: InvoiceStatus; }
