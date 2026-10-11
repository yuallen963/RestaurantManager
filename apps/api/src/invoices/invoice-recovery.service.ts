import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ExtractionStatus, InvoiceStatus, ReviewStatus } from '@prisma/client';
import { AuditService } from '../audit.service';
import { PrismaService } from '../prisma.service';
import { InvoiceExtractionProcessor } from './extraction.processor';
import { MAX_EXTRACTION_ATTEMPTS, STALE_EXTRACTION_MS } from './invoices.service';

const ABANDONED_UPLOAD_MS = 20 * 60 * 1000;
const RECOVERY_INTERVAL_MS = 60 * 1000;

@Injectable()
export class InvoiceRecoveryService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(InvoiceRecoveryService.name);
  private timer?: NodeJS.Timeout;

  constructor(private readonly prisma: PrismaService, private readonly extraction: InvoiceExtractionProcessor, private readonly audit: AuditService) {}

  onModuleInit() {
    setImmediate(() => void this.recover().catch((error) => this.logFailure(error)));
    this.timer = setInterval(() => void this.recover().catch((error) => this.logFailure(error)), RECOVERY_INTERVAL_MS);
    this.timer.unref();
  }

  onModuleDestroy() { if (this.timer) clearInterval(this.timer); }

  async recover(now = new Date()) {
    const staleUploadBefore = new Date(now.getTime() - ABANDONED_UPLOAD_MS);
    const abandoned = await this.prisma.invoice.findMany({ where: { status: InvoiceStatus.PROCESSING, attachmentHash: null, reviewStatus: { not: ReviewStatus.REVIEWED }, updatedAt: { lt: staleUploadBefore } }, select: { id: true, organizationId: true, createdByUserId: true }, take: 50 });
    for (const invoice of abandoned) {
      const result = await this.prisma.invoice.updateMany({ where: { id: invoice.id, status: InvoiceStatus.PROCESSING, attachmentHash: null, reviewStatus: { not: ReviewStatus.REVIEWED }, updatedAt: { lt: staleUploadBefore } }, data: { status: InvoiceStatus.FAILED, extractionStatus: ExtractionStatus.FAILED, extractionCompletedAt: now, extractionError: 'Upload did not finish. Choose the file and upload it again.' } });
      if (result.count) await this.audit.log({ userId: invoice.createdByUserId, organizationId: invoice.organizationId, action: 'invoice.upload_abandoned', entityType: 'Invoice', entityId: invoice.id, metadata: { failureStage: 'UPLOAD', errorCode: 'UPLOAD_EXPIRED', recoveryOutcome: 'MARKED_FAILED' } });
    }

    if (!this.extraction.isConfigured()) return;
    const staleExtractionBefore = new Date(now.getTime() - STALE_EXTRACTION_MS);
    const stale = await this.prisma.invoice.findMany({ where: { attachmentHash: { not: null }, extractionStatus: ExtractionStatus.PROCESSING, extractionStartedAt: { lt: staleExtractionBefore }, extractionAttemptCount: { lt: MAX_EXTRACTION_ATTEMPTS }, reviewStatus: { not: ReviewStatus.REVIEWED } }, select: { id: true, organizationId: true, createdByUserId: true, extractionAttemptCount: true }, take: 20 });
    for (const invoice of stale) {
      const claim = await this.prisma.invoice.updateMany({ where: { id: invoice.id, extractionStatus: ExtractionStatus.PROCESSING, extractionStartedAt: { lt: staleExtractionBefore }, extractionAttemptCount: { lt: MAX_EXTRACTION_ATTEMPTS }, reviewStatus: { not: ReviewStatus.REVIEWED } }, data: { status: InvoiceStatus.UPLOADED, extractionStartedAt: new Date(), extractionCompletedAt: null, extractionDurationMs: null, extractionError: null, extractionAttemptCount: { increment: 1 } } });
      if (!claim.count) continue;
      await this.audit.log({ userId: invoice.createdByUserId, organizationId: invoice.organizationId, action: 'invoice.extraction_recovered', entityType: 'Invoice', entityId: invoice.id, metadata: { attempt: invoice.extractionAttemptCount + 1, recoveryOutcome: 'RESTARTED' } });
      setImmediate(() => void this.extraction.process(invoice.id, invoice.createdByUserId));
    }

    await this.prisma.invoice.updateMany({ where: { extractionStatus: ExtractionStatus.PROCESSING, extractionStartedAt: { lt: staleExtractionBefore }, extractionAttemptCount: { gte: MAX_EXTRACTION_ATTEMPTS }, reviewStatus: { not: ReviewStatus.REVIEWED } }, data: { status: InvoiceStatus.FAILED, extractionStatus: ExtractionStatus.FAILED, extractionCompletedAt: now, extractionError: 'Invoice extraction retry limit reached. Enter the invoice manually or contact support.' } });
  }

  private logFailure(error: unknown) { this.logger.error(JSON.stringify({ event: 'invoice_recovery_failed', errorType: error instanceof Error ? error.name : 'UnknownError' })); }
}
