CREATE TYPE "InvoiceDuplicateResolution" AS ENUM ('UNRESOLVED', 'DUPLICATE', 'CONFIRMED_DISTINCT');

ALTER TABLE "Invoice"
  ADD COLUMN "duplicateFingerprint" TEXT,
  ADD COLUMN "reviewedIdentityKey" TEXT,
  ADD COLUMN "duplicateResolution" "InvoiceDuplicateResolution" NOT NULL DEFAULT 'UNRESOLVED',
  ADD COLUMN "duplicateOfInvoiceId" TEXT,
  ADD COLUMN "duplicateResolvedByUserId" TEXT,
  ADD COLUMN "duplicateResolvedAt" TIMESTAMP(3),
  ADD COLUMN "duplicateResolutionReason" TEXT,
  ADD COLUMN "duplicateDecisionFingerprint" TEXT;

CREATE UNIQUE INDEX "Invoice_organizationId_restaurantLocationId_reviewedIdentit_key"
  ON "Invoice"("organizationId", "restaurantLocationId", "reviewedIdentityKey");
CREATE INDEX "Invoice_organizationId_restaurantLocationId_duplicateFinger_idx"
  ON "Invoice"("organizationId", "restaurantLocationId", "duplicateFingerprint");

ALTER TABLE "Invoice" ADD CONSTRAINT "Invoice_duplicateOfInvoiceId_fkey"
  FOREIGN KEY ("duplicateOfInvoiceId") REFERENCES "Invoice"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- Historical rows remain unchanged. An explicit preflight identifies any
-- reviewed identity conflicts before this release starts assigning keys.
