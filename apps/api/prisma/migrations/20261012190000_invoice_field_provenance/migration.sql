ALTER TABLE "Invoice"
ADD COLUMN "discount" DECIMAL(14,2),
ADD COLUMN "fieldProvenance" JSONB;

ALTER TABLE "InvoiceLineItem"
ADD COLUMN "fieldProvenance" JSONB;
