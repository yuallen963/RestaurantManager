CREATE TYPE "ProductMatchStatus" AS ENUM ('PENDING', 'CONFIRMED', 'REJECTED');
CREATE TYPE "ProductMatchConfidence" AS ENUM ('HIGH', 'MEDIUM', 'LOW');

CREATE TABLE "ProductGroup" (
  "id" TEXT NOT NULL,
  "organizationId" TEXT NOT NULL,
  "restaurantLocationId" TEXT NOT NULL,
  "displayName" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ProductGroup_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "ProductGroupMember" (
  "id" TEXT NOT NULL,
  "productGroupId" TEXT NOT NULL,
  "invoiceLineItemId" TEXT NOT NULL,
  "vendorId" TEXT NOT NULL,
  "confirmed" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ProductGroupMember_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "ProductMatchDecision" (
  "id" TEXT NOT NULL,
  "organizationId" TEXT NOT NULL,
  "restaurantLocationId" TEXT NOT NULL,
  "candidateLineItemAId" TEXT NOT NULL,
  "candidateLineItemBId" TEXT NOT NULL,
  "status" "ProductMatchStatus" NOT NULL DEFAULT 'PENDING',
  "confidence" "ProductMatchConfidence" NOT NULL,
  "reason" TEXT NOT NULL,
  "productGroupId" TEXT,
  "reviewedByUserId" TEXT,
  "reviewedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ProductMatchDecision_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "ProductGroup_organizationId_restaurantLocationId_idx" ON "ProductGroup"("organizationId", "restaurantLocationId");
CREATE UNIQUE INDEX "ProductGroupMember_productGroupId_invoiceLineItemId_key" ON "ProductGroupMember"("productGroupId", "invoiceLineItemId");
CREATE INDEX "ProductGroupMember_invoiceLineItemId_idx" ON "ProductGroupMember"("invoiceLineItemId");
CREATE INDEX "ProductGroupMember_vendorId_idx" ON "ProductGroupMember"("vendorId");
CREATE UNIQUE INDEX "ProductMatchDecision_candidateLineItemAId_candidateLineItemBId_key" ON "ProductMatchDecision"("candidateLineItemAId", "candidateLineItemBId");
CREATE INDEX "ProductMatchDecision_organizationId_restaurantLocationId_status_idx" ON "ProductMatchDecision"("organizationId", "restaurantLocationId", "status");
ALTER TABLE "ProductGroup" ADD CONSTRAINT "ProductGroup_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ProductGroup" ADD CONSTRAINT "ProductGroup_restaurantLocationId_fkey" FOREIGN KEY ("restaurantLocationId") REFERENCES "RestaurantLocation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ProductGroupMember" ADD CONSTRAINT "ProductGroupMember_productGroupId_fkey" FOREIGN KEY ("productGroupId") REFERENCES "ProductGroup"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ProductGroupMember" ADD CONSTRAINT "ProductGroupMember_invoiceLineItemId_fkey" FOREIGN KEY ("invoiceLineItemId") REFERENCES "InvoiceLineItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ProductGroupMember" ADD CONSTRAINT "ProductGroupMember_vendorId_fkey" FOREIGN KEY ("vendorId") REFERENCES "Vendor"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ProductMatchDecision" ADD CONSTRAINT "ProductMatchDecision_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ProductMatchDecision" ADD CONSTRAINT "ProductMatchDecision_restaurantLocationId_fkey" FOREIGN KEY ("restaurantLocationId") REFERENCES "RestaurantLocation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ProductMatchDecision" ADD CONSTRAINT "ProductMatchDecision_candidateLineItemAId_fkey" FOREIGN KEY ("candidateLineItemAId") REFERENCES "InvoiceLineItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ProductMatchDecision" ADD CONSTRAINT "ProductMatchDecision_candidateLineItemBId_fkey" FOREIGN KEY ("candidateLineItemBId") REFERENCES "InvoiceLineItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ProductMatchDecision" ADD CONSTRAINT "ProductMatchDecision_productGroupId_fkey" FOREIGN KEY ("productGroupId") REFERENCES "ProductGroup"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "ProductMatchDecision" ADD CONSTRAINT "ProductMatchDecision_reviewedByUserId_fkey" FOREIGN KEY ("reviewedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "Invoice" ADD CONSTRAINT "Invoice_vendorId_fkey" FOREIGN KEY ("vendorId") REFERENCES "Vendor"("id") ON DELETE SET NULL ON UPDATE CASCADE;
