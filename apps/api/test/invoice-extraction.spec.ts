import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { ExtractionStatus, ReviewStatus } from '@prisma/client';
import { extractionConfidence, InvoiceExtractionProcessor, normalizeExtractedDate, parsePackageSize } from '../src/invoices/extraction.processor';
import { ExtractedInvoiceSchema } from '../src/invoices/extraction.provider';
import { InvoicesService } from '../src/invoices/invoices.service';

const extraction = { vendorName: 'Sysco', vendorAddress: '123 Food Way', invoiceNumber: 'INV-1', invoiceDate: '2026-10-04', dueDate: '2026-11-04', subtotal: 100, tax: 6, otherFees: 0, total: 106, currency: 'USD', uncertainFields: [], lineItems: [{ lineNumber: 1, sourcePage: 1, rawDescription: 'CHKN BRST BNLS SKLS 4/10 LB', normalizedName: 'Chicken Breast', sku: '384920', quantity: 2, unit: 'CASE', packSize: '4 x 10 lb', unitPrice: 50, extendedPrice: 100, category: 'Food' as const, productAttributes: { brand: null, condition: 'Fresh', bone: 'Boneless', skin: 'Skinless', organic: null, grade: null, cut: 'Breast', size: null, packConfiguration: '4/10 LB' }, uncertainFields: [] }] };

describe('invoice extraction', () => {
  it('rejects malformed provider responses before persistence', () => {
    expect(() => ExtractedInvoiceSchema.parse({ vendorName: 'Sysco', lineItems: 'not-an-array' })).toThrow();
  });
  it('derives confidence without claiming provider-native confidence', () => {
    expect(extractionConfidence(extraction)).toEqual({ overall: 1, lines: [1], needsReview: false });
    const weak = extractionConfidence({ ...extraction, total: null, uncertainFields: ['total'], lineItems: [{ ...extraction.lineItems[0], quantity: null, uncertainFields: ['quantity'] }] });
    expect(weak.needsReview).toBe(true);
    expect(weak.overall).toBeLessThan(.75);
  });

  it.each([
    ['4/10 LB', 4, 10, 'LB', 40],
    ['6/5 LB', 6, 5, 'LB', 30],
    ['40 LB', null, null, 'LB', 40],
    ['12/16 OZ', 12, 16, 'OZ', 192],
    ['20/50 CT', 20, 50, 'CT', 1000],
  ])('parses unambiguous package notation %s', (raw, count, quantity, unit, total) => {
    expect(parsePackageSize(raw)).toEqual({ packCount: count, packUnitQuantity: quantity, measurementUnit: unit, totalPackageQuantity: total });
  });

  it('leaves ambiguous package text unstructured', () => {
    expect(parsePackageSize('CS APPROX')).toBeNull();
  });

  it('normalizes valid dates and rejects impossible or future dates', () => {
    expect(normalizeExtractedDate('2026-10-07', new Date('2026-10-09'))).toEqual(new Date('2026-10-07T00:00:00.000Z'));
    expect(normalizeExtractedDate('2026-02-31', new Date('2026-10-09'))).toBeNull();
    expect(normalizeExtractedDate('2027-10-07', new Date('2026-10-09'))).toBeNull();
  });

  it('persists invoice fields and replaces line items atomically', async () => {
    const tx: any = { invoiceLineItem: { deleteMany: jest.fn(), createMany: jest.fn() }, invoice: { findUnique: jest.fn().mockResolvedValue({ reviewStatus: ReviewStatus.NOT_REVIEWED }), update: jest.fn() } };
    const prisma: any = { invoice: { findUnique: jest.fn().mockResolvedValue({ id: 'inv', organizationId: 'org', restaurantLocationId: 'loc', storageKey: 'key', fileType: 'application/pdf', originalFileName: 'invoice.pdf', reviewStatus: ReviewStatus.NOT_REVIEWED }) }, vendor: { findFirst: jest.fn().mockResolvedValue({ id: 'vendor' }) }, $transaction: jest.fn(async (callback) => callback(tx)) };
    const provider: any = { extract: jest.fn().mockResolvedValue({ data: extraction, provider: 'openai', model: 'gpt-4.1-mini', usage: { input_tokens: 10 } }), isConfigured: () => true };
    const processor = new InvoiceExtractionProcessor(prisma, { get: jest.fn().mockResolvedValue(Buffer.from('pdf')) } as any, provider, { log: jest.fn() } as any);
    await processor.process('inv', 'user');
    expect(tx.invoiceLineItem.deleteMany).toHaveBeenCalledWith({ where: { invoiceId: 'inv' } });
    expect(tx.invoiceLineItem.createMany).toHaveBeenCalledWith(expect.objectContaining({ data: [expect.objectContaining({ rawDescription: 'CHKN BRST BNLS SKLS 4/10 LB', normalizedName: 'Chicken Breast', packCount: expect.anything(), totalPackageQuantity: expect.anything(), quantity: expect.anything(), extendedPrice: expect.anything() })] }));
    expect(tx.invoice.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ extractionStatus: ExtractionStatus.COMPLETED, reviewStatus: ReviewStatus.NOT_REVIEWED, extractedVendorName: 'Sysco', invoiceDate: new Date('2026-10-04T00:00:00.000Z'), extractionUsage: { input_tokens: 10 } }) }));
  });

  it('records a failed extraction without persisting raw content to audit metadata', async () => {
    const prisma: any = { invoice: { findUnique: jest.fn().mockResolvedValue({ id: 'inv', organizationId: 'org', restaurantLocationId: 'loc', storageKey: 'missing', reviewStatus: ReviewStatus.NOT_REVIEWED }), updateMany: jest.fn() } };
    const audit: any = { log: jest.fn() };
    const notifications: any = { notifyOperational: jest.fn() };
    const processor = new InvoiceExtractionProcessor(prisma, { get: jest.fn().mockRejectedValue(new Error('missing')) } as any, {} as any, audit, notifications);
    await processor.process('inv', 'user');
    expect(prisma.invoice.updateMany).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ extractionStatus: ExtractionStatus.FAILED, extractionError: 'Invoice extraction is temporarily unavailable. Your uploaded invoice is safe.' }) }));
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ metadata: expect.objectContaining({ errorType: 'Error' }) }));
    expect(notifications.notifyOperational).toHaveBeenCalledWith(expect.objectContaining({ type: 'INVOICE_EXTRACTION_FAILED', dedupeKey: 'invoice-extraction-failed:inv:Error', restaurantLocationId: 'loc' }));
  });

  it('aggregates multi-page line items into one invoice transaction', async () => {
    const multiPage = { ...extraction, lineItems: [extraction.lineItems[0], { ...extraction.lineItems[0], lineNumber: 2, sourcePage: 2, rawDescription: 'FRY OIL 2/35 LB', normalizedName: 'Frying Oil', packSize: '2/35 LB' }] };
    const tx: any = { invoiceLineItem: { deleteMany: jest.fn(), createMany: jest.fn() }, invoice: { findUnique: jest.fn().mockResolvedValue({ reviewStatus: ReviewStatus.NOT_REVIEWED }), update: jest.fn() } };
    const prisma: any = { invoice: { findUnique: jest.fn().mockResolvedValue({ id: 'inv', organizationId: 'org', restaurantLocationId: 'loc', storageKey: 'key', fileType: 'application/pdf', originalFileName: 'multi.pdf', reviewStatus: ReviewStatus.NOT_REVIEWED }) }, vendor: { findFirst: jest.fn() }, $transaction: (callback: (client: any) => unknown) => callback(tx) };
    const processor = new InvoiceExtractionProcessor(prisma, { get: jest.fn().mockResolvedValue(Buffer.from('pdf')) } as any, { extract: jest.fn().mockResolvedValue({ data: multiPage, provider: 'openai', model: 'gpt-4.1-mini', usage: null }) } as any, { log: jest.fn() } as any);
    await processor.process('inv', 'user');
    const lines = tx.invoiceLineItem.createMany.mock.calls[0][0].data;
    expect(lines).toHaveLength(2);
    expect(lines.map((line: any) => line.sourcePage)).toEqual([1, 2]);
    expect(lines[1]).toEqual(expect.objectContaining({ rawDescription: 'FRY OIL 2/35 LB', measurementUnit: 'LB', totalPackageQuantity: expect.anything() }));
  });

  it('discards a late provider result if the invoice was reviewed while processing', async () => {
    const tx: any = { invoiceLineItem: { deleteMany: jest.fn(), createMany: jest.fn() }, invoice: { findUnique: jest.fn().mockResolvedValue({ reviewStatus: ReviewStatus.REVIEWED }), update: jest.fn() } };
    const audit: any = { log: jest.fn() };
    const prisma: any = { invoice: { findUnique: jest.fn().mockResolvedValue({ id: 'inv', organizationId: 'org', restaurantLocationId: 'loc', storageKey: 'key', fileType: 'application/pdf', originalFileName: 'invoice.pdf', reviewStatus: ReviewStatus.NOT_REVIEWED }) }, vendor: { findFirst: jest.fn() }, $transaction: (callback: (client: any) => unknown) => callback(tx) };
    await new InvoiceExtractionProcessor(prisma, { get: jest.fn().mockResolvedValue(Buffer.from('pdf')) } as any, { extract: jest.fn().mockResolvedValue({ data: extraction, provider: 'openai', model: 'gpt-4.1-mini', usage: null }) } as any, audit).process('inv', 'user');
    expect(tx.invoiceLineItem.deleteMany).not.toHaveBeenCalled();
    expect(tx.invoice.update).not.toHaveBeenCalled();
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'invoice.extraction_discarded_reviewed' }));
  });

  it('enforces tenant authorization before extraction', async () => {
    const prisma: any = { invoice: { findUnique: jest.fn().mockResolvedValue({ id: 'inv', organizationId: 'org', reviewStatus: ReviewStatus.NOT_REVIEWED }) } };
    const access: any = { requireMember: jest.fn().mockRejectedValue(new ForbiddenException()) };
    const service = new InvoicesService(prisma, access, {} as any, {} as any, { isConfigured: () => true } as any);
    await expect(service.startExtraction('other-user', 'inv')).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('does not allow retry after human review', async () => {
    const prisma: any = { invoice: { findUnique: jest.fn().mockResolvedValue({ id: 'inv', organizationId: 'org', reviewStatus: ReviewStatus.REVIEWED }) } };
    const service = new InvoicesService(prisma, { requireMember: jest.fn() } as any, {} as any, {} as any, { isConfigured: () => true } as any);
    await expect(service.startExtraction('user', 'inv')).rejects.toBeInstanceOf(BadRequestException);
  });

  it('records reviewedBy and reviewedAt only after required fields are present', async () => {
    const first = { id: 'inv', organizationId: 'org', reviewStatus: ReviewStatus.NEEDS_REVIEW, vendorId: 'vendor', extractedVendorName: 'Sysco', invoiceDate: new Date('2026-10-04'), total: 106 };
    const reviewed = { ...first, reviewStatus: ReviewStatus.REVIEWED, reviewedByUserId: 'user' };
    const prisma: any = { invoice: { findUnique: jest.fn().mockResolvedValue(first), update: jest.fn().mockResolvedValueOnce(first).mockResolvedValueOnce(reviewed) }, invoiceLineItem: { findFirst: jest.fn().mockResolvedValue(null) }, vendor: { findFirst: jest.fn().mockResolvedValue({ id: 'vendor', organizationId: 'org' }) } };
    const audit: any = { log: jest.fn() };
    const service = new InvoicesService(prisma, { requireMember: jest.fn() } as any, audit, {} as any, {} as any);
    const result = await service.review('user', 'inv', { markReviewed: true });
    expect(result.reviewStatus).toBe(ReviewStatus.REVIEWED);
    expect(prisma.invoice.update).toHaveBeenLastCalledWith({ where: { id: 'inv' }, data: expect.objectContaining({ reviewStatus: ReviewStatus.REVIEWED, reviewedAt: expect.any(Date), reviewedByUserId: 'user' }) });
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'invoice.marked_reviewed' }));
  });

  it('tenant-scopes line-item edits', async () => {
    const prisma: any = { invoice: { findUnique: jest.fn().mockResolvedValue({ id: 'inv', organizationId: 'org', restaurantLocationId: 'loc', reviewStatus: ReviewStatus.NEEDS_REVIEW }) }, invoiceLineItem: { findFirst: jest.fn().mockResolvedValue(null) } };
    const service = new InvoicesService(prisma, { requireMember: jest.fn() } as any, {} as any, {} as any, {} as any);
    await expect(service.updateLineItem('user', 'inv', 'other-tenant-line', { rawDescription: 'x' })).rejects.toThrow('Invoice line item not found');
    expect(prisma.invoiceLineItem.findFirst).toHaveBeenCalledWith({ where: { id: 'other-tenant-line', invoiceId: 'inv', organizationId: 'org', restaurantLocationId: 'loc' } });
  });
});
