import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { ExtractionStatus, ReviewStatus } from '@prisma/client';
import { extractionConfidence, InvoiceExtractionProcessor } from '../src/invoices/extraction.processor';
import { ExtractedInvoiceSchema } from '../src/invoices/extraction.provider';
import { InvoicesService } from '../src/invoices/invoices.service';

const extraction = { vendorName: 'Sysco', invoiceNumber: 'INV-1', invoiceDate: '2026-10-04', subtotal: 100, tax: 6, total: 106, uncertainFields: [], lineItems: [{ lineNumber: 1, rawDescription: 'CHKN BRST BNLS SKLS 4/10 LB', sku: '384920', quantity: 2, unit: 'CASE', packSize: '4 x 10 lb', unitPrice: 50, extendedPrice: 100, category: 'Food' as const, uncertainFields: [] }] };

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

  it('persists invoice fields and replaces line items atomically', async () => {
    const tx: any = { invoiceLineItem: { deleteMany: jest.fn(), createMany: jest.fn() }, invoice: { update: jest.fn() } };
    const prisma: any = { invoice: { findUnique: jest.fn().mockResolvedValue({ id: 'inv', organizationId: 'org', restaurantLocationId: 'loc', storageKey: 'key', fileType: 'application/pdf', originalFileName: 'invoice.pdf' }) }, vendor: { findFirst: jest.fn().mockResolvedValue({ id: 'vendor' }) }, $transaction: jest.fn(async (callback) => callback(tx)) };
    const provider: any = { extract: jest.fn().mockResolvedValue({ data: extraction, provider: 'openai', model: 'gpt-4.1-mini', usage: { input_tokens: 10 } }), isConfigured: () => true };
    const processor = new InvoiceExtractionProcessor(prisma, { get: jest.fn().mockResolvedValue(Buffer.from('pdf')) } as any, provider, { log: jest.fn() } as any);
    await processor.process('inv', 'user');
    expect(tx.invoiceLineItem.deleteMany).toHaveBeenCalledWith({ where: { invoiceId: 'inv' } });
    expect(tx.invoiceLineItem.createMany).toHaveBeenCalledWith(expect.objectContaining({ data: [expect.objectContaining({ rawDescription: 'CHKN BRST BNLS SKLS 4/10 LB', quantity: expect.anything(), extendedPrice: expect.anything() })] }));
    expect(tx.invoice.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ extractionStatus: ExtractionStatus.COMPLETED, reviewStatus: ReviewStatus.NOT_REVIEWED, extractedVendorName: 'Sysco', invoiceDate: new Date('2026-10-04T00:00:00.000Z') }) }));
  });

  it('records a failed extraction without persisting raw content to audit metadata', async () => {
    const prisma: any = { invoice: { findUnique: jest.fn().mockResolvedValue({ id: 'inv', organizationId: 'org', storageKey: 'missing' }), update: jest.fn() } };
    const audit: any = { log: jest.fn() };
    const processor = new InvoiceExtractionProcessor(prisma, { get: jest.fn().mockRejectedValue(new Error('missing')) } as any, {} as any, audit);
    await processor.process('inv', 'user');
    expect(prisma.invoice.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ extractionStatus: ExtractionStatus.FAILED }) }));
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ metadata: { errorType: 'Error' } }));
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
