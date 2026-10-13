CREATE TYPE "AuthChallengeType" AS ENUM ('EMAIL_LOGIN', 'TOTP_LOGIN');
CREATE TYPE "SecurityEmailType" AS ENUM ('WELCOME', 'PASSWORD_CHANGED', 'NEW_DEVICE_LOGIN', 'SUSPICIOUS_LOGIN', 'SECURITY_SETTINGS_CHANGED', 'MFA_ENABLED', 'MFA_DISABLED', 'RECOVERY_CODES_REGENERATED', 'RECOVERY_CODE_USED', 'ACCOUNT_RECOVERED');

ALTER TABLE "User"
  ADD COLUMN "emailLoginVerificationEnabled" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "mfaEnabled" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "totpSecretEncrypted" TEXT,
  ADD COLUMN "totpPendingSecretEncrypted" TEXT,
  ADD COLUMN "totpPendingExpiresAt" TIMESTAMP(3),
  ADD COLUMN "totpLastUsedStep" BIGINT;

ALTER TABLE "RefreshToken"
  ADD COLUMN "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN "deviceHash" TEXT,
  ADD COLUMN "deviceLabel" TEXT;

CREATE TABLE "AuthChallenge" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "type" "AuthChallengeType" NOT NULL,
  "codeHash" TEXT,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "usedAt" TIMESTAMP(3),
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "maxAttempts" INTEGER NOT NULL DEFAULT 5,
  "lastSentAt" TIMESTAMP(3),
  "deviceHash" TEXT,
  "deviceLabel" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AuthChallenge_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "MfaRecoveryCode" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "codeHash" TEXT NOT NULL,
  "usedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "MfaRecoveryCode_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "RecognizedDevice" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "deviceHash" TEXT NOT NULL,
  "label" TEXT,
  "firstSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "revokedAt" TIMESTAMP(3),
  CONSTRAINT "RecognizedDevice_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "SecurityEmailEvent" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "type" "SecurityEmailType" NOT NULL,
  "dedupeKey" TEXT NOT NULL,
  "sentAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SecurityEmailEvent_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "AuthChallenge_userId_type_expiresAt_idx" ON "AuthChallenge"("userId", "type", "expiresAt");
CREATE INDEX "MfaRecoveryCode_userId_usedAt_idx" ON "MfaRecoveryCode"("userId", "usedAt");
CREATE UNIQUE INDEX "RecognizedDevice_userId_deviceHash_key" ON "RecognizedDevice"("userId", "deviceHash");
CREATE INDEX "RecognizedDevice_userId_revokedAt_lastSeenAt_idx" ON "RecognizedDevice"("userId", "revokedAt", "lastSeenAt");
CREATE UNIQUE INDEX "SecurityEmailEvent_dedupeKey_key" ON "SecurityEmailEvent"("dedupeKey");
CREATE INDEX "SecurityEmailEvent_userId_type_createdAt_idx" ON "SecurityEmailEvent"("userId", "type", "createdAt");

ALTER TABLE "AuthChallenge" ADD CONSTRAINT "AuthChallenge_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "MfaRecoveryCode" ADD CONSTRAINT "MfaRecoveryCode_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "RecognizedDevice" ADD CONSTRAINT "RecognizedDevice_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SecurityEmailEvent" ADD CONSTRAINT "SecurityEmailEvent_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
