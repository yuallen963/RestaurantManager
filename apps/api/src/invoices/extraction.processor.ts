import { Injectable } from '@nestjs/common';
import { ExtractionStatus, InvoiceStatus, Prisma, ReviewStatus } from '@prisma/client';
import { AuditService } from '../audit.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma.service';
import { ExtractedInvoice, InvoiceExtractionProvider } from './extraction.provider';
import { InvoiceStorageService } from './storage.service';

const clamp = (value: number) => Math.max(0, Math.min(1, value));
export type ParsedPackageSize = { packCount: number | null; packUnitQuantity: number | null; measurementUnit: string; totalPackageQuantity: number };
export const MONEY_TOLERANCE = new Prisma.Decimal('0.01');

export type ReconciliationResult = { reasons: string[]; details: Array<{ code: string; expected: string; actual: string }> };
export type FieldProvenanceKind = 'OBSERVED' | 'CALCULATED' | 'MISSING';
export type FieldProvenance = Record<string, { kind: FieldProvenanceKind; sourceText?: string; sourcePage?: number; calculatedValue?: string; verified: boolean }>;
const money = (value: number) => new Prisma.Decimal(value);
const matches = (a: Prisma.Decimal, b: Prisma.Decimal) => a.sub(b).abs().lte(MONEY_TOLERANCE);

export function reconcileInvoice(data: ExtractedInvoice): ReconciliationResult {
  const reasons: string[] = [];
  const details: ReconciliationResult['details'] = [];
  const extended = data.lineItems.map((line) => line.extendedPrice).filter((value): value is number => value !== null);
  if (data.subtotal !== null && extended.length > 0 && extended.length === data.lineItems.length) {
    const sum = extended.reduce((total, value) => total.add(money(value)), new Prisma.Decimal(0));
    const subtotal = money(data.subtotal);
    if (!matches(sum, subtotal)) { reasons.push('SUBTOTAL_MISMATCH', 'LINE_EXTENSION_MISMATCH'); details.push({ code: 'SUBTOTAL_MISMATCH', expected: subtotal.toFixed(2), actual: sum.toFixed(2) }); }
  }
  if (data.subtotal !== null && data.tax !== null && data.otherFees !== null && data.discount !== null && data.total !== null) {
    const calculated = money(data.subtotal).add(money(data.tax)).add(money(data.otherFees)).sub(money(data.discount));
    const total = money(data.total);
    if (!matches(calculated, total)) { reasons.push('TOTAL_MISMATCH'); details.push({ code: 'TOTAL_MISMATCH', expected: total.toFixed(2), actual: calculated.toFixed(2) }); }
  }
  for (const line of data.lineItems) {
    // Case/package prices are commonly extended at the case level; only check
    // intrinsically countable units where quantity × unit price is unambiguous.
    const unit = line.unit?.trim().toUpperCase();
    if (line.quantity !== null && line.unitPrice !== null && line.extendedPrice !== null && unit && ['EA', 'EACH', 'UNIT', 'CT', 'COUNT'].includes(unit)) {
      const calculated = money(line.quantity).mul(money(line.unitPrice));
      if (!matches(calculated, money(line.extendedPrice))) reasons.push('LINE_MATH_MISMATCH');
    }
  }
  return { reasons: [...new Set(reasons)], details };
}

const evidenceKey = (value: string) => value.toLowerCase().replace(/[^a-z0-9]/g, '');
const evidenceSupportsMoney = (source: string, value: number) => {
  const expected = money(value);
  const candidates = source.match(/(?:\(|-)?\d[\d,]*(?:\.\d{1,4})?\)?/g) ?? [];
  return candidates.some((candidate) => {
    const negative = candidate.startsWith('-') || (candidate.startsWith('(') && candidate.endsWith(')'));
    const raw = candidate.replace(/[(),]/g, '').replace(/^-/, '');
    try { return new Prisma.Decimal(raw).mul(negative ? -1 : 1).eq(expected); } catch { return false; }
  });
};
const evidenceSupportsDate = (source: string, value: string) => {
  const [year, month, day] = value.split('-');
  const rawDigits: string[] = source.match(/\d+/g) ?? [];
  const digits = new Set(rawDigits.map((part) => String(Number(part))));
  const monthNames = [
    ['january', 'jan'], ['february', 'feb'], ['march', 'mar'], ['april', 'apr'],
    ['may'], ['june', 'jun'], ['july', 'jul'], ['august', 'aug'],
    ['september', 'sep', 'sept'], ['october', 'oct'], ['november', 'nov'], ['december', 'dec'],
  ];
  const normalizedSource = source.toLowerCase();
  const numericMonth = digits.has(String(Number(month)));
  const namedMonth = monthNames[Number(month) - 1]?.some((name) => new RegExp(`\\b${name}\\b`, 'i').test(normalizedSource)) ?? false;
  return (numericMonth || namedMonth) && digits.has(String(Number(day))) && (digits.has(String(Number(year))) || digits.has(String(Number(year.slice(2)))));
};

/**
 * Treat model output as an extraction claim, not proof. A document-level value
 * is retained only when the model also returns a page-scoped exact source quote
 * that deterministically contains the claimed value. Human review remains the
 * authority that verifies the quote against the original document.
 */
export function establishFieldProvenance(input: ExtractedInvoice): { data: ExtractedInvoice; provenance: FieldProvenance; lineProvenance: FieldProvenance[]; unsupportedFields: string[] } {
  const data = structuredClone(input);
  const provenance: FieldProvenance = {};
  const unsupportedFields: string[] = [];
  const moneyFields = new Set(['subtotal', 'tax', 'otherFees', 'discount', 'total']);
  const dateFields = new Set(['invoiceDate', 'dueDate']);
  const fields = ['vendorName', 'invoiceNumber', 'invoiceDate', 'dueDate', 'subtotal', 'tax', 'otherFees', 'discount', 'total', 'currency'] as const;
  for (const field of fields) {
    const value = data[field];
    const evidence = data.fieldEvidence[field];
    if (value === null) {
      provenance[field] = { kind: 'MISSING', verified: false };
      continue;
    }
    const source = evidence.sourceText?.trim();
    let supported = Boolean(source && evidence.sourcePage);
    if (supported && moneyFields.has(field)) supported = evidenceSupportsMoney(source!, value as number);
    else if (supported && dateFields.has(field)) supported = evidenceSupportsDate(source!, value as string);
    else if (supported) supported = evidenceKey(source!).includes(evidenceKey(String(value)));
    if (!supported) {
      (data as unknown as Record<string, unknown>)[field] = null;
      provenance[field] = { kind: 'MISSING', verified: false };
      unsupportedFields.push(field);
      continue;
    }
    provenance[field] = { kind: 'OBSERVED', sourceText: source!, sourcePage: evidence.sourcePage!, verified: false };
  }
  const extended = data.lineItems.map((line) => line.extendedPrice).filter((value): value is number => value !== null);
  if (data.subtotal === null && extended.length > 0 && extended.length === data.lineItems.length) {
    provenance.subtotal = { kind: 'CALCULATED', calculatedValue: extended.reduce((sum, value) => sum.add(money(value)), new Prisma.Decimal(0)).toFixed(2), verified: false };
  }
  if (data.total === null && data.subtotal !== null && data.tax !== null && data.otherFees !== null && data.discount !== null) {
    provenance.total = { kind: 'CALCULATED', calculatedValue: money(data.subtotal).add(money(data.tax)).add(money(data.otherFees)).sub(money(data.discount)).toFixed(2), verified: false };
  }
  const lineProvenance = data.lineItems.map((line, index) => {
    const result: FieldProvenance = {};
    const source = line.sourceText?.trim();
    const pageSupported = Boolean(source && line.sourcePage);
    const fields = ['sku', 'quantity', 'unit', 'packSize', 'unitPrice', 'extendedPrice'] as const;
    for (const field of fields) {
      const value = line[field];
      if (value === null) {
        result[field] = { kind: 'MISSING', verified: false };
        continue;
      }
      const supported = pageSupported && (['quantity', 'unitPrice', 'extendedPrice'].includes(field)
        ? evidenceSupportsMoney(source!, value as number)
        : evidenceKey(source!).includes(evidenceKey(String(value))));
      if (!supported) {
        (line as unknown as Record<string, unknown>)[field] = null;
        line.uncertainFields = [...new Set([...line.uncertainFields, `UNSUPPORTED_${field}`])];
        unsupportedFields.push(`lineItems.${index}.${field}`);
        result[field] = { kind: 'MISSING', verified: false };
      } else {
        result[field] = { kind: 'OBSERVED', sourceText: source!, sourcePage: line.sourcePage!, verified: false };
      }
    }
    const descriptionSupported = pageSupported && evidenceKey(source!).includes(evidenceKey(line.rawDescription));
    result.rawDescription = descriptionSupported
      ? { kind: 'OBSERVED', sourceText: source!, sourcePage: line.sourcePage!, verified: false }
      : { kind: 'MISSING', verified: false };
    if (!descriptionSupported) line.uncertainFields = [...new Set([...line.uncertainFields, 'UNSUPPORTED_rawDescription'])];
    return result;
  });
  return { data, provenance, lineProvenance, unsupportedFields };
}

export function parsePackageSize(raw: string | null): ParsedPackageSize | null {
  if (!raw) return null;
  const normalized = raw.trim().toUpperCase().replace(/×/g, 'X')
    .replace(/\bFLUID\s+OUNCES?\b/g, 'FL OZ')
    .replace(/\bPOUNDS?\b/g, 'LB').replace(/\bOUNCES?\b/g, 'OZ')
    .replace(/\bGALLONS?\b/g, 'GAL').replace(/\bLIT(?:ER|RE)S?\b/g, 'L')
    .replace(/\bMILLILIT(?:ER|RE)S?\b/g, 'ML')
    .replace(/\s+/g, ' ');
  const unitPattern = '(LB|LBS|OZ|KG|G|GAL|GALLON|FL\\s*OZ|FLOZ|L|LTR|ML|CT|EA|EACH)';
  const packed = normalized.match(new RegExp(`^(\\d+(?:\\.\\d+)?)\\s*(?:/|X)\\s*(\\d+(?:\\.\\d+)?)\\s*${unitPattern}$`));
  if (packed) {
    const packCount = Number(packed[1]);
    const packUnitQuantity = Number(packed[2]);
    const measurementUnit = ({ LBS: 'LB', GALLON: 'GAL', FLOZ: 'FL OZ', LTR: 'L', EACH: 'EA' } as Record<string, string>)[packed[3].replace(/\s+/g, '')] ?? packed[3].replace(/\s+/g, ' ');
    return { packCount, packUnitQuantity, measurementUnit, totalPackageQuantity: packCount * packUnitQuantity };
  }
  const single = normalized.match(new RegExp(`^(\\d+(?:\\.\\d+)?)\\s*${unitPattern}$`));
  if (!single) return null;
  const measurementUnit = ({ LBS: 'LB', GALLON: 'GAL', FLOZ: 'FL OZ', LTR: 'L', EACH: 'EA' } as Record<string, string>)[single[2].replace(/\s+/g, '')] ?? single[2].replace(/\s+/g, ' ');
  return { packCount: null, packUnitQuantity: null, measurementUnit, totalPackageQuantity: Number(single[1]) };
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
      const established = establishFieldProvenance(result.data);
      const extracted = established.data;
      const invoiceDate = normalizeExtractedDate(extracted.invoiceDate);
      const dueDate = normalizeExtractedDate(extracted.dueDate, new Date(), true);
      const uncertainFields = new Set(extracted.uncertainFields);
      established.unsupportedFields.forEach((field) => uncertainFields.add(`UNSUPPORTED_${field}`));
      if (extracted.invoiceDate && !invoiceDate) uncertainFields.add('invoiceDate');
      if (extracted.dueDate && !dueDate) uncertainFields.add('dueDate');
      const reconciliation = reconcileInvoice(extracted);
      reconciliation.reasons.forEach((reason) => uncertainFields.add(reason));
      const confidence = extractionConfidence({ ...extracted, invoiceDate: invoiceDate ? extracted.invoiceDate : null, uncertainFields: [...uncertainFields] });
      const vendor = extracted.vendorName ? await this.prisma.vendor.findFirst({ where: { organizationId: invoice.organizationId, normalizedName: extracted.vendorName.trim().toLowerCase().replace(/\s+/g, ' ') } }) : null;
      let applied = false;
      await this.prisma.$transaction(async (tx) => {
        const current = await tx.invoice.findUnique({ where: { id: invoiceId }, select: { reviewStatus: true, extractionStatus: true, extractionStartedAt: true } });
        if (!current || current.reviewStatus === ReviewStatus.REVIEWED || (current.extractionStatus && current.extractionStatus !== ExtractionStatus.PROCESSING) || (current.extractionStartedAt && invoice.extractionStartedAt && current.extractionStartedAt.getTime() !== invoice.extractionStartedAt.getTime())) return;
        applied = true;
        await tx.invoiceLineItem.deleteMany({ where: { invoiceId } });
        if (extracted.lineItems.length) await tx.invoiceLineItem.createMany({ data: extracted.lineItems.map((line, index) => {
          const parsedPackage = parsePackageSize(line.packSize);
          return { invoiceId, organizationId: invoice.organizationId, restaurantLocationId: invoice.restaurantLocationId, lineNumber: line.lineNumber || index + 1, sourcePage: line.sourcePage, rawDescription: line.rawDescription, normalizedName: line.normalizedName, sku: line.sku, quantity: line.quantity === null ? null : new Prisma.Decimal(line.quantity), unit: line.unit, packSize: line.packSize, packCount: parsedPackage?.packCount == null ? null : new Prisma.Decimal(parsedPackage.packCount), packUnitQuantity: parsedPackage?.packUnitQuantity == null ? null : new Prisma.Decimal(parsedPackage.packUnitQuantity), measurementUnit: parsedPackage?.measurementUnit ?? null, totalPackageQuantity: parsedPackage ? new Prisma.Decimal(parsedPackage.totalPackageQuantity) : null, unitPrice: line.unitPrice === null ? null : new Prisma.Decimal(line.unitPrice), extendedPrice: line.extendedPrice === null ? null : new Prisma.Decimal(line.extendedPrice), category: line.category, productAttributes: line.productAttributes ? line.productAttributes as Prisma.InputJsonValue : Prisma.DbNull, uncertainFields: line.uncertainFields, fieldProvenance: established.lineProvenance[index] as Prisma.InputJsonValue, confidence: new Prisma.Decimal(confidence.lines[index].toFixed(4)) };
        }) });
        await tx.invoice.update({ where: { id: invoiceId }, data: { vendorId: vendor?.id, extractedVendorName: extracted.vendorName, extractedVendorAddress: extracted.vendorAddress, invoiceNumber: extracted.invoiceNumber, invoiceDate, dueDate, subtotal: extracted.subtotal === null ? null : new Prisma.Decimal(extracted.subtotal), tax: extracted.tax === null ? null : new Prisma.Decimal(extracted.tax), otherFees: extracted.otherFees === null ? null : new Prisma.Decimal(extracted.otherFees), discount: extracted.discount === null ? null : new Prisma.Decimal(extracted.discount), total: extracted.total === null ? null : new Prisma.Decimal(extracted.total), currency: extracted.currency, fieldProvenance: established.provenance as Prisma.InputJsonValue, status: InvoiceStatus.COMPLETED, extractionStatus: ExtractionStatus.COMPLETED, extractionProvider: result.provider, extractionModel: result.model, extractionConfidence: new Prisma.Decimal(confidence.overall.toFixed(4)), extractionCompletedAt: new Date(), extractionDurationMs: Date.now() - startedAt, extractionError: null, uncertainFields: [...uncertainFields], rawExtractionJson: { ...result.data, sanitized: extracted, reconciliation } as Prisma.InputJsonValue, extractionUsage: result.usage ? result.usage as Prisma.InputJsonValue : Prisma.DbNull, reviewStatus: confidence.needsReview ? ReviewStatus.NEEDS_REVIEW : ReviewStatus.NOT_REVIEWED } });
      });
      if (!applied) {
        await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.extraction_discarded_reviewed', entityType: 'Invoice', entityId: invoiceId, metadata: { model: result.model, durationMs: Date.now() - startedAt } });
        return;
      }
      const usage = result.usage as { input_tokens?: number; output_tokens?: number; total_tokens?: number } | null;
      await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.extraction_completed', entityType: 'Invoice', entityId: invoiceId, metadata: { provider: result.provider, model: result.model, lineItemCount: extracted.lineItems.length, unsupportedFieldCount: established.unsupportedFields.length, durationMs: Date.now() - startedAt, inputTokens: usage?.input_tokens, outputTokens: usage?.output_tokens, totalTokens: usage?.total_tokens } });
    } catch (error) {
      const safeMessage = safeExtractionError(error);
      await this.prisma.invoice.updateMany({ where: { id: invoiceId, reviewStatus: { not: ReviewStatus.REVIEWED }, extractionStatus: ExtractionStatus.PROCESSING, extractionStartedAt: invoice.extractionStartedAt }, data: { status: InvoiceStatus.FAILED, extractionStatus: ExtractionStatus.FAILED, extractionCompletedAt: new Date(), extractionDurationMs: Date.now() - startedAt, extractionError: safeMessage } });
      await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.extraction_failed', entityType: 'Invoice', entityId: invoiceId, metadata: { failureStage: 'EXTRACTION', errorCode: error instanceof Error && (error.name.toLowerCase().includes('timeout') || error.message.toLowerCase().includes('timeout')) ? 'PROVIDER_TIMEOUT' : 'EXTRACTION_FAILED', errorType: error instanceof Error ? error.name : 'UnknownError', durationMs: Date.now() - startedAt, attempt: invoice.extractionAttemptCount } });
      await this.notifications?.notifyOperational({ organizationId: invoice.organizationId, restaurantLocationId: invoice.restaurantLocationId, type: 'INVOICE_EXTRACTION_FAILED' as any, severity: 'HIGH' as any, title: 'Invoice extraction failed', body: 'Invoice extraction failed for a recent upload.', deepLinkType: 'OPEN_INVOICE', deepLinkId: invoiceId, dedupeKey: `invoice-extraction-failed:${invoiceId}:${error instanceof Error ? error.name : 'unknown'}` });
    }
  }
}
