CREATE TYPE "InvoiceStatus" AS ENUM ('UPLOADED', 'PROCESSING', 'COMPLETED', 'FAILED');

ALTER TABLE "Invoice"
  ADD COLUMN "fileName" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "originalFileName" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "fileType" TEXT NOT NULL DEFAULT 'application/octet-stream',
  ADD COLUMN "fileSize" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "storageKey" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "invoiceNumber" TEXT,
  ADD COLUMN "invoiceDate" TIMESTAMP(3),
  ADD COLUMN "subtotal" DECIMAL(14,2),
  ADD COLUMN "tax" DECIMAL(14,2),
  ADD COLUMN "total" DECIMAL(14,2),
  ADD COLUMN "notes" TEXT,
  ADD COLUMN "status" "InvoiceStatus" NOT NULL DEFAULT 'UPLOADED',
  ADD COLUMN "createdByUserId" TEXT NOT NULL DEFAULT '';

ALTER TABLE "Invoice" ALTER COLUMN "fileName" DROP DEFAULT;
ALTER TABLE "Invoice" ALTER COLUMN "originalFileName" DROP DEFAULT;
ALTER TABLE "Invoice" ALTER COLUMN "fileType" DROP DEFAULT;
ALTER TABLE "Invoice" ALTER COLUMN "fileSize" DROP DEFAULT;
ALTER TABLE "Invoice" ALTER COLUMN "storageKey" DROP DEFAULT;
ALTER TABLE "Invoice" ALTER COLUMN "createdByUserId" DROP DEFAULT;

CREATE INDEX "Invoice_restaurantLocationId_invoiceDate_idx" ON "Invoice"("restaurantLocationId", "invoiceDate");
