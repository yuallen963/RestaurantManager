import { Injectable } from '@nestjs/common';
import { ExtractionStatus, Prisma, ReviewStatus } from '@prisma/client';
import { AuditService } from '../audit.service';
import { PrismaService } from '../prisma.service';
import { ExtractedInvoice, InvoiceExtractionProvider } from './extraction.provider';
import { InvoiceStorageService } from './storage.service';

const clamp = (value: number) => Math.max(0, Math.min(1, value));
export function extractionConfidence(data: ExtractedInvoice) {
  let invoice = 1;
  if (!data.vendorName) invoice -= .25;
  if (!data.invoiceDate) invoice -= .25;
  if (data.total === null) invoice -= .25;
  invoice -= Math.min(data.uncertainFields.length * .08, .24);
  const lines = data.lineItems.map((line) => clamp(1 - (!line.rawDescription ? .4 : 0) - (line.quantity === null ? .18 : 0) - (line.unitPrice === null && line.extendedPrice === null ? .2 : 0) - Math.min(line.uncertainFields.length * .08, .24)));
  const overall = clamp(lines.length ? (invoice * .65) + (lines.reduce((a, b) => a + b, 0) / lines.length * .35) : invoice - .15);
  const needsReview = !data.vendorName || !data.invoiceDate || data.total === null || data.uncertainFields.length > 0 || data.lineItems.some((line) => line.quantity === null || (line.unitPrice === null && line.extendedPrice === null) || line.uncertainFields.length > 0);
  return { overall, lines, needsReview };
}

@Injectable()
export class InvoiceExtractionProcessor {
  constructor(private readonly prisma: PrismaService, private readonly storage: InvoiceStorageService, private readonly provider: InvoiceExtractionProvider, private readonly audit: AuditService) {}
  isConfigured() { return this.provider.isConfigured(); }
  async process(invoiceId: string, userId: string) {
    const invoice = await this.prisma.invoice.findUnique({ where: { id: invoiceId } });
    if (!invoice) return;
    try {
      const file = await this.storage.get(invoice.storageKey);
      const result = await this.provider.extract(file, invoice.fileType, invoice.originalFileName);
      const confidence = extractionConfidence(result.data);
      const vendor = result.data.vendorName ? await this.prisma.vendor.findFirst({ where: { organizationId: invoice.organizationId, normalizedName: result.data.vendorName.trim().toLowerCase().replace(/\s+/g, ' ') } }) : null;
      await this.prisma.$transaction(async (tx) => {
        await tx.invoiceLineItem.deleteMany({ where: { invoiceId } });
        if (result.data.lineItems.length) await tx.invoiceLineItem.createMany({ data: result.data.lineItems.map((line, index) => ({ invoiceId, organizationId: invoice.organizationId, restaurantLocationId: invoice.restaurantLocationId, lineNumber: line.lineNumber || index + 1, rawDescription: line.rawDescription, sku: line.sku, quantity: line.quantity === null ? null : new Prisma.Decimal(line.quantity), unit: line.unit, packSize: line.packSize, unitPrice: line.unitPrice === null ? null : new Prisma.Decimal(line.unitPrice), extendedPrice: line.extendedPrice === null ? null : new Prisma.Decimal(line.extendedPrice), category: line.category, confidence: new Prisma.Decimal(confidence.lines[index].toFixed(4)) })) });
        await tx.invoice.update({ where: { id: invoiceId }, data: { vendorId: vendor?.id, extractedVendorName: result.data.vendorName, invoiceNumber: result.data.invoiceNumber, invoiceDate: result.data.invoiceDate ? new Date(`${result.data.invoiceDate}T00:00:00.000Z`) : null, subtotal: result.data.subtotal === null ? null : new Prisma.Decimal(result.data.subtotal), tax: result.data.tax === null ? null : new Prisma.Decimal(result.data.tax), total: result.data.total === null ? null : new Prisma.Decimal(result.data.total), extractionStatus: ExtractionStatus.COMPLETED, extractionProvider: result.provider, extractionModel: result.model, extractionConfidence: new Prisma.Decimal(confidence.overall.toFixed(4)), extractionCompletedAt: new Date(), extractionError: null, rawExtractionJson: result.data as Prisma.InputJsonValue, extractionUsage: result.usage as Prisma.InputJsonValue, reviewStatus: confidence.needsReview ? ReviewStatus.NEEDS_REVIEW : ReviewStatus.NOT_REVIEWED } });
      });
      await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.extraction_completed', entityType: 'Invoice', entityId: invoiceId, metadata: { provider: result.provider, model: result.model, lineItemCount: result.data.lineItems.length } });
    } catch (error) {
      const message = error instanceof Error ? error.message.slice(0, 500) : 'Unknown extraction error';
      await this.prisma.invoice.update({ where: { id: invoiceId }, data: { extractionStatus: ExtractionStatus.FAILED, extractionCompletedAt: new Date(), extractionError: message } });
      await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.extraction_failed', entityType: 'Invoice', entityId: invoiceId, metadata: { errorType: error instanceof Error ? error.name : 'UnknownError' } });
    }
  }
}
