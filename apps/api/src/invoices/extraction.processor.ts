import { Injectable } from '@nestjs/common';
import { ExtractionStatus, Prisma, ReviewStatus } from '@prisma/client';
import { AuditService } from '../audit.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma.service';
import { ExtractedInvoice, InvoiceExtractionProvider } from './extraction.provider';
import { InvoiceStorageService } from './storage.service';

const clamp = (value: number) => Math.max(0, Math.min(1, value));
export type ParsedPackageSize = { packCount: number | null; packUnitQuantity: number | null; measurementUnit: string; totalPackageQuantity: number };

export function parsePackageSize(raw: string | null): ParsedPackageSize | null {
  if (!raw) return null;
  const normalized = raw.trim().toUpperCase().replace(/\s+/g, ' ');
  const packed = normalized.match(/^(\d+(?:\.\d+)?)\s*(?:\/|X)\s*(\d+(?:\.\d+)?)\s*(LB|LBS|OZ|KG|G|CT|EA)$/);
  if (packed) {
    const packCount = Number(packed[1]);
    const packUnitQuantity = Number(packed[2]);
    return { packCount, packUnitQuantity, measurementUnit: packed[3] === 'LBS' ? 'LB' : packed[3], totalPackageQuantity: packCount * packUnitQuantity };
  }
  const single = normalized.match(/^(\d+(?:\.\d+)?)\s*(LB|LBS|OZ|KG|G|CT|EA)$/);
  if (!single) return null;
  return { packCount: null, packUnitQuantity: null, measurementUnit: single[2] === 'LBS' ? 'LB' : single[2], totalPackageQuantity: Number(single[1]) };
}

export function normalizeExtractedDate(value: string | null, now = new Date(), allowFuture = false): Date | null {
  if (!value) return null;
  const match = value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return null;
  const year = Number(match[1]), month = Number(match[2]), day = Number(match[3]);
  const result = new Date(Date.UTC(year, month - 1, day));
  if (result.getUTCFullYear() !== year || result.getUTCMonth() !== month - 1 || result.getUTCDate() !== day) return null;
  if (!allowFuture && result.getTime() > now.getTime() + 86_400_000) return null;
  return result;
}

export function extractionConfidence(data: ExtractedInvoice) {
  let invoice = 1;
  if (!data.vendorName) invoice -= .25;
  if (!data.invoiceNumber) invoice -= .1;
  if (!data.invoiceDate) invoice -= .25;
  if (data.total === null) invoice -= .25;
  invoice -= Math.min(data.uncertainFields.length * .08, .24);
  const lines = data.lineItems.map((line) => clamp(1 - (!line.rawDescription ? .4 : 0) - (line.quantity === null ? .18 : 0) - (line.unitPrice === null && line.extendedPrice === null ? .2 : 0) - Math.min(line.uncertainFields.length * .08, .24)));
  const overall = clamp(lines.length ? (invoice * .65) + (lines.reduce((a, b) => a + b, 0) / lines.length * .35) : invoice - .15);
  const needsReview = !data.vendorName || !data.invoiceNumber || !data.invoiceDate || data.total === null || data.uncertainFields.length > 0 || data.lineItems.some((line) => line.quantity === null || (line.unitPrice === null && line.extendedPrice === null) || line.uncertainFields.length > 0);
  return { overall, lines, needsReview };
}

function safeExtractionError(error: unknown) {
  const name = error instanceof Error ? error.name.toLowerCase() : '';
  const message = error instanceof Error ? error.message.toLowerCase() : '';
  if (name.includes('timeout') || message.includes('timeout')) return 'Invoice extraction timed out. Please try again.';
  if (message.includes('structured') || message.includes('parse') || message.includes('schema')) return 'The invoice could not be read reliably. Please retry or enter it manually.';
  if (message.includes('unsupported') || message.includes('invalid file')) return 'This invoice file could not be processed. Upload a PDF, JPG, or PNG.';
  return 'Invoice extraction is temporarily unavailable. Your uploaded invoice is safe.';
}

@Injectable()
export class InvoiceExtractionProcessor {
  constructor(private readonly prisma: PrismaService, private readonly storage: InvoiceStorageService, private readonly provider: InvoiceExtractionProvider, private readonly audit: AuditService, private readonly notifications?: NotificationsService) {}
  isConfigured() { return this.provider.isConfigured(); }
  async process(invoiceId: string, userId: string) {
    const startedAt = Date.now();
    const invoice = await this.prisma.invoice.findUnique({ where: { id: invoiceId } });
    if (!invoice) return;
    if (invoice.reviewStatus === ReviewStatus.REVIEWED) {
      await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.extraction_skipped_reviewed', entityType: 'Invoice', entityId: invoiceId });
      return;
    }
    try {
      const file = await this.storage.get(invoice.storageKey);
      const result = await this.provider.extract(file, invoice.fileType, invoice.originalFileName);
      const invoiceDate = normalizeExtractedDate(result.data.invoiceDate);
      const dueDate = normalizeExtractedDate(result.data.dueDate, new Date(), true);
      const uncertainFields = new Set(result.data.uncertainFields);
      if (result.data.invoiceDate && !invoiceDate) uncertainFields.add('invoiceDate');
      if (result.data.dueDate && !dueDate) uncertainFields.add('dueDate');
      const confidence = extractionConfidence({ ...result.data, invoiceDate: invoiceDate ? result.data.invoiceDate : null, uncertainFields: [...uncertainFields] });
      const vendor = result.data.vendorName ? await this.prisma.vendor.findFirst({ where: { organizationId: invoice.organizationId, normalizedName: result.data.vendorName.trim().toLowerCase().replace(/\s+/g, ' ') } }) : null;
      let applied = false;
      await this.prisma.$transaction(async (tx) => {
        const current = await tx.invoice.findUnique({ where: { id: invoiceId }, select: { reviewStatus: true } });
        if (!current || current.reviewStatus === ReviewStatus.REVIEWED) return;
        applied = true;
        await tx.invoiceLineItem.deleteMany({ where: { invoiceId } });
        if (result.data.lineItems.length) await tx.invoiceLineItem.createMany({ data: result.data.lineItems.map((line, index) => {
          const parsedPackage = parsePackageSize(line.packSize);
          return { invoiceId, organizationId: invoice.organizationId, restaurantLocationId: invoice.restaurantLocationId, lineNumber: line.lineNumber || index + 1, sourcePage: line.sourcePage, rawDescription: line.rawDescription, normalizedName: line.normalizedName, sku: line.sku, quantity: line.quantity === null ? null : new Prisma.Decimal(line.quantity), unit: line.unit, packSize: line.packSize, packCount: parsedPackage?.packCount == null ? null : new Prisma.Decimal(parsedPackage.packCount), packUnitQuantity: parsedPackage?.packUnitQuantity == null ? null : new Prisma.Decimal(parsedPackage.packUnitQuantity), measurementUnit: parsedPackage?.measurementUnit ?? null, totalPackageQuantity: parsedPackage ? new Prisma.Decimal(parsedPackage.totalPackageQuantity) : null, unitPrice: line.unitPrice === null ? null : new Prisma.Decimal(line.unitPrice), extendedPrice: line.extendedPrice === null ? null : new Prisma.Decimal(line.extendedPrice), category: line.category, productAttributes: line.productAttributes ? line.productAttributes as Prisma.InputJsonValue : Prisma.DbNull, uncertainFields: line.uncertainFields, confidence: new Prisma.Decimal(confidence.lines[index].toFixed(4)) };
        }) });
        await tx.invoice.update({ where: { id: invoiceId }, data: { vendorId: vendor?.id, extractedVendorName: result.data.vendorName, extractedVendorAddress: result.data.vendorAddress, invoiceNumber: result.data.invoiceNumber, invoiceDate, dueDate, subtotal: result.data.subtotal === null ? null : new Prisma.Decimal(result.data.subtotal), tax: result.data.tax === null ? null : new Prisma.Decimal(result.data.tax), otherFees: result.data.otherFees === null ? null : new Prisma.Decimal(result.data.otherFees), total: result.data.total === null ? null : new Prisma.Decimal(result.data.total), currency: result.data.currency, extractionStatus: ExtractionStatus.COMPLETED, extractionProvider: result.provider, extractionModel: result.model, extractionConfidence: new Prisma.Decimal(confidence.overall.toFixed(4)), extractionCompletedAt: new Date(), extractionDurationMs: Date.now() - startedAt, extractionError: null, uncertainFields: [...uncertainFields], rawExtractionJson: result.data as Prisma.InputJsonValue, extractionUsage: result.usage ? result.usage as Prisma.InputJsonValue : Prisma.DbNull, reviewStatus: confidence.needsReview ? ReviewStatus.NEEDS_REVIEW : ReviewStatus.NOT_REVIEWED } });
      });
      if (!applied) {
        await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.extraction_discarded_reviewed', entityType: 'Invoice', entityId: invoiceId, metadata: { model: result.model, durationMs: Date.now() - startedAt } });
        return;
      }
      const usage = result.usage as { input_tokens?: number; output_tokens?: number; total_tokens?: number } | null;
      await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.extraction_completed', entityType: 'Invoice', entityId: invoiceId, metadata: { provider: result.provider, model: result.model, lineItemCount: result.data.lineItems.length, durationMs: Date.now() - startedAt, inputTokens: usage?.input_tokens, outputTokens: usage?.output_tokens, totalTokens: usage?.total_tokens } });
    } catch (error) {
      const safeMessage = safeExtractionError(error);
      await this.prisma.invoice.updateMany({ where: { id: invoiceId, reviewStatus: { not: ReviewStatus.REVIEWED } }, data: { extractionStatus: ExtractionStatus.FAILED, extractionCompletedAt: new Date(), extractionDurationMs: Date.now() - startedAt, extractionError: safeMessage } });
      await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.extraction_failed', entityType: 'Invoice', entityId: invoiceId, metadata: { errorType: error instanceof Error ? error.name : 'UnknownError', durationMs: Date.now() - startedAt } });
      await this.notifications?.notifyOperational({ organizationId: invoice.organizationId, restaurantLocationId: invoice.restaurantLocationId, type: 'INVOICE_EXTRACTION_FAILED' as any, severity: 'HIGH' as any, title: 'Invoice extraction failed', body: 'Invoice extraction failed for a recent upload.', deepLinkType: 'OPEN_INVOICE', deepLinkId: invoiceId, dedupeKey: `invoice-extraction-failed:${invoiceId}:${error instanceof Error ? error.name : 'unknown'}` });
    }
  }
}
