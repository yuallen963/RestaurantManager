ALTER TABLE "RestaurantLocation" ADD COLUMN "timezone" TEXT NOT NULL DEFAULT 'America/Detroit';

CREATE TABLE "OnboardingState" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "organizationId" TEXT,
  "restaurantLocationId" TEXT,
  "onboardingStartedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "onboardingCompletedAt" TIMESTAMP(3),
  "currentStep" INTEGER NOT NULL DEFAULT 1,
  "selectedDataSources" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "OnboardingState_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "OnboardingState_userId_key" ON "OnboardingState"("userId");
CREATE INDEX "OnboardingState_organizationId_idx" ON "OnboardingState"("organizationId");
CREATE INDEX "OnboardingState_restaurantLocationId_idx" ON "OnboardingState"("restaurantLocationId");

ALTER TABLE "OnboardingState" ADD CONSTRAINT "OnboardingState_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "OnboardingState" ADD CONSTRAINT "OnboardingState_organizationId_fkey" FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "OnboardingState" ADD CONSTRAINT "OnboardingState_restaurantLocationId_fkey" FOREIGN KEY ("restaurantLocationId") REFERENCES "RestaurantLocation"("id") ON DELETE SET NULL ON UPDATE CASCADE;

INSERT INTO "OnboardingState" (
  "id", "userId", "organizationId", "restaurantLocationId",
  "onboardingStartedAt", "onboardingCompletedAt", "currentStep",
  "selectedDataSources", "createdAt", "updatedAt"
)
SELECT
  gen_random_uuid()::TEXT,
  u."id",
  membership."organizationId",
  location."id",
  u."createdAt",
  CURRENT_TIMESTAMP,
  6,
  ARRAY[]::TEXT[],
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
FROM "User" u
LEFT JOIN LATERAL (
  SELECT m."organizationId"
  FROM "OrganizationMember" m
  WHERE m."userId" = u."id"
  ORDER BY m."createdAt" ASC
  LIMIT 1
) membership ON TRUE
LEFT JOIN LATERAL (
  SELECT l."id"
  FROM "RestaurantLocation" l
  WHERE l."organizationId" = membership."organizationId"
  ORDER BY l."createdAt" ASC
  LIMIT 1
) location ON TRUE;
