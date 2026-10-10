ALTER TABLE "Invoice"
  ADD COLUMN "extractedVendorAddress" TEXT,
  ADD COLUMN "dueDate" TIMESTAMP(3),
  ADD COLUMN "otherFees" DECIMAL(14,2),
  ADD COLUMN "currency" TEXT,
  ADD COLUMN "extractionDurationMs" INTEGER,
  ADD COLUMN "extractionAttemptCount" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "uncertainFields" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

ALTER TABLE "InvoiceLineItem"
  ADD COLUMN "packCount" DECIMAL(14,3),
  ADD COLUMN "packUnitQuantity" DECIMAL(14,3),
  ADD COLUMN "measurementUnit" TEXT,
  ADD COLUMN "totalPackageQuantity" DECIMAL(14,3),
  ADD COLUMN "productAttributes" JSONB,
  ADD COLUMN "sourcePage" INTEGER,
  ADD COLUMN "uncertainFields" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
