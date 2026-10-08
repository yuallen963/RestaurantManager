CREATE TYPE "ExtractionStatus" AS ENUM ('NOT_STARTED', 'PROCESSING', 'COMPLETED', 'FAILED');
CREATE TYPE "ReviewStatus" AS ENUM ('NOT_REVIEWED', 'NEEDS_REVIEW', 'REVIEWED');

ALTER TABLE "Invoice"
  ADD COLUMN "extractedVendorName" TEXT,
  ADD COLUMN "extractionStatus" "ExtractionStatus" NOT NULL DEFAULT 'NOT_STARTED',
  ADD COLUMN "extractionProvider" TEXT,
  ADD COLUMN "extractionModel" TEXT,
  ADD COLUMN "extractionConfidence" DECIMAL(5,4),
  ADD COLUMN "extractionStartedAt" TIMESTAMP(3),
  ADD COLUMN "extractionCompletedAt" TIMESTAMP(3),
  ADD COLUMN "extractionError" TEXT,
  ADD COLUMN "rawExtractionJson" JSONB,
  ADD COLUMN "extractionUsage" JSONB,
  ADD COLUMN "reviewStatus" "ReviewStatus" NOT NULL DEFAULT 'NOT_REVIEWED',
  ADD COLUMN "reviewedAt" TIMESTAMP(3),
  ADD COLUMN "reviewedByUserId" TEXT;

ALTER TABLE "InvoiceLineItem"
  RENAME COLUMN "description" TO "rawDescription";
ALTER TABLE "InvoiceLineItem"
  ADD COLUMN "organizationId" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "restaurantLocationId" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "lineNumber" INTEGER,
  ADD COLUMN "normalizedName" TEXT,
  ADD COLUMN "sku" TEXT,
  ADD COLUMN "unit" TEXT,
  ADD COLUMN "packSize" TEXT,
  ADD COLUMN "extendedPrice" DECIMAL(14,2),
  ADD COLUMN "category" TEXT,
  ADD COLUMN "confidence" DECIMAL(5,4);

WITH numbered AS (
  SELECT "id", ROW_NUMBER() OVER (PARTITION BY "invoiceId" ORDER BY "createdAt", "id") AS number
  FROM "InvoiceLineItem"
)
UPDATE "InvoiceLineItem" item SET "lineNumber" = numbered.number
FROM numbered WHERE item."id" = numbered."id";

UPDATE "InvoiceLineItem" item
SET "organizationId" = invoice."organizationId",
    "restaurantLocationId" = invoice."restaurantLocationId"
FROM "Invoice" invoice WHERE item."invoiceId" = invoice."id";

ALTER TABLE "InvoiceLineItem" ALTER COLUMN "lineNumber" SET NOT NULL;
ALTER TABLE "InvoiceLineItem" ALTER COLUMN "organizationId" DROP DEFAULT;
ALTER TABLE "InvoiceLineItem" ALTER COLUMN "restaurantLocationId" DROP DEFAULT;
ALTER TABLE "InvoiceLineItem" ALTER COLUMN "quantity" DROP NOT NULL;
ALTER TABLE "InvoiceLineItem" ALTER COLUMN "unitPrice" DROP NOT NULL;

ALTER TABLE "InvoiceLineItem" ADD CONSTRAINT "InvoiceLineItem_invoiceId_fkey"
  FOREIGN KEY ("invoiceId") REFERENCES "Invoice"("id") ON DELETE CASCADE ON UPDATE CASCADE;
CREATE UNIQUE INDEX "InvoiceLineItem_invoiceId_lineNumber_key" ON "InvoiceLineItem"("invoiceId", "lineNumber");
CREATE INDEX "InvoiceLineItem_organizationId_restaurantLocationId_idx" ON "InvoiceLineItem"("organizationId", "restaurantLocationId");
