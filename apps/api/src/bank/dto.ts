import { BankReconciliationStatus, MerchantRuleMatchType } from '@prisma/client';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsEnum, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export enum BankReviewDecision { EXPENSE = 'EXPENSE', PERSONAL_TRANSFER = 'PERSONAL_TRANSFER', REVIEW_LATER = 'REVIEW_LATER' }

export class OrganizationDto { @IsUUID() organizationId!: string; }
export class BankSyncStatusQuery extends OrganizationDto { @IsUUID() restaurantLocationId!: string; }
export class ExchangeBankTokenDto extends OrganizationDto { @IsString() publicToken!: string; @IsOptional() @IsUUID() restaurantLocationId?: string; }
export class AssignBankAccountDto { @IsOptional() @IsUUID() restaurantLocationId?: string | null; @IsOptional() @IsBoolean() active?: boolean; }
export class BankTransactionQuery extends OrganizationDto { @IsOptional() @IsUUID() restaurantLocationId?: string; @IsOptional() @IsEnum(BankReconciliationStatus) status?: BankReconciliationStatus; }
export class ReviewBankTransactionDto {
  @IsOptional() @IsEnum(BankReviewDecision) decision?: BankReviewDecision;
  @IsOptional() @IsUUID() vendorId?: string | null;
  @IsOptional() @IsUUID() categoryId?: string | null;
  @IsOptional() @IsUUID() restaurantLocationId?: string | null;
  @IsOptional() @IsBoolean() ignored?: boolean;
  @IsOptional() @IsBoolean() createMerchantRule?: boolean;
  @IsOptional() @IsBoolean() autoConfirmFuture?: boolean;
  @IsOptional() @IsNumber() @Min(0) minimumAmount?: number;
  @IsOptional() @IsNumber() @Min(0) maximumAmount?: number;
  @IsOptional() @IsEnum(MerchantRuleMatchType) ruleMatchType?: MerchantRuleMatchType;
}
export class BulkReviewBankTransactionsDto extends ReviewBankTransactionDto {
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(500) @IsUUID('4', { each: true }) ids!: string[];
  @IsOptional() @IsUUID() groupAnchorId?: string;
}
export class UpdateMerchantRuleDto {
  @IsOptional() @IsBoolean() active?: boolean;
  @IsOptional() @IsBoolean() autoConfirm?: boolean;
  @IsOptional() @IsUUID() vendorId?: string | null;
  @IsOptional() @IsUUID() categoryId?: string | null;
  @IsOptional() @IsNumber() @Min(0) minimumAmount?: number | null;
  @IsOptional() @IsNumber() @Min(0) maximumAmount?: number | null;
}
export class ConfirmInvoiceMatchDto { @IsUUID() invoiceId!: string; }

