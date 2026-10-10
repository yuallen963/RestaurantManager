CREATE TABLE "InboundEmailWebhookReceipt" (
    "id" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "receivedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "processedAt" TIMESTAMP(3),

    CONSTRAINT "InboundEmailWebhookReceipt_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "InboundEmailWebhookReceipt_tokenHash_key" ON "InboundEmailWebhookReceipt"("tokenHash");
CREATE INDEX "InboundEmailWebhookReceipt_receivedAt_idx" ON "InboundEmailWebhookReceipt"("receivedAt");
