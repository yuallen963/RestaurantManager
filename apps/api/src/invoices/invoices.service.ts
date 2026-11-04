import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { BankReconciliationStatus, ExtractionStatus, InvoiceDuplicateResolution, InvoiceStatus, OrganizationRole, Prisma, ReviewStatus } from '@prisma/client';
import { AuditService } from '../audit.service';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PrismaService } from '../prisma.service';
import { CompleteUploadDto, InvoiceListQuery, ResolveInvoiceDuplicateDto, ReviewInvoiceDto, UpdateInvoiceDto, UpdateLineItemDto, UploadIntentDto } from './dto';
import { createHash } from 'crypto';
import { InvoiceExtractionProcessor, parsePackageSize } from './extraction.processor';
import { InvoiceStorageService } from './storage.service';
import { duplicateCandidateKind, distinctReviewedKey, invoiceIdentity, InvoiceIdentityFields } from './duplicate-identity';
import { reviewDiscrepancies } from './review-reconciliation';
const invoiceWriteRoles = [OrganizationRole.OWNER, OrganizationRole.ADMIN, OrganizationRole.MANAGER];
const clearDuplicateDecision = { duplicateResolution: InvoiceDuplicateResolution.UNRESOLVED, duplicateOfInvoiceId: null, duplicateResolvedByUserId: null,
  duplicateResolvedAt: null, duplicateResolutionReason: null, duplicateDecisionFingerprint: null, duplicateFingerprint: null };
const allowedTypes = new Set(['application/pdf', 'image/jpeg', 'image/png']); const maxFileSize = 15 * 1024 * 1024; const safeName = (name: string) => name.replace(/[^a-zA-Z0-9._-]/g, '_').slice(-160) || 'invoice';
const contentMatches = (mimeType: string, file: Buffer) => {
  if (mimeType === 'application/pdf') return file.length >= 4 && file.subarray(0, 4).equals(Buffer.from('%PDF'));
  if (mimeType === 'image/jpeg') return file.length >= 3 && file[0] === 0xff && file[1] === 0xd8 && file[2] === 0xff;
  if (mimeType === 'image/png') return file.length >= 8 && file.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  return false;
};
export const MAX_EXTRACTION_ATTEMPTS = 3;
export const STALE_EXTRACTION_MS = 10 * 60 * 1000;
const money = (value: unknown, name: string) => { if (value === undefined) return undefined; if (value === null || value === '') return null; const parsed = new Prisma.Decimal(value as string | number); if (!parsed.isFinite() || parsed.lt(0)) throw new BadRequestException(`${name} cannot be negative`); return parsed; };
const correctedProvenance = (current: unknown, data: UpdateInvoiceDto | ReviewInvoiceDto) => {
  const provenance = current && typeof current === 'object' && !Array.isArray(current) ? { ...(current as Record<string, unknown>) } : {};
  const values: Record<string, unknown> = { invoiceNumber: data.invoiceNumber, invoiceDate: data.invoiceDate, subtotal: data.subtotal, tax: data.tax, otherFees: data.otherFees, discount: data.discount, total: data.total, currency: data.currency };
  if ('vendorName' in data && data.vendorName !== undefined) values.vendorName = data.vendorName;
  for (const [field, value] of Object.entries(values)) {
    if (value === undefined) continue;
    provenance[field] = value === null || value === '' ? { kind: 'MISSING', verified: true } : { kind: 'OBSERVED', sourceText: 'Confirmed by user', verified: true };
  }
  return provenance as Prisma.InputJsonValue;
};
const correctedLineProvenance = (current: unknown, data: UpdateLineItemDto) => {
  const provenance = current && typeof current === 'object' && !Array.isArray(current) ? { ...(current as Record<string, unknown>) } : {};
  for (const field of ['rawDescription', 'sku', 'quantity', 'unit', 'packSize', 'unitPrice', 'extendedPrice'] as const) {
    const value = data[field];
    if (value === undefined) continue;
    provenance[field] = value === null || value === '' ? { kind: 'MISSING', verified: true } : { kind: 'OBSERVED', sourceText: 'Confirmed by user', verified: true };
  }
  return provenance as Prisma.InputJsonValue;
};
@Injectable()
export class InvoicesService {
  constructor(private readonly prisma: PrismaService, private readonly access: OrganizationAccessService, private readonly audit: AuditService, private readonly storage: InvoiceStorageService, private readonly extraction: InvoiceExtractionProcessor) {}
  private async location(userId: string, id: string, roles?: OrganizationRole[]) { const location = await this.prisma.restaurantLocation.findUnique({ where: { id } }); if (!location) throw new NotFoundException('Location not found'); await this.access.requireMember(userId, location.organizationId, ...(roles ? [roles] : [])); return location; }
  private async invoice(userId: string, id: string, roles?: OrganizationRole[]) { const invoice = await this.prisma.invoice.findUnique({ where: { id } }); if (!invoice) throw new NotFoundException('Invoice not found'); await this.access.requireMember(userId, invoice.organizationId, ...(roles ? [roles] : [])); return invoice; }
  private async vendor(organizationId: string, vendorId?: string | null) { if (!vendorId) return; const vendor = await this.prisma.vendor.findFirst({ where: { id: vendorId, organizationId } }); if (!vendor) throw new ForbiddenException('Vendor is not available'); }
  private async candidates(tx: Prisma.TransactionClient, current: InvoiceIdentityFields) {
    const identity = invoiceIdentity(current);
    const conditions: Prisma.InvoiceWhereInput[] = [];
    if (current.attachmentHash) conditions.push({ attachmentHash: current.attachmentHash });
    if (identity && current.invoiceDate && current.vendorId && current.total != null) {
      const day = current.invoiceDate.toISOString().slice(0, 10);
      conditions.push({ vendorId: current.vendorId, currency: current.currency?.trim().toUpperCase(), total: current.total,
        invoiceDate: { gte: new Date(`${day}T00:00:00.000Z`), lt: new Date(new Date(`${day}T00:00:00.000Z`).getTime() + 86400000) } });
    }
    if (!conditions.length) return [];
    const rows = await tx.invoice.findMany({ where: { organizationId: current.organizationId, restaurantLocationId: current.restaurantLocationId, id: { not: current.id }, OR: conditions }, orderBy: [{ createdAt: 'asc' }, { id: 'asc' }] });
    return rows.flatMap((row) => { const kind = duplicateCandidateKind(current, row); return kind ? [{ row, kind }] : []; });
  }
  async duplicateCandidates(userId: string, id: string) {
    const invoice = await this.invoice(userId, id);
    const membership = await this.access.requireMember(userId, invoice.organizationId);
    const identity = invoiceIdentity(invoice);
    const matches = await this.candidates(this.prisma, invoice);
    const decisions = await this.prisma.invoiceDuplicateDecision.findMany({ where: { invoiceId: id, fingerprint: identity?.fingerprint ?? '' } });
    return { fingerprint: identity?.fingerprint ?? null, resolution: invoice.duplicateResolution,
      canResolve: membership.role === OrganizationRole.OWNER || membership.role === OrganizationRole.ADMIN,
      candidates: matches.map(({ row, kind }) => ({ id: row.id, kind, invoiceNumber: row.invoiceNumber, invoiceDate: row.invoiceDate, total: row.total, currency: row.currency, reviewStatus: row.reviewStatus,
        decision: decisions.find((decision) => decision.candidateInvoiceId === row.id)?.resolution ?? null })) };
  }
  async resolveDuplicate(userId: string, id: string, data: ResolveInvoiceDuplicateDto) {
    const invoice = await this.invoice(userId, id, [OrganizationRole.OWNER, OrganizationRole.ADMIN]);
    if (invoice.reviewStatus === ReviewStatus.REVIEWED) throw new BadRequestException('Reviewed invoices cannot be changed');
    if (data.resolution === InvoiceDuplicateResolution.UNRESOLVED) throw new BadRequestException('Choose duplicate or confirmed distinct');
    if (data.reason.trim().length < 10) throw new BadRequestException('Explain why this invoice is a duplicate or distinct purchase');
    const identity = invoiceIdentity(invoice);
    if (!identity || data.expectedFingerprint !== identity.fingerprint) throw new ConflictException('Invoice details changed. Refresh duplicate candidates before deciding.');
    const candidates = await this.candidates(this.prisma, invoice);
    const match = candidates.find(({ row }) => row.id === data.candidateInvoiceId && row.reviewStatus === ReviewStatus.REVIEWED);
    if (!match) throw new ConflictException('The matching reviewed invoice changed. Refresh duplicate candidates.');
    const saved = await this.prisma.$transaction(async (tx) => {
      const prior = await tx.invoiceDuplicateDecision.findUnique({ where: { invoiceId_candidateInvoiceId: {
        invoiceId: id, candidateInvoiceId: match.row.id } } });
      if (prior?.resolution === data.resolution && prior.fingerprint === identity.fingerprint)
        throw new ConflictException('This decision was already recorded. Refresh duplicate candidates.');
      const saved = await tx.invoice.update({ where: { id, reviewStatus: { not: ReviewStatus.REVIEWED }, updatedAt: invoice.updatedAt }, data: {
        duplicateResolution: data.resolution, duplicateOfInvoiceId: match.row.id, duplicateResolvedByUserId: userId,
        duplicateResolvedAt: new Date(), duplicateResolutionReason: data.reason.trim(), duplicateDecisionFingerprint: identity.fingerprint,
        duplicateFingerprint: identity.fingerprint,
      } });
      if (data.resolution === InvoiceDuplicateResolution.DUPLICATE || invoice.duplicateResolution === InvoiceDuplicateResolution.DUPLICATE)
        await tx.invoiceDuplicateDecision.deleteMany({ where: { invoiceId: id } });
      await tx.invoiceDuplicateDecision.upsert({ where: { invoiceId_candidateInvoiceId: { invoiceId: id, candidateInvoiceId: match.row.id } },
        create: { invoiceId: id, candidateInvoiceId: match.row.id, resolution: data.resolution, fingerprint: identity.fingerprint,
          reviewerUserId: userId, reason: data.reason.trim() },
        update: { resolution: data.resolution, fingerprint: identity.fingerprint, reviewerUserId: userId,
          reason: data.reason.trim(), decidedAt: new Date() } });
      return saved;
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable }).catch((error) => {
      if (error instanceof Prisma.PrismaClientKnownRequestError && ['P2025', 'P2034'].includes(error.code)) throw new ConflictException('Invoice changed. Refresh duplicate candidates.');
      throw error;
    });
    await this.audit.log({ userId, organizationId: invoice.organizationId, action: `invoice.duplicate_${data.resolution.toLowerCase()}`, entityType: 'Invoice', entityId: id,
      metadata: { candidateInvoiceId: match.row.id, reason: data.reason.trim(), fingerprint: identity.fingerprint } });
    return saved;
  }
  async uploadIntent(userId: string, data: UploadIntentDto) { if (!allowedTypes.has(data.mimeType)) throw new BadRequestException('Only PDF, JPG, JPEG, and PNG files are supported'); if (data.fileSize > maxFileSize) throw new BadRequestException('Invoice files must be 15 MB or smaller'); const location = await this.location(userId, data.restaurantLocationId, invoiceWriteRoles); await this.vendor(location.organizationId, data.vendorId); const originalFileName = data.fileName.trim(); if (!originalFileName) throw new BadRequestException('File name is required'); const invoice = await this.prisma.invoice.create({ data: { organizationId: location.organizationId, restaurantLocationId: location.id, vendorId: data.vendorId, fileName: safeName(originalFileName), originalFileName, fileType: data.mimeType, fileSize: data.fileSize, storageKey: 'pending', createdByUserId: userId, status: InvoiceStatus.PROCESSING } }); const storageKey = `organizations/${location.organizationId}/locations/${location.id}/invoices/${invoice.id}/${safeName(originalFileName)}`; const saved = await this.prisma.invoice.update({ where: { id: invoice.id }, data: { storageKey } }); try { const uploadUrl = await this.storage.putUrl(storageKey, data.mimeType); await this.audit.log({ userId, organizationId: location.organizationId, action: 'invoice.created', entityType: 'Invoice', entityId: saved.id, metadata: { fileType: data.mimeType, fileSize: data.fileSize } }); return { invoice: saved, uploadUrl, headers: { 'Content-Type': data.mimeType } }; } catch (error) { await this.prisma.invoice.delete({ where: { id: invoice.id } }); throw error; } }
  async complete(userId: string, id: string, _data: CompleteUploadDto) { const invoice = await this.invoice(userId, id, invoiceWriteRoles); let file: Buffer; try { file = await this.storage.get(invoice.storageKey); } catch (error) { await this.prisma.invoice.updateMany({ where: { id, reviewStatus: { not: ReviewStatus.REVIEWED }, attachmentHash: null }, data: { status: InvoiceStatus.FAILED, extractionStatus: ExtractionStatus.FAILED, extractionCompletedAt: new Date(), extractionError: 'The uploaded file could not be found. Choose the file and upload it again.' } }); await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.upload_completion_failed', entityType: 'Invoice', entityId: id, metadata: { failureStage: 'STORAGE_VERIFICATION', errorCode: 'STORAGE_OBJECT_UNAVAILABLE', errorType: error instanceof Error ? error.name : 'UnknownError' } }); throw new BadRequestException('The uploaded invoice file is unavailable. Please upload it again.'); } if (file.length !== invoice.fileSize || !contentMatches(invoice.fileType, file)) { try { await this.storage.remove(invoice.storageKey); } catch {} await this.prisma.invoice.updateMany({ where: { id, reviewStatus: { not: ReviewStatus.REVIEWED }, attachmentHash: null }, data: { status: InvoiceStatus.FAILED, extractionStatus: ExtractionStatus.FAILED, extractionCompletedAt: new Date(), extractionError: 'The uploaded file did not match the selected invoice format. Choose the original PDF, JPEG, or PNG and try again.' } }); await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.upload_completion_failed', entityType: 'Invoice', entityId: id, metadata: { failureStage: 'CONTENT_VALIDATION', errorCode: file.length !== invoice.fileSize ? 'FILE_SIZE_MISMATCH' : 'FILE_SIGNATURE_MISMATCH' } }); throw new BadRequestException('The uploaded file does not match the selected invoice format.'); } const attachmentHash = createHash('sha256').update(file).digest('hex'); const duplicate = await this.prisma.invoice.findFirst({ where: { organizationId: invoice.organizationId, restaurantLocationId: invoice.restaurantLocationId, attachmentHash, id: { not: id } } }); if (duplicate) { await this.storage.remove(invoice.storageKey); await this.prisma.invoice.delete({ where: { id } }); await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.duplicate_skipped', entityType: 'Invoice', entityId: duplicate.id, metadata: { duplicateUploadId: id } }); return duplicate; } let saved;
    try { saved = await this.prisma.invoice.update({ where: { id }, data: { status: InvoiceStatus.UPLOADED, attachmentHash } }); }
    catch (error) {
      if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== 'P2002') throw error;
      const concurrent = await this.prisma.invoice.findUnique({ where: { organizationId_restaurantLocationId_attachmentHash: {
        organizationId: invoice.organizationId, restaurantLocationId: invoice.restaurantLocationId, attachmentHash } } });
      if (!concurrent || concurrent.id === id) throw error;
      await this.storage.remove(invoice.storageKey);
      await this.prisma.invoice.delete({ where: { id } });
      await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.duplicate_skipped', entityType: 'Invoice', entityId: concurrent.id,
        metadata: { duplicateUploadId: id, concurrent: true } });
      return concurrent;
    } await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.uploaded', entityType: 'Invoice', entityId: id }); if (this.extraction.isConfigured() && saved.extractionStatus === ExtractionStatus.NOT_STARTED) await this.startExtraction(userId, id); return saved; }
  async list(userId: string, query: InvoiceListQuery) { const location = await this.location(userId, query.restaurantLocationId); const startDate = query.startDate ? new Date(query.startDate) : undefined; const endDate = query.endDate ? new Date(query.endDate) : undefined; if (endDate && /^\d{4}-\d{2}-\d{2}$/.test(query.endDate!)) endDate.setUTCHours(23, 59, 59, 999); const dateRange = startDate || endDate ? { gte: startDate, lte: endDate } : undefined; const invoices = await this.prisma.invoice.findMany({ where: { organizationId: location.organizationId, restaurantLocationId: location.id, vendorId: query.vendorId, status: query.status, OR: dateRange ? [{ invoiceDate: dateRange }, { invoiceDate: null, createdAt: dateRange }] : undefined }, include: { bankTransactions: { where: { reconciliationStatus: BankReconciliationStatus.MATCHED_INVOICE, removedAt: null }, select: { id: true } } }, orderBy: [{ invoiceDate: { sort: 'desc', nulls: 'last' } }, { createdAt: 'desc' }, { id: 'desc' }] }); const vendors = await this.prisma.vendor.findMany({ where: { organizationId: location.organizationId, id: { in: invoices.map((i) => i.vendorId).filter(Boolean) as string[] } }, select: { id: true, name: true } }); const names = new Map(vendors.map((vendor) => [vendor.id, vendor.name])); return invoices.map((invoice) => ({ ...invoice, vendorName: invoice.vendorId ? names.get(invoice.vendorId) ?? null : null, paymentStatus: invoice.bankTransactions.length > 0 ? 'PAID' : 'AWAITING_PAYMENT', canRetryExtraction: Boolean(invoice.attachmentHash) && invoice.extractionAttemptCount < MAX_EXTRACTION_ATTEMPTS && invoice.reviewStatus !== ReviewStatus.REVIEWED })); }
  async detail(userId: string, id: string) { const invoice = await this.invoice(userId, id); const vendor = invoice.vendorId ? await this.prisma.vendor.findFirst({ where: { id: invoice.vendorId, organizationId: invoice.organizationId }, select: { name: true } }) : null; return { ...invoice, vendorName: vendor?.name ?? invoice.extractedVendorName ?? null, canRetryExtraction: Boolean(invoice.attachmentHash) && invoice.extractionAttemptCount < MAX_EXTRACTION_ATTEMPTS && invoice.reviewStatus !== ReviewStatus.REVIEWED }; }
  async update(userId: string, id: string, data: UpdateInvoiceDto) { const invoice = await this.invoice(userId, id, invoiceWriteRoles); if (invoice.reviewStatus === ReviewStatus.REVIEWED) throw new BadRequestException('Reviewed invoices cannot be edited'); await this.vendor(invoice.organizationId, data.vendorId); const saved = await this.prisma.$transaction(async (tx) => { const saved = await tx.invoice.update({ where: { id, reviewStatus: { not: ReviewStatus.REVIEWED }, updatedAt: invoice.updatedAt }, data: { vendorId: data.vendorId, invoiceNumber: data.invoiceNumber, invoiceDate: data.invoiceDate ? new Date(data.invoiceDate) : data.invoiceDate === null ? null : undefined, subtotal: money(data.subtotal, 'Subtotal'), tax: money(data.tax, 'Tax'), otherFees: money(data.otherFees, 'Other fees'), discount: money(data.discount, 'Discount'), total: money(data.total, 'Total'), currency: data.currency?.trim().toUpperCase() || (data.currency === null ? null : undefined), fieldProvenance: correctedProvenance(invoice.fieldProvenance, data), notes: data.notes, ...(data.vendorId !== undefined || data.invoiceNumber !== undefined || data.invoiceDate !== undefined || data.currency !== undefined || data.total !== undefined ? clearDuplicateDecision : {}), status: data.status ?? InvoiceStatus.COMPLETED } }); if (data.vendorId !== undefined || data.invoiceNumber !== undefined || data.invoiceDate !== undefined || data.currency !== undefined || data.total !== undefined) await tx.invoiceDuplicateDecision.deleteMany({ where: { invoiceId: id } }); return saved; }); await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.updated', entityType: 'Invoice', entityId: id }); return saved; }
  async startExtraction(userId: string, id: string) { const invoice = await this.invoice(userId, id, invoiceWriteRoles); if (invoice.reviewStatus === ReviewStatus.REVIEWED) throw new BadRequestException('Reviewed invoices cannot be re-extracted'); if (!invoice.attachmentHash || invoice.status === InvoiceStatus.PROCESSING) throw new BadRequestException('Invoice upload is not complete'); if (!this.extraction.isConfigured()) throw new BadRequestException('Invoice extraction is not configured'); const staleBefore = new Date(Date.now() - STALE_EXTRACTION_MS); const claimedAt = new Date(); const claim = await this.prisma.invoice.updateMany({ where: { id, reviewStatus: { not: ReviewStatus.REVIEWED }, extractionAttemptCount: { lt: MAX_EXTRACTION_ATTEMPTS }, OR: [{ extractionStatus: { not: ExtractionStatus.PROCESSING } }, { extractionStartedAt: { lt: staleBefore } }] }, data: { status: InvoiceStatus.UPLOADED, extractionStatus: ExtractionStatus.PROCESSING, extractionStartedAt: claimedAt, extractionCompletedAt: null, extractionDurationMs: null, extractionError: null, extractionAttemptCount: { increment: 1 } } }); if (claim.count === 0) { const current = await this.invoice(userId, id); if (current.extractionStatus === ExtractionStatus.PROCESSING && current.extractionStartedAt && current.extractionStartedAt > staleBefore) return current; if (current.extractionAttemptCount >= MAX_EXTRACTION_ATTEMPTS) throw new BadRequestException('Invoice extraction retry limit reached. Enter the invoice manually or contact support.'); throw new BadRequestException('Invoice extraction could not be started'); } const saved = await this.invoice(userId, id); await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.extraction_started', entityType: 'Invoice', entityId: id, metadata: { attempt: (invoice.extractionAttemptCount ?? 0) + 1, recovery: invoice.extractionStatus === ExtractionStatus.PROCESSING } }); setImmediate(() => void this.extraction.process(id, userId)); return saved; }
  async extractionStatus(userId: string, id: string) { const invoice = await this.invoice(userId, id); return { invoiceId: id, extractionStatus: invoice.extractionStatus, extractionConfidence: invoice.extractionConfidence, extractionError: invoice.extractionError, reviewStatus: invoice.reviewStatus, extractionStartedAt: invoice.extractionStartedAt, extractionCompletedAt: invoice.extractionCompletedAt, extractionDurationMs: invoice.extractionDurationMs, extractionAttemptCount: invoice.extractionAttemptCount }; }
  async lineItems(userId: string, id: string) { const invoice = await this.invoice(userId, id); return this.prisma.invoiceLineItem.findMany({ where: { invoiceId: id, organizationId: invoice.organizationId, restaurantLocationId: invoice.restaurantLocationId }, orderBy: [{ lineNumber: 'asc' }, { id: 'asc' }] }); }
  async updateLineItem(userId: string, invoiceId: string, lineItemId: string, data: UpdateLineItemDto) {
    const invoice = await this.invoice(userId, invoiceId, invoiceWriteRoles);
    const item = await this.prisma.invoiceLineItem.findFirst({ where: { id: lineItemId, invoiceId,
      organizationId: invoice.organizationId, restaurantLocationId: invoice.restaurantLocationId } });
    if (!item) throw new NotFoundException('Invoice line item not found');
    if (invoice.reviewStatus === ReviewStatus.REVIEWED) throw new BadRequestException('Reviewed invoices cannot be edited');
    const parsedPackage = data.packSize === undefined ? undefined : parsePackageSize(data.packSize);
    const saved = await this.prisma.$transaction(async (tx) => {
      await tx.invoice.update({ where: { id: invoiceId, reviewStatus: { not: ReviewStatus.REVIEWED }, updatedAt: invoice.updatedAt },
        data: clearDuplicateDecision });
      await tx.invoiceDuplicateDecision.deleteMany({ where: { invoiceId } });
      return tx.invoiceLineItem.update({ where: { id: lineItemId }, data: {
        rawDescription: data.rawDescription, normalizedName: data.normalizedName, sku: data.sku,
        quantity: data.quantity === undefined ? undefined : money(data.quantity, 'Quantity'), unit: data.unit,
        packSize: data.packSize, packCount: parsedPackage === undefined ? undefined : parsedPackage?.packCount,
        packUnitQuantity: parsedPackage === undefined ? undefined : parsedPackage?.packUnitQuantity,
        measurementUnit: parsedPackage === undefined ? undefined : parsedPackage?.measurementUnit,
        totalPackageQuantity: parsedPackage === undefined ? undefined : parsedPackage?.totalPackageQuantity,
        unitPrice: data.unitPrice === undefined ? undefined : money(data.unitPrice, 'Unit price'),
        extendedPrice: data.extendedPrice === undefined ? undefined : money(data.extendedPrice, 'Extended price'),
        category: data.category,
        uncertainFields: data.packSize === undefined ? item.uncertainFields : parsedPackage
          ? item.uncertainFields.filter((field) => field !== 'AMBIGUOUS_PACK_SIZE')
          : [...new Set([...item.uncertainFields, 'AMBIGUOUS_PACK_SIZE'])],
        fieldProvenance: correctedLineProvenance(item.fieldProvenance, data),
      } });
    }).catch((error) => {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025')
        throw new ConflictException('Invoice changed. Refresh before editing this line.');
      throw error;
    });
    await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.line_item_corrected',
      entityType: 'InvoiceLineItem', entityId: lineItemId, metadata: { invoiceId } });
    return saved;
  }
  async review(userId: string, id: string, data: ReviewInvoiceDto) {
    const invoice = await this.invoice(userId, id, invoiceWriteRoles);
    if (invoice.reviewStatus === ReviewStatus.REVIEWED) throw new BadRequestException('Reviewed invoices cannot be edited');
    await this.vendor(invoice.organizationId, data.vendorId);
    const invoiceDate = data.invoiceDate ? new Date(data.invoiceDate) : data.invoiceDate === null ? null : undefined;
    if (invoiceDate && invoiceDate > new Date(Date.now() + 86400000)) throw new BadRequestException('Invoice date cannot be in the future');
    const changes = {
      vendorId: data.vendorId,
      extractedVendorName: data.vendorName === undefined ? undefined : data.vendorName?.trim() || null,
      invoiceNumber: data.invoiceNumber, invoiceDate,
      subtotal: money(data.subtotal, 'Subtotal'), tax: money(data.tax, 'Tax'),
      otherFees: money(data.otherFees, 'Other fees'), discount: money(data.discount, 'Discount'),
      total: money(data.total, 'Total'),
      currency: data.currency?.trim().toUpperCase() || (data.currency === null ? null : undefined),
      fieldProvenance: correctedProvenance(invoice.fieldProvenance, data), notes: data.notes,
      ...(!data.markReviewed && (data.vendorId !== undefined || data.invoiceNumber !== undefined || data.invoiceDate !== undefined || data.currency !== undefined || data.total !== undefined) ? clearDuplicateDecision : {}),
    };
    if (!data.markReviewed) {
      const saved = await this.prisma.$transaction(async (tx) => { const saved = await tx.invoice.update({ where: { id, reviewStatus: { not: ReviewStatus.REVIEWED }, updatedAt: invoice.updatedAt }, data: changes }); if (data.vendorId !== undefined || data.invoiceNumber !== undefined || data.invoiceDate !== undefined || data.currency !== undefined || data.total !== undefined) await tx.invoiceDuplicateDecision.deleteMany({ where: { invoiceId: id } }); return saved; });
      await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.review_updated', entityType: 'Invoice', entityId: id });
      return saved;
    }
    const proposed = { ...invoice, ...Object.fromEntries(Object.entries(changes).filter(([, value]) => value !== undefined)) };
    if (!(proposed.vendorId || proposed.extractedVendorName) || !proposed.invoiceDate || proposed.total == null)
      throw new BadRequestException('Vendor, invoice date, and total are required before review');
    const lines = await this.prisma.invoiceLineItem.findMany({ where: { invoiceId: id, organizationId: invoice.organizationId, restaurantLocationId: invoice.restaurantLocationId }, select: { id: true, rawDescription: true, quantity: true, unit: true, unitPrice: true, extendedPrice: true, fieldProvenance: true } });
    if (lines.some((line) => !line.rawDescription.trim())) throw new BadRequestException('Every line item requires a description');
    const mismatch = reviewDiscrepancies({ subtotal: proposed.subtotal, tax: proposed.tax, otherFees: proposed.otherFees,
      discount: proposed.discount, total: proposed.total, lines });
    if (mismatch.length) throw new BadRequestException(`Invoice totals do not reconcile. Correct these amounts before review: ${mismatch.join('; ')}`);
    const currentProvenance = proposed.fieldProvenance && typeof proposed.fieldProvenance === 'object' && !Array.isArray(proposed.fieldProvenance) ? proposed.fieldProvenance as Record<string, any> : {};
    const verifiedProvenance = Object.fromEntries(Object.entries(currentProvenance).map(([field, value]) => [field, { ...(value as object), verified: true }]));
    const reviewed = await this.prisma.$transaction(async (tx) => {
      const identity = invoiceIdentity(proposed);
      if (invoice.duplicateResolution === InvoiceDuplicateResolution.DUPLICATE)
        throw new ConflictException('This invoice was marked as a duplicate and cannot become trusted.');
      const matches = await this.candidates(tx, proposed);
      const reviewedMatches = matches.filter(({ row }) => row.reviewStatus === ReviewStatus.REVIEWED);
      const distinct = invoice.duplicateResolution === InvoiceDuplicateResolution.CONFIRMED_DISTINCT;
      const decisions = await tx.invoiceDuplicateDecision.findMany({ where: { invoiceId: id, fingerprint: identity?.fingerprint ?? '',
        resolution: InvoiceDuplicateResolution.CONFIRMED_DISTINCT } });
      const decidedIds = new Set(decisions.map((decision) => decision.candidateInvoiceId));
      if (reviewedMatches.length) {
        if (!identity || !distinct || invoice.duplicateDecisionFingerprint !== identity.fingerprint ||
            reviewedMatches.some(({ row }) => !decidedIds.has(row.id)))
          throw new ConflictException('Possible duplicate of a reviewed invoice. Confirm distinctness against every reviewed candidate.');
      } else if (distinct) {
        throw new ConflictException('The duplicate decision is stale. Refresh the candidates before review.');
      }
      const reviewedIdentityKey = identity ? (distinct ? distinctReviewedKey(identity.claimKey, id) : identity.claimKey) : null;
      for (const line of lines) {
        const current = line.fieldProvenance && typeof line.fieldProvenance === 'object' && !Array.isArray(line.fieldProvenance) ? line.fieldProvenance as Record<string, any> : {};
        const verified = Object.fromEntries(Object.entries(current).map(([field, value]) => [field, { ...(value as object), verified: true }]));
        await tx.invoiceLineItem.update({ where: { id: line.id }, data: { fieldProvenance: verified as Prisma.InputJsonValue } });
      }
      return tx.invoice.update({ where: { id, reviewStatus: { not: ReviewStatus.REVIEWED }, updatedAt: invoice.updatedAt }, data: { ...changes,
        reviewedIdentityKey, duplicateFingerprint: identity?.fingerprint ?? null,
        status: InvoiceStatus.COMPLETED, reviewStatus: ReviewStatus.REVIEWED, reviewedAt: new Date(), reviewedByUserId: userId,
        uncertainFields: [], fieldProvenance: verifiedProvenance as Prisma.InputJsonValue } });
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable }).catch((error) => {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002')
        throw new ConflictException('Another reviewed invoice claimed this purchase identity. Refresh duplicate candidates.');
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025')
        throw new ConflictException('Invoice changed while you were reviewing it. Refresh and review the latest details.');
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2034')
        throw new ConflictException('Another invoice was reviewed concurrently. Refresh duplicate candidates and review again.');
      throw error;
    });
    await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.marked_reviewed', entityType: 'Invoice', entityId: id });
    return reviewed;
  }
  async delete(userId: string, id: string) {
    const invoice = await this.invoice(userId, id, invoiceWriteRoles);
    const linkedDecision = await this.prisma.invoice.findFirst({ where: { organizationId: invoice.organizationId,
      restaurantLocationId: invoice.restaurantLocationId, duplicateOfInvoiceId: id }, select: { id: true } });
    const linkedDecisionRecord = await this.prisma.invoiceDuplicateDecision.findFirst({ where: { candidateInvoiceId: id }, select: { id: true } });
    if (linkedDecision || linkedDecisionRecord) throw new ConflictException('This invoice is referenced by a duplicate decision. Resolve or remove that invoice first.');
    const payment = await this.prisma.bankTransaction.findFirst({
      where: { invoiceId: id, reconciliationStatus: BankReconciliationStatus.MATCHED_INVOICE, removedAt: null },
      select: { id: true },
    });
    if (payment) {
      throw new ConflictException('This invoice has a bank payment link. Remove the payment link from Bank Transactions before deleting the invoice.');
    }
    await this.prisma.invoice.delete({ where: { id } });
    try { await this.storage.remove(invoice.storageKey); } catch (error) { console.error(`Unable to remove invoice object ${id}`, error); }
    await this.audit.log({ userId, organizationId: invoice.organizationId, action: 'invoice.deleted', entityType: 'Invoice', entityId: id });
  }
}
