ALTER TYPE "InsightStatus" ADD VALUE IF NOT EXISTS 'REVIEWED';

ALTER TABLE "Insight"
ADD COLUMN "fingerprint" TEXT,
ADD COLUMN "reviewedAt" TIMESTAMP(3),
ADD COLUMN "resolvedAt" TIMESTAMP(3),
ADD COLUMN "dismissedAt" TIMESTAMP(3);

UPDATE "Insight"
SET "fingerprint" = 'legacy:' || "id"
WHERE "fingerprint" IS NULL;

ALTER TABLE "Insight" ALTER COLUMN "fingerprint" SET NOT NULL;
CREATE UNIQUE INDEX "Insight_fingerprint_key" ON "Insight"("fingerprint");
