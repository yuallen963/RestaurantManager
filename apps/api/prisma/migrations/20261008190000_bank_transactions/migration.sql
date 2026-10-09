CREATE TYPE "BankProvider" AS ENUM ('PLAID', 'DEMO');
CREATE TYPE "BankConnectionStatus" AS ENUM ('CONNECTED', 'SYNCING', 'NEEDS_ATTENTION', 'DISCONNECTED', 'ERROR');
CREATE TYPE "BankReconciliationStatus" AS ENUM ('UNMATCHED', 'MATCHED_INVOICE', 'MATCHED_EXPENSE', 'NEEDS_REVIEW', 'IGNORED');
CREATE TYPE "BankCategorizationSource" AS ENUM ('PROVIDER', 'MERCHANT_RULE', 'USER_RULE', 'INVOICE_MATCH', 'MANUAL', 'UNRESOLVED');
CREATE TYPE "InvoiceMatchConfidence" AS ENUM ('EXACT', 'LIKELY', 'NO_MATCH');
CREATE TYPE "MerchantRuleMatchType" AS ENUM ('EXACT', 'PREFIX', 'CONTAINS');

CREATE TABLE "BankConnection" (
  "id" TEXT NOT NULL,
  "organizationId" TEXT NOT NULL,
  "provider" "BankProvider" NOT NULL,
  "providerItemId" TEXT NOT NULL,
  "encryptedAccessToken" TEXT NOT NULL,
  "institutionId" TEXT,
  "institutionName" TEXT,
  "status" "BankConnectionStatus" NOT NULL DEFAULT 'CONNECTED',
  "syncCursor" TEXT,
  "lastSyncAt" TIMESTAMP(3),
  "lastError" TEXT,
  "createdByUserId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "BankConnection_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "BankAccount" (
  "id" TEXT NOT NULL,
  "bankConnectionId" TEXT NOT NULL,
  "organizationId" TEXT NOT NULL,
  "restaurantLocationId" TEXT,
  "providerAccountId" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "mask" TEXT,
  "subtype" TEXT,
  "type" TEXT,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "BankAccount_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "BankTransaction" (
  "id" TEXT NOT NULL,
  "organizationId" TEXT NOT NULL,
  "restaurantLocationId" TEXT,
  "bankAccountId" TEXT NOT NULL,
  "providerTransactionId" TEXT NOT NULL,
  "postedDate" TIMESTAMP(3) NOT NULL,
  "authorizedDate" TIMESTAMP(3),
  "merchantNameRaw" TEXT,
  "merchantNameNormalized" TEXT,
  "description" TEXT NOT NULL,
  "amount" DECIMAL(14,2) NOT NULL,
  "pending" BOOLEAN NOT NULL DEFAULT false,
  "providerCategory" TEXT,
  "providerCategoryId" TEXT,
  "categoryId" TEXT,
  "vendorId" TEXT,
  "invoiceId" TEXT,
  "suggestedInvoiceId" TEXT,
  "expenseId" TEXT,
  "matchConfidence" "InvoiceMatchConfidence" NOT NULL DEFAULT 'NO_MATCH',
  "reconciliationStatus" "BankReconciliationStatus" NOT NULL DEFAULT 'UNMATCHED',
  "categorizationSource" "BankCategorizationSource" NOT NULL DEFAULT 'UNRESOLVED',
  "removedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "BankTransaction_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "MerchantRule" (
  "id" TEXT NOT NULL,
  "organizationId" TEXT NOT NULL,
  "matchType" "MerchantRuleMatchType" NOT NULL,
  "matchValue" TEXT NOT NULL,
  "normalizedMerchantName" TEXT NOT NULL,
  "vendorId" TEXT,
  "expenseCategoryId" TEXT,
  "restaurantLocationId" TEXT,
  "createdByUserId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "MerchantRule_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "BankConnection_provider_providerItemId_key" ON "BankConnection"("provider", "providerItemId");
CREATE INDEX "BankConnection_organizationId_status_idx" ON "BankConnection"("organizationId", "status");
CREATE UNIQUE INDEX "BankAccount_bankConnectionId_providerAccountId_key" ON "BankAccount"("bankConnectionId", "providerAccountId");
CREATE INDEX "BankAccount_organizationId_restaurantLocationId_idx" ON "BankAccount"("organizationId", "restaurantLocationId");
CREATE UNIQUE INDEX "BankTransaction_bankAccountId_providerTransactionId_key" ON "BankTransaction"("bankAccountId", "providerTransactionId");
CREATE INDEX "BankTransaction_organizationId_restaurantLocationId_reconciliationStatus_postedDate_idx" ON "BankTransaction"("organizationId", "restaurantLocationId", "reconciliationStatus", "postedDate");
CREATE INDEX "BankTransaction_invoiceId_idx" ON "BankTransaction"("invoiceId");
CREATE INDEX "BankTransaction_suggestedInvoiceId_idx" ON "BankTransaction"("suggestedInvoiceId");
CREATE INDEX "MerchantRule_organizationId_restaurantLocationId_matchType_matchValue_idx" ON "MerchantRule"("organizationId", "restaurantLocationId", "matchType", "matchValue");

ALTER TABLE "BankConnection" ADD CONSTRAINT "BankConnection_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "BankConnection" ADD CONSTRAINT "BankConnection_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "BankAccount" ADD CONSTRAINT "BankAccount_bankConnectionId_fkey" FOREIGN KEY ("bankConnectionId") REFERENCES "BankConnection"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "BankAccount" ADD CONSTRAINT "BankAccount_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "BankAccount" ADD CONSTRAINT "BankAccount_restaurantLocationId_fkey" FOREIGN KEY ("restaurantLocationId") REFERENCES "RestaurantLocation"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "BankTransaction" ADD CONSTRAINT "BankTransaction_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "BankTransaction" ADD CONSTRAINT "BankTransaction_restaurantLocationId_fkey" FOREIGN KEY ("restaurantLocationId") REFERENCES "RestaurantLocation"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "BankTransaction" ADD CONSTRAINT "BankTransaction_bankAccountId_fkey" FOREIGN KEY ("bankAccountId") REFERENCES "BankAccount"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "BankTransaction" ADD CONSTRAINT "BankTransaction_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "ExpenseCategory"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "BankTransaction" ADD CONSTRAINT "BankTransaction_vendorId_fkey" FOREIGN KEY ("vendorId") REFERENCES "Vendor"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "BankTransaction" ADD CONSTRAINT "BankTransaction_invoiceId_fkey" FOREIGN KEY ("invoiceId") REFERENCES "Invoice"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "BankTransaction" ADD CONSTRAINT "BankTransaction_expenseId_fkey" FOREIGN KEY ("expenseId") REFERENCES "Expense"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "MerchantRule" ADD CONSTRAINT "MerchantRule_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "MerchantRule" ADD CONSTRAINT "MerchantRule_vendorId_fkey" FOREIGN KEY ("vendorId") REFERENCES "Vendor"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "MerchantRule" ADD CONSTRAINT "MerchantRule_expenseCategoryId_fkey" FOREIGN KEY ("expenseCategoryId") REFERENCES "ExpenseCategory"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "MerchantRule" ADD CONSTRAINT "MerchantRule_restaurantLocationId_fkey" FOREIGN KEY ("restaurantLocationId") REFERENCES "RestaurantLocation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "MerchantRule" ADD CONSTRAINT "MerchantRule_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
