CREATE TYPE "ManualRevenueType" AS ENUM ('CASH', 'CARD', 'ONLINE', 'OTHER');

ALTER TABLE "RevenueEntry"
ADD COLUMN "manualType" "ManualRevenueType",
ADD COLUMN "additionalToPos" BOOLEAN NOT NULL DEFAULT false;

-- New manual entries are one total per restaurant, business date, and sales
-- channel. Existing rows have a NULL manualType and remain untouched.
CREATE UNIQUE INDEX "RevenueEntry_manual_business_day_key"
ON "RevenueEntry"("organizationId", "restaurantLocationId", "date", "source", "manualType", "additionalToPos");
