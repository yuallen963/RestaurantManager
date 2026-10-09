CREATE TYPE "InvoiceIngestionSource" AS ENUM ('MANUAL_UPLOAD', 'EMAIL_FORWARD');

ALTER TABLE "RestaurantLocation" ADD COLUMN "invoiceEmailToken" TEXT;
UPDATE "RestaurantLocation" SET "invoiceEmailToken" = replace(gen_random_uuid()::text, '-', '') WHERE "invoiceEmailToken" IS NULL;
ALTER TABLE "RestaurantLocation" ALTER COLUMN "invoiceEmailToken" SET NOT NULL;
CREATE UNIQUE INDEX "RestaurantLocation_invoiceEmailToken_key" ON "RestaurantLocation"("invoiceEmailToken");

ALTER TABLE "Invoice"
  ADD COLUMN "ingestionSource" "InvoiceIngestionSource" NOT NULL DEFAULT 'MANUAL_UPLOAD',
  ADD COLUMN "inboundMessageId" TEXT,
  ADD COLUMN "inboundSender" TEXT,
  ADD COLUMN "inboundSubject" TEXT,
  ADD COLUMN "inboundReceivedAt" TIMESTAMP(3),
  ADD COLUMN "originalAttachmentName" TEXT,
  ADD COLUMN "attachmentHash" TEXT;

CREATE UNIQUE INDEX "Invoice_organizationId_restaurantLocationId_attachmentHash_key" ON "Invoice"("organizationId", "restaurantLocationId", "attachmentHash");
CREATE INDEX "Invoice_organizationId_restaurantLocationId_inboundMessageId_idx" ON "Invoice"("organizationId", "restaurantLocationId", "inboundMessageId");
