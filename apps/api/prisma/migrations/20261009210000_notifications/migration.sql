CREATE TYPE "NotificationType" AS ENUM ('PRICE_INCREASE','SAVINGS_OPPORTUNITY','FOOD_COST_DETERIORATION','LABOR_COST_DETERIORATION','VENDOR_SPEND_INCREASE','CATEGORY_SPEND_INCREASE','INVOICE_EXTRACTION_FAILED','BANK_SYNC_FAILED','BANK_REAUTH_REQUIRED','POS_SYNC_FAILED','POS_REAUTH_REQUIRED','WEEKLY_DIGEST');
CREATE TYPE "NotificationSeverity" AS ENUM ('LOW','MEDIUM','HIGH','CRITICAL');
CREATE TYPE "DevicePushPlatform" AS ENUM ('IOS','ANDROID','WEB');

ALTER TABLE "Notification" ADD COLUMN "organizationId" TEXT;
ALTER TABLE "Notification" ADD COLUMN "restaurantLocationId" TEXT;
ALTER TABLE "Notification" ADD COLUMN "type" "NotificationType";
ALTER TABLE "Notification" ADD COLUMN "severity" "NotificationSeverity";
ALTER TABLE "Notification" ADD COLUMN "deepLinkType" TEXT;
ALTER TABLE "Notification" ADD COLUMN "deepLinkId" TEXT;
ALTER TABLE "Notification" ADD COLUMN "deliveredAt" TIMESTAMP(3);
ALTER TABLE "Notification" ADD COLUMN "pushSentAt" TIMESTAMP(3);
ALTER TABLE "Notification" ADD COLUMN "dedupeKey" TEXT;
UPDATE "Notification" n SET "organizationId" = (SELECT m."organizationId" FROM "OrganizationMember" m WHERE m."userId" = n."userId" ORDER BY m."createdAt" ASC LIMIT 1), "type" = 'WEEKLY_DIGEST';
ALTER TABLE "Notification" ALTER COLUMN "organizationId" SET NOT NULL;
ALTER TABLE "Notification" ALTER COLUMN "type" SET NOT NULL;
ALTER TABLE "Notification" ADD CONSTRAINT "Notification_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "Notification" ADD CONSTRAINT "Notification_restaurantLocationId_fkey" FOREIGN KEY ("restaurantLocationId") REFERENCES "RestaurantLocation"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "Notification" ADD CONSTRAINT "Notification_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
CREATE UNIQUE INDEX "Notification_dedupeKey_key" ON "Notification"("dedupeKey");
CREATE INDEX "Notification_userId_readAt_createdAt_idx" ON "Notification"("userId", "readAt", "createdAt");
CREATE INDEX "Notification_organizationId_restaurantLocationId_createdAt_idx" ON "Notification"("organizationId", "restaurantLocationId", "createdAt");

CREATE TABLE "NotificationPreference" (
  "id" TEXT NOT NULL, "userId" TEXT NOT NULL, "organizationId" TEXT NOT NULL, "restaurantLocationId" TEXT,
  "pushEnabled" BOOLEAN NOT NULL DEFAULT true, "weeklyDigestEnabled" BOOLEAN NOT NULL DEFAULT true,
  "priceAlertsEnabled" BOOLEAN NOT NULL DEFAULT true, "savingsAlertsEnabled" BOOLEAN NOT NULL DEFAULT true,
  "costAlertsEnabled" BOOLEAN NOT NULL DEFAULT true, "syncAlertsEnabled" BOOLEAN NOT NULL DEFAULT true,
  "quietHoursStart" TEXT, "quietHoursEnd" TEXT, "timezone" TEXT NOT NULL DEFAULT 'America/Detroit',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "NotificationPreference_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "DevicePushToken" (
  "id" TEXT NOT NULL, "userId" TEXT NOT NULL, "platform" "DevicePushPlatform" NOT NULL, "token" TEXT NOT NULL,
  "active" BOOLEAN NOT NULL DEFAULT true, "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL, "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "DevicePushToken_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "NotificationPreference_userId_organizationId_key" ON "NotificationPreference"("userId", "organizationId");
CREATE INDEX "NotificationPreference_organizationId_restaurantLocationId_idx" ON "NotificationPreference"("organizationId", "restaurantLocationId");
CREATE UNIQUE INDEX "DevicePushToken_token_key" ON "DevicePushToken"("token");
CREATE INDEX "DevicePushToken_userId_active_idx" ON "DevicePushToken"("userId", "active");
ALTER TABLE "NotificationPreference" ADD CONSTRAINT "NotificationPreference_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "NotificationPreference" ADD CONSTRAINT "NotificationPreference_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "NotificationPreference" ADD CONSTRAINT "NotificationPreference_restaurantLocationId_fkey" FOREIGN KEY ("restaurantLocationId") REFERENCES "RestaurantLocation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "DevicePushToken" ADD CONSTRAINT "DevicePushToken_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
