CREATE TYPE "MerchantRuleDecision" AS ENUM ('EXPENSE', 'PERSONAL_TRANSFER');
CREATE TYPE "BankTransactionDirection" AS ENUM ('OUTFLOW', 'INFLOW');

ALTER TABLE "MerchantRule"
ADD COLUMN "bankAccountId" TEXT,
ADD COLUMN "direction" "BankTransactionDirection",
ADD COLUMN "providerCategoryId" TEXT,
ADD COLUMN "decision" "MerchantRuleDecision" NOT NULL DEFAULT 'EXPENSE';

ALTER TABLE "BankTransaction"
ADD COLUMN "pendingReviewDecision" "MerchantRuleDecision";

ALTER TABLE "MerchantRule"
ADD CONSTRAINT "MerchantRule_bankAccountId_fkey"
FOREIGN KEY ("bankAccountId") REFERENCES "BankAccount"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE INDEX "MerchantRule_bankAccountId_direction_providerCategoryId_idx"
ON "MerchantRule"("bankAccountId", "direction", "providerCategoryId");
