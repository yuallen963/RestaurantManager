import { BankReconciliationStatus, MerchantRuleMatchType } from '@prisma/client';
import { IsBoolean, IsEnum, IsOptional, IsString, IsUUID } from 'class-validator';

export class OrganizationDto { @IsUUID() organizationId!: string; }
export class ExchangeBankTokenDto extends OrganizationDto { @IsString() publicToken!: string; @IsOptional() @IsUUID() restaurantLocationId?: string; }
export class AssignBankAccountDto { @IsOptional() @IsUUID() restaurantLocationId?: string | null; @IsOptional() @IsBoolean() active?: boolean; }
export class BankTransactionQuery extends OrganizationDto { @IsOptional() @IsUUID() restaurantLocationId?: string; @IsOptional() @IsEnum(BankReconciliationStatus) status?: BankReconciliationStatus; }
export class ReviewBankTransactionDto {
  @IsOptional() @IsUUID() vendorId?: string | null;
  @IsOptional() @IsUUID() categoryId?: string | null;
  @IsOptional() @IsUUID() restaurantLocationId?: string | null;
  @IsOptional() @IsBoolean() ignored?: boolean;
  @IsOptional() @IsBoolean() createMerchantRule?: boolean;
  @IsOptional() @IsEnum(MerchantRuleMatchType) ruleMatchType?: MerchantRuleMatchType;
}
export class ConfirmInvoiceMatchDto { @IsUUID() invoiceId!: string; }

