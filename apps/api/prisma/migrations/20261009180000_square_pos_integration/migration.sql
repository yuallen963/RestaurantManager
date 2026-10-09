CREATE TYPE "PosProvider" AS ENUM ('SQUARE');
CREATE TYPE "PosConnectionStatus" AS ENUM ('CONNECTED', 'SYNCING', 'REAUTH_REQUIRED', 'ERROR', 'DISCONNECTED');
CREATE TYPE "PosRevenueConflictStatus" AS ENUM ('NONE', 'PENDING', 'USE_MANUAL', 'USE_POS');

CREATE TABLE "PosOAuthState" (
  "id" TEXT NOT NULL,
  "organizationId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "provider" "PosProvider" NOT NULL DEFAULT 'SQUARE',
  "stateHash" TEXT NOT NULL,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "usedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PosOAuthState_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "PosConnection" (
  "id" TEXT NOT NULL,
  "organizationId" TEXT NOT NULL,
  "provider" "PosProvider" NOT NULL DEFAULT 'SQUARE',
  "encryptedAccessToken" TEXT NOT NULL,
  "encryptedRefreshToken" TEXT,
  "providerMerchantId" TEXT NOT NULL,
  "merchantName" TEXT,
  "status" "PosConnectionStatus" NOT NULL DEFAULT 'CONNECTED',
  "tokenExpiresAt" TIMESTAMP(3),
  "lastSyncAt" TIMESTAMP(3),
  "lastError" TEXT,
  "createdByUserId" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PosConnection_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "PosLocationMapping" (
  "id" TEXT NOT NULL,
  "posConnectionId" TEXT NOT NULL,
  "organizationId" TEXT NOT NULL,
  "restaurantLocationId" TEXT NOT NULL,
  "providerLocationId" TEXT NOT NULL,
  "providerLocationName" TEXT NOT NULL,
  "providerTimezone" TEXT NOT NULL,
  "active" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PosLocationMapping_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "PosDailySales" (
  "id" TEXT NOT NULL,
  "organizationId" TEXT NOT NULL,
  "restaurantLocationId" TEXT NOT NULL,
  "posConnectionId" TEXT NOT NULL,
  "posLocationMappingId" TEXT NOT NULL,
  "providerLocationId" TEXT NOT NULL,
  "businessDate" TIMESTAMP(3) NOT NULL,
  "grossSales" DECIMAL(14,2) NOT NULL,
  "discounts" DECIMAL(14,2) NOT NULL,
  "refunds" DECIMAL(14,2) NOT NULL,
  "taxes" DECIMAL(14,2) NOT NULL,
  "tips" DECIMAL(14,2) NOT NULL,
  "netSales" DECIMAL(14,2) NOT NULL,
  "transactionCount" INTEGER NOT NULL,
  "providerUpdatedAt" TIMESTAMP(3),
  "revenueEntryId" TEXT,
  "conflictStatus" "PosRevenueConflictStatus" NOT NULL DEFAULT 'NONE',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "PosDailySales_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "PosWebhookEvent" (
  "id" TEXT NOT NULL,
  "provider" "PosProvider" NOT NULL DEFAULT 'SQUARE',
  "providerEventId" TEXT NOT NULL,
  "eventType" TEXT NOT NULL,
  "merchantId" TEXT,
  "receivedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "processedAt" TIMESTAMP(3),
  CONSTRAINT "PosWebhookEvent_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "PosOAuthState_stateHash_key" ON "PosOAuthState"("stateHash");
CREATE INDEX "PosOAuthState_organizationId_expiresAt_idx" ON "PosOAuthState"("organizationId", "expiresAt");
CREATE UNIQUE INDEX "PosConnection_provider_providerMerchantId_key" ON "PosConnection"("provider", "providerMerchantId");
CREATE INDEX "PosConnection_organizationId_provider_status_idx" ON "PosConnection"("organizationId", "provider", "status");
CREATE UNIQUE INDEX "PosLocationMapping_posConnectionId_providerLocationId_key" ON "PosLocationMapping"("posConnectionId", "providerLocationId");
CREATE UNIQUE INDEX "PosLocationMapping_posConnectionId_restaurantLocationId_key" ON "PosLocationMapping"("posConnectionId", "restaurantLocationId");
CREATE INDEX "PosLocationMapping_organizationId_restaurantLocationId_active_idx" ON "PosLocationMapping"("organizationId", "restaurantLocationId", "active");
CREATE UNIQUE INDEX "PosDailySales_revenueEntryId_key" ON "PosDailySales"("revenueEntryId");
CREATE UNIQUE INDEX "PosDailySales_posConnectionId_providerLocationId_businessDate_key" ON "PosDailySales"("posConnectionId", "providerLocationId", "businessDate");
CREATE INDEX "PosDailySales_organizationId_restaurantLocationId_businessDate_idx" ON "PosDailySales"("organizationId", "restaurantLocationId", "businessDate");
CREATE INDEX "PosDailySales_conflictStatus_idx" ON "PosDailySales"("conflictStatus");
CREATE UNIQUE INDEX "PosWebhookEvent_provider_providerEventId_key" ON "PosWebhookEvent"("provider", "providerEventId");
CREATE INDEX "PosWebhookEvent_merchantId_receivedAt_idx" ON "PosWebhookEvent"("merchantId", "receivedAt");

ALTER TABLE "PosOAuthState" ADD CONSTRAINT "PosOAuthState_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PosOAuthState" ADD CONSTRAINT "PosOAuthState_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PosConnection" ADD CONSTRAINT "PosConnection_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PosConnection" ADD CONSTRAINT "PosConnection_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "PosLocationMapping" ADD CONSTRAINT "PosLocationMapping_posConnectionId_fkey" FOREIGN KEY ("posConnectionId") REFERENCES "PosConnection"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PosLocationMapping" ADD CONSTRAINT "PosLocationMapping_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PosLocationMapping" ADD CONSTRAINT "PosLocationMapping_restaurantLocationId_fkey" FOREIGN KEY ("restaurantLocationId") REFERENCES "RestaurantLocation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PosDailySales" ADD CONSTRAINT "PosDailySales_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PosDailySales" ADD CONSTRAINT "PosDailySales_restaurantLocationId_fkey" FOREIGN KEY ("restaurantLocationId") REFERENCES "RestaurantLocation"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PosDailySales" ADD CONSTRAINT "PosDailySales_posConnectionId_fkey" FOREIGN KEY ("posConnectionId") REFERENCES "PosConnection"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PosDailySales" ADD CONSTRAINT "PosDailySales_posLocationMappingId_fkey" FOREIGN KEY ("posLocationMappingId") REFERENCES "PosLocationMapping"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PosDailySales" ADD CONSTRAINT "PosDailySales_revenueEntryId_fkey" FOREIGN KEY ("revenueEntryId") REFERENCES "RevenueEntry"("id") ON DELETE SET NULL ON UPDATE CASCADE;
