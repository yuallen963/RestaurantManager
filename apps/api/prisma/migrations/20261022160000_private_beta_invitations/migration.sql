CREATE TYPE "BetaInvitationType" AS ENUM ('NEW_ORGANIZATION', 'JOIN_ORGANIZATION');

CREATE TABLE "BetaInvitation" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "type" "BetaInvitationType" NOT NULL,
    "organizationId" TEXT,
    "organizationName" TEXT,
    "role" "OrganizationRole",
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "redeemedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdByUserId" TEXT NOT NULL,
    "redeemedByUserId" TEXT,

    CONSTRAINT "BetaInvitation_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "BetaInvitation_tokenHash_key" ON "BetaInvitation"("tokenHash");
CREATE INDEX "BetaInvitation_email_expiresAt_idx" ON "BetaInvitation"("email", "expiresAt");
CREATE INDEX "BetaInvitation_organizationId_createdAt_idx" ON "BetaInvitation"("organizationId", "createdAt");
CREATE INDEX "BetaInvitation_createdByUserId_idx" ON "BetaInvitation"("createdByUserId");

ALTER TABLE "BetaInvitation" ADD CONSTRAINT "BetaInvitation_organizationId_fkey"
  FOREIGN KEY ("organizationId") REFERENCES "Organization"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "BetaInvitation" ADD CONSTRAINT "BetaInvitation_createdByUserId_fkey"
  FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "BetaInvitation" ADD CONSTRAINT "BetaInvitation_redeemedByUserId_fkey"
  FOREIGN KEY ("redeemedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
