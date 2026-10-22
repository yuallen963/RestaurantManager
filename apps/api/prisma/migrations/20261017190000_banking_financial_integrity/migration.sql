-- Refuse deployment if historical rows already violate the invariants. This
-- migration never rewrites or reclassifies financial data.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "BankTransaction"
    WHERE
      ("reconciliationStatus" = 'MATCHED_EXPENSE' AND ("expenseId" IS NULL OR "invoiceId" IS NOT NULL))
      OR ("reconciliationStatus" = 'MATCHED_INVOICE' AND ("invoiceId" IS NULL OR "expenseId" IS NOT NULL))
      OR ("reconciliationStatus" NOT IN ('MATCHED_EXPENSE', 'MATCHED_INVOICE') AND ("expenseId" IS NOT NULL OR "invoiceId" IS NOT NULL))
  ) THEN
    RAISE EXCEPTION 'Bank transaction reconciliation links must be repaired before migration';
  END IF;

  IF EXISTS (
    SELECT "invoiceId"
    FROM "BankTransaction"
    WHERE "invoiceId" IS NOT NULL
      AND "reconciliationStatus" = 'MATCHED_INVOICE'
      AND "removedAt" IS NULL
    GROUP BY "invoiceId"
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'An invoice is linked to more than one active bank transaction';
  END IF;

  IF EXISTS (
    SELECT "expenseId"
    FROM "BankTransaction"
    WHERE "expenseId" IS NOT NULL
      AND "reconciliationStatus" = 'MATCHED_EXPENSE'
      AND "removedAt" IS NULL
    GROUP BY "expenseId"
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'An expense is linked to more than one active bank transaction';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM "BankTransaction" bt
    JOIN "Expense" expense ON expense."id" = bt."expenseId"
    WHERE bt."organizationId" <> expense."organizationId"
      OR bt."restaurantLocationId" IS DISTINCT FROM expense."restaurantLocationId"
  ) THEN
    RAISE EXCEPTION 'A bank transaction expense link crosses an organization or restaurant location';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM "BankTransaction" bt
    JOIN "Invoice" invoice ON invoice."id" = bt."invoiceId"
    WHERE bt."organizationId" <> invoice."organizationId"
      OR bt."restaurantLocationId" IS DISTINCT FROM invoice."restaurantLocationId"
  ) THEN
    RAISE EXCEPTION 'A bank transaction invoice link crosses an organization or restaurant location';
  END IF;
END $$;

ALTER TABLE "BankTransaction"
ADD CONSTRAINT "BankTransaction_reconciliation_links_check"
CHECK (
  ("reconciliationStatus" = 'MATCHED_EXPENSE' AND "expenseId" IS NOT NULL AND "invoiceId" IS NULL)
  OR ("reconciliationStatus" = 'MATCHED_INVOICE' AND "invoiceId" IS NOT NULL AND "expenseId" IS NULL)
  OR ("reconciliationStatus" NOT IN ('MATCHED_EXPENSE', 'MATCHED_INVOICE') AND "expenseId" IS NULL AND "invoiceId" IS NULL)
);

CREATE INDEX "BankTransaction_expenseId_idx"
ON "BankTransaction"("expenseId");

CREATE UNIQUE INDEX "BankTransaction_active_matched_invoice_key"
ON "BankTransaction"("invoiceId")
WHERE "invoiceId" IS NOT NULL
  AND "reconciliationStatus" = 'MATCHED_INVOICE'
  AND "removedAt" IS NULL;

CREATE UNIQUE INDEX "BankTransaction_active_matched_expense_key"
ON "BankTransaction"("expenseId")
WHERE "expenseId" IS NOT NULL
  AND "reconciliationStatus" = 'MATCHED_EXPENSE'
  AND "removedAt" IS NULL;
