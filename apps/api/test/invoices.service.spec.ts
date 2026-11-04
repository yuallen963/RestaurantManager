import { BadRequestException, ConflictException, ForbiddenException } from '@nestjs/common';
import { InvoicesService } from '../src/invoices/invoices.service';
import { invoiceIdentity } from '../src/invoices/duplicate-identity';
import { Prisma } from '@prisma/client';

const location = { id: 'loc-a', organizationId: 'org-a' };
const invoiceBytes = Buffer.from('%PDF-invoice bytes');
const invoice = { id: 'invoice-a', organizationId: 'org-a', restaurantLocationId: 'loc-a', vendorId: null, storageKey: 'org/file.pdf', fileType: 'application/pdf', fileSize: invoiceBytes.length, status: 'UPLOADED', attachmentHash: 'hash-a', reviewStatus: 'NOT_REVIEWED', extractionStatus: 'NOT_STARTED', extractionStartedAt: null, extractionAttemptCount: 0, bankTransactions: [] };

function setup() {
  const prisma: any = {
    restaurantLocation: { findUnique: jest.fn().mockResolvedValue(location) },
    invoice: {
      create: jest.fn().mockResolvedValue({ ...invoice, storageKey: 'pending' }),
      update: jest.fn().mockImplementation(({ data }: any) => Promise.resolve({ ...invoice, ...data })),
      findUnique: jest.fn().mockResolvedValue(invoice),
      findFirst: jest.fn().mockResolvedValue(null),
      findMany: jest.fn().mockResolvedValue([invoice]),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      delete: jest.fn().mockResolvedValue(invoice),
    },
    vendor: { findFirst: jest.fn().mockResolvedValue(null), findMany: jest.fn().mockResolvedValue([]) },
    invoiceLineItem: {
      findFirst: jest.fn().mockResolvedValue(null),
      findMany: jest.fn().mockResolvedValue([]),
      update: jest.fn().mockResolvedValue({}),
    },
    bankTransaction: { findFirst: jest.fn().mockResolvedValue(null) },
  };
  prisma.$transaction = jest.fn((callback: any) => callback(prisma));
  const access: any = { requireMember: jest.fn().mockResolvedValue({ role: 'OWNER' }) };
  const audit: any = { log: jest.fn().mockResolvedValue({}) };
  const storage: any = { putUrl: jest.fn().mockResolvedValue('https://storage/upload'), exists: jest.fn().mockResolvedValue(undefined), get: jest.fn().mockResolvedValue(invoiceBytes), remove: jest.fn().mockResolvedValue(undefined) };
  const extraction: any = { isConfigured: jest.fn().mockReturnValue(false), process: jest.fn() };
  return { prisma, access, audit, storage, extraction, service: new InvoicesService(prisma, access, audit, storage, extraction) };
}

describe('InvoicesService', () => {
  const reviewable = { ...invoice, vendorId: 'vendor-a', invoiceNumber: 'INV-101', invoiceDate: new Date('2026-10-14'),
    currency: 'USD', subtotal: new Prisma.Decimal(100), tax: new Prisma.Decimal(0), otherFees: new Prisma.Decimal(0),
    discount: new Prisma.Decimal(0), total: new Prisma.Decimal(100), updatedAt: new Date('2026-10-15'), duplicateResolution: 'UNRESOLVED' };
  const rescanned = { ...reviewable, id: 'invoice-b', attachmentHash: 'different-bytes', reviewStatus: 'REVIEWED', reviewedIdentityKey: 'historical-key' };

  it('reports rescanned candidates only within the authorized tenant and location', async () => {
    const { service, prisma } = setup();
    prisma.invoice.findUnique.mockResolvedValue(reviewable);
    prisma.invoice.findMany.mockResolvedValue([rescanned]);
    const result = await service.duplicateCandidates('user-a', reviewable.id);
    expect(result.candidates).toEqual([expect.objectContaining({ id: rescanned.id, kind: 'POSSIBLE' })]);
    expect(prisma.invoice.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ organizationId: 'org-a', restaurantLocationId: 'loc-a' }) }));
  });

  it('blocks a rescanned purchase until an owner or admin confirms distinctness', async () => {
    const { service, prisma } = setup();
    prisma.invoice.findUnique.mockResolvedValue(reviewable);
    prisma.invoice.findMany.mockResolvedValue([rescanned]);
    prisma.vendor.findFirst.mockResolvedValue({ id: 'vendor-a', organizationId: 'org-a' });
    await expect(service.review('user-a', reviewable.id, { markReviewed: true })).rejects.toThrow('Possible duplicate');
    expect(prisma.invoice.update).not.toHaveBeenCalled();
  });

  it('records and rechecks a distinct decision before claiming a separate reviewed identity', async () => {
    const { service, prisma, access, audit } = setup();
    prisma.invoice.findUnique.mockResolvedValue(reviewable);
    prisma.invoice.findMany.mockResolvedValue([rescanned]);
    prisma.vendor.findFirst.mockResolvedValue({ id: 'vendor-a', organizationId: 'org-a' });
    const fingerprint = invoiceIdentity(reviewable)!.fingerprint;
    await service.resolveDuplicate('user-a', reviewable.id, { candidateInvoiceId: rescanned.id,
      resolution: 'CONFIRMED_DISTINCT' as any, reason: 'Two original deliveries and signed receipts', expectedFingerprint: fingerprint });
    expect(access.requireMember).toHaveBeenCalledWith('user-a', 'org-a', ['OWNER', 'ADMIN']);
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'invoice.duplicate_confirmed_distinct' }));
    prisma.invoice.findUnique.mockResolvedValue({ ...reviewable, duplicateResolution: 'CONFIRMED_DISTINCT',
      duplicateOfInvoiceId: rescanned.id, duplicateDecisionFingerprint: fingerprint });
    await service.review('user-a', reviewable.id, { markReviewed: true });
    expect(prisma.invoice.update.mock.calls.at(-1)[0].data.reviewedIdentityKey).not.toBe(invoiceIdentity(reviewable)!.claimKey);
    expect(prisma.invoice.update.mock.calls.at(-1)[0].data.reviewStatus).toBe('REVIEWED');
  });

  it('rejects unauthorized or stale duplicate decisions', async () => {
    const { service, prisma, access } = setup();
    prisma.invoice.findUnique.mockResolvedValue(reviewable);
    access.requireMember.mockRejectedValueOnce(new ForbiddenException());
    await expect(service.resolveDuplicate('viewer', reviewable.id, { candidateInvoiceId: rescanned.id,
      resolution: 'CONFIRMED_DISTINCT' as any, reason: 'Separate signed deliveries', expectedFingerprint: invoiceIdentity(reviewable)!.fingerprint })).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.resolveDuplicate('user-a', reviewable.id, { candidateInvoiceId: rescanned.id,
      resolution: 'CONFIRMED_DISTINCT' as any, reason: 'Separate signed deliveries', expectedFingerprint: 'stale' })).rejects.toThrow('details changed');
  });

  it('translates a concurrent unique-claim race into a duplicate conflict', async () => {
    const { service, prisma } = setup();
    prisma.invoice.findUnique.mockResolvedValue(reviewable);
    prisma.invoice.findMany.mockResolvedValue([]);
    prisma.vendor.findFirst.mockResolvedValue({ id: 'vendor-a', organizationId: 'org-a' });
    prisma.invoice.update.mockRejectedValue(new Prisma.PrismaClientKnownRequestError('Unique reviewed identity', { code: 'P2002', clientVersion: '6.19.3' }));
    await expect(service.review('user-a', reviewable.id, { markReviewed: true })).rejects.toThrow('claimed this purchase identity');
  });

  it('allows only one of two concurrent review attempts to claim the same purchase', async () => {
    const { service, prisma } = setup();
    prisma.invoice.findUnique.mockImplementation(({ where }: any) => Promise.resolve({ ...reviewable, id: where.id, attachmentHash: where.id }));
    prisma.invoice.findMany.mockResolvedValue([]);
    prisma.vendor.findFirst.mockResolvedValue({ id: 'vendor-a', organizationId: 'org-a' });
    const claims = new Set<string>();
    prisma.invoice.update.mockImplementation(({ where, data }: any) => {
      if (claims.has(data.reviewedIdentityKey)) throw new Prisma.PrismaClientKnownRequestError('Unique reviewed identity', { code: 'P2002', clientVersion: '6.19.3' });
      claims.add(data.reviewedIdentityKey);
      return Promise.resolve({ ...reviewable, id: where.id, ...data });
    });
    const outcomes = await Promise.allSettled([
      service.review('user-a', 'invoice-a', { markReviewed: true }),
      service.review('user-a', 'invoice-b', { markReviewed: true }),
    ]);
    expect(outcomes.map((outcome) => outcome.status).sort()).toEqual(['fulfilled', 'rejected']);
    expect(claims.size).toBe(1);
  });

  it('prevents invoices marked duplicate from becoming trusted', async () => {
    const { service, prisma } = setup();
    prisma.invoice.findUnique.mockResolvedValue({ ...reviewable, duplicateResolution: 'DUPLICATE' });
    prisma.vendor.findFirst.mockResolvedValue({ id: 'vendor-a', organizationId: 'org-a' });
    await expect(service.review('user-a', reviewable.id, { markReviewed: true })).rejects.toThrow('marked as a duplicate');
  });

  it('invalidates a distinct decision when an invoice identifier changes and locks reviewed identifiers', async () => {
    const { service, prisma } = setup();
    prisma.invoice.findUnique.mockResolvedValue({ ...reviewable, duplicateResolution: 'CONFIRMED_DISTINCT',
      duplicateOfInvoiceId: rescanned.id, duplicateDecisionFingerprint: invoiceIdentity(reviewable)!.fingerprint });
    await service.update('user-a', reviewable.id, { invoiceNumber: 'DIFFERENT' });
    expect(prisma.invoice.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({
      duplicateResolution: 'UNRESOLVED', duplicateOfInvoiceId: null, duplicateDecisionFingerprint: null,
    }) }));
    prisma.invoice.findUnique.mockResolvedValue({ ...reviewable, reviewStatus: 'REVIEWED' });
    await expect(service.update('user-a', reviewable.id, { invoiceNumber: 'CHANGED' })).rejects.toThrow('Reviewed invoices cannot be edited');
  });

  it('requires management roles for every invoice write path', async () => {
    const { service, access, prisma } = setup();
    access.requireMember.mockRejectedValue(new ForbiddenException());
    await expect(service.uploadIntent('viewer', { restaurantLocationId: 'loc-a', fileName: 'x.pdf', mimeType: 'application/pdf', fileSize: 10 })).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.complete('viewer', 'invoice-a', {} as any)).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.update('viewer', 'invoice-a', {})).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.startExtraction('viewer', 'invoice-a')).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.updateLineItem('viewer', 'invoice-a', 'line-a', {})).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.review('viewer', 'invoice-a', { markReviewed: true })).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.delete('viewer', 'invoice-a')).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.invoice.create).not.toHaveBeenCalled();
    expect(prisma.invoice.delete).not.toHaveBeenCalled();
    expect(access.requireMember).toHaveBeenCalledWith('viewer', 'org-a', ['OWNER', 'ADMIN', 'MANAGER']);
  });

  it('rejects a material subtotal mismatch before any invoice write', async () => {
    const { service, prisma } = setup();
    prisma.invoiceLineItem.findMany.mockResolvedValue([{ id: 'line-a', rawDescription: 'Rice', quantity: null, unitPrice: null, extendedPrice: new (require('@prisma/client').Prisma.Decimal)('90'), fieldProvenance: {} }]);
    await expect(service.review('user-a', 'invoice-a', { markReviewed: true, vendorName: 'Vendor', invoiceDate: '2026-10-01', subtotal: 100, total: 100 } as any)).rejects.toThrow('line items sum to 90.00');
    expect(prisma.invoice.update).not.toHaveBeenCalled();
  });

  it('rejects a material total mismatch and preserves reviewed headers', async () => {
    const { service, prisma } = setup();
    await expect(service.review('user-a', 'invoice-a', { markReviewed: true, vendorName: 'Vendor', invoiceDate: '2026-10-01', subtotal: 100, tax: 10, otherFees: 0, discount: 0, total: 100 } as any)).rejects.toThrow('known charges reconcile');
    prisma.invoice.findUnique.mockResolvedValue({ ...invoice, reviewStatus: 'REVIEWED' });
    await expect(service.update('user-a', 'invoice-a', { total: 1 })).rejects.toThrow('Reviewed invoices cannot be edited');
    expect(prisma.invoice.update).not.toHaveBeenCalled();
  });

  it('creates a tenant-scoped upload intent and audits it', async () => {
    const { service, prisma, storage, audit } = setup();
    const result = await service.uploadIntent('user-a', { restaurantLocationId: 'loc-a', fileName: 'invoice.pdf', mimeType: 'application/pdf', fileSize: 100 });
    expect(result.uploadUrl).toBe('https://storage/upload');
    expect(prisma.invoice.create).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ organizationId: 'org-a', restaurantLocationId: 'loc-a', createdByUserId: 'user-a' }) }));
    expect(storage.putUrl).toHaveBeenCalledWith(expect.stringContaining('/invoices/invoice-a/invoice.pdf'), 'application/pdf');
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'invoice.created' }));
  });

  it('rejects unauthorized locations', async () => {
    const { service, access } = setup();
    access.requireMember.mockRejectedValue(new ForbiddenException());
    await expect(service.uploadIntent('user-b', { restaurantLocationId: 'loc-a', fileName: 'x.pdf', mimeType: 'application/pdf', fileSize: 10 })).rejects.toBeInstanceOf(ForbiddenException);
  });

  it.each(['text/plain', 'image/gif'])('rejects unsupported MIME %s', async (mimeType) => {
    const { service } = setup();
    await expect(service.uploadIntent('user-a', { restaurantLocationId: 'loc-a', fileName: 'x', mimeType, fileSize: 10 })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects oversized files', async () => {
    const { service } = setup();
    await expect(service.uploadIntent('user-a', { restaurantLocationId: 'loc-a', fileName: 'x.pdf', mimeType: 'application/pdf', fileSize: 15 * 1024 * 1024 + 1 })).rejects.toThrow('15 MB');
  });

  it('keeps invoice lists isolated to the authorized location', async () => {
    const { service, prisma, access } = setup();
    const result = await service.list('user-a', { restaurantLocationId: 'loc-a' });
    expect(access.requireMember).toHaveBeenCalledWith('user-a', 'org-a');
    expect(prisma.invoice.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ organizationId: 'org-a', restaurantLocationId: 'loc-a' }) }));
    expect(result[0].paymentStatus).toBe('AWAITING_PAYMENT');
  });

  it('filters invoice lists by invoice date and falls back to creation date when absent', async () => {
    const { service, prisma } = setup();
    await service.list('user-a', {
      restaurantLocationId: 'loc-a',
      startDate: '2026-10-01T04:00:00.000Z',
      endDate: '2026-10-10T03:59:59.999Z',
    });
    expect(prisma.invoice.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          OR: [
            {
              invoiceDate: {
                gte: new Date('2026-10-01T04:00:00.000Z'),
                lte: new Date('2026-10-10T03:59:59.999Z'),
              },
            },
            {
              invoiceDate: null,
              createdAt: {
                gte: new Date('2026-10-01T04:00:00.000Z'),
                lte: new Date('2026-10-10T03:59:59.999Z'),
              },
            },
          ],
        }),
      }),
    );
  });

  it('rejects a vendor from another organization', async () => {
    const { service } = setup();
    await expect(service.uploadIntent('user-a', { restaurantLocationId: 'loc-a', vendorId: 'vendor-b', fileName: 'x.pdf', mimeType: 'application/pdf', fileSize: 10 })).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('reuses an existing location-scoped duplicate without starting extraction again', async () => {
    const { service, prisma, storage, extraction, audit } = setup();
    const existing = { ...invoice, id: 'existing-invoice', attachmentHash: 'existing-hash' };
    prisma.invoice.findFirst.mockResolvedValue(existing);
    const result = await service.complete('user-a', 'invoice-a', { etag: 'uploaded' });
    expect(result.id).toBe('existing-invoice');
    expect(storage.remove).toHaveBeenCalledWith(invoice.storageKey);
    expect(prisma.invoice.delete).toHaveBeenCalledWith({ where: { id: 'invoice-a' } });
    expect(extraction.process).not.toHaveBeenCalled();
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'invoice.duplicate_skipped', entityId: 'existing-invoice' }));
  });

  it('handles a concurrent identical-file unique conflict without a second trusted upload', async () => {
    const { service, prisma, storage } = setup();
    const existing = { ...invoice, id: 'concurrent-invoice' };
    prisma.invoice.findFirst.mockResolvedValue(null);
    prisma.invoice.update.mockRejectedValue(new Prisma.PrismaClientKnownRequestError('Unique attachment', { code: 'P2002', clientVersion: '6.19.3' }));
    prisma.invoice.findUnique.mockImplementation(({ where }: any) => Promise.resolve(where.id ? invoice : existing));
    const result = await service.complete('user-a', invoice.id, { etag: 'uploaded' });
    expect(result.id).toBe(existing.id);
    expect(storage.remove).toHaveBeenCalledWith(invoice.storageKey);
    expect(prisma.invoice.delete).toHaveBeenCalledWith({ where: { id: invoice.id } });
  });

  it('marks completion failed when the storage object is missing', async () => {
    const { service, prisma, storage, audit } = setup();
    storage.get.mockRejectedValue(new Error('NoSuchKey'));
    await expect(service.complete('user-a', 'invoice-a', { etag: 'uploaded' })).rejects.toThrow('uploaded invoice file is unavailable');
    expect(prisma.invoice.updateMany).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ status: 'FAILED', extractionStatus: 'FAILED' }) }));
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'invoice.upload_completion_failed', metadata: expect.objectContaining({ errorCode: 'STORAGE_OBJECT_UNAVAILABLE' }) }));
  });

  it('rejects a browser upload whose bytes do not match its declared MIME type', async () => {
    const { service, prisma, storage, audit } = setup();
    storage.get.mockResolvedValue(Buffer.alloc(invoiceBytes.length, 0));
    await expect(service.complete('user-a', 'invoice-a', { etag: 'uploaded' })).rejects.toThrow('does not match');
    expect(storage.remove).toHaveBeenCalledWith(invoice.storageKey);
    expect(prisma.invoice.updateMany).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ status: 'FAILED' }) }));
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ metadata: expect.objectContaining({ errorCode: 'FILE_SIGNATURE_MISMATCH' }) }));
  });

  it('rejects a browser upload whose stored size differs from the intent', async () => {
    const { service, storage, audit } = setup();
    storage.get.mockResolvedValue(Buffer.from('%PDF-short'));
    await expect(service.complete('user-a', 'invoice-a', { etag: 'uploaded' })).rejects.toThrow('does not match');
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ metadata: expect.objectContaining({ errorCode: 'FILE_SIZE_MISMATCH' }) }));
  });

  it('claims extraction once when concurrent requests arrive', async () => {
    jest.useFakeTimers();
    const { service, prisma, extraction } = setup();
    extraction.isConfigured.mockReturnValue(true);
    const processing = { ...invoice, extractionStatus: 'PROCESSING', extractionStartedAt: new Date(), extractionAttemptCount: 1 };
    prisma.invoice.findUnique.mockResolvedValueOnce(invoice).mockResolvedValue(processing);
    prisma.invoice.updateMany.mockResolvedValueOnce({ count: 1 }).mockResolvedValueOnce({ count: 0 });
    await service.startExtraction('user-a', 'invoice-a');
    await service.startExtraction('user-a', 'invoice-a');
    jest.runAllTimers();
    expect(extraction.process).toHaveBeenCalledTimes(1);
    jest.useRealTimers();
  });

  it('enforces the extraction retry limit', async () => {
    const { service, prisma, extraction } = setup();
    extraction.isConfigured.mockReturnValue(true);
    prisma.invoice.findUnique.mockResolvedValue({ ...invoice, extractionStatus: 'FAILED', extractionAttemptCount: 3 });
    prisma.invoice.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.startExtraction('user-a', 'invoice-a')).rejects.toThrow('retry limit reached');
    expect(extraction.process).not.toHaveBeenCalled();
  });

  it('validates non-negative metadata amounts', async () => {
    const { service } = setup();
    await expect(service.update('user-a', 'invoice-a', { total: '-1' })).rejects.toThrow('Total cannot be negative');
  });

  it('preserves omitted financial fields during a partial metadata update', async () => {
    const { service, prisma } = setup();
    await service.update('user-a', 'invoice-a', { status: 'COMPLETED' as any });
    expect(prisma.invoice.update).toHaveBeenCalledWith({
      where: { id: 'invoice-a', reviewStatus: { not: 'REVIEWED' } },
      data: expect.objectContaining({ subtotal: undefined, tax: undefined, total: undefined, status: 'COMPLETED' }),
    });
  });

  it('sets the terminal invoice status when approval marks an invoice reviewed', async () => {
    const { service, prisma } = setup();
    prisma.invoice.update.mockResolvedValue({ ...invoice, status: 'COMPLETED', reviewStatus: 'REVIEWED' });
    await service.review('user-a', 'invoice-a', { markReviewed: true, vendorName: 'Vendor', invoiceDate: '2026-10-01', total: 100 } as any);
    expect(prisma.invoice.update).toHaveBeenLastCalledWith({
      where: { id: 'invoice-a', reviewStatus: { not: 'REVIEWED' } },
      data: expect.objectContaining({ status: 'COMPLETED', reviewStatus: 'REVIEWED' }),
    });
  });

  it('marks preserved line evidence verified when the owner reviews the invoice', async () => {
    const { service, prisma } = setup();
    prisma.invoiceLineItem.findMany.mockResolvedValue([{ id: 'line-a', rawDescription: 'Chicken', fieldProvenance: { quantity: { kind: 'OBSERVED', verified: false }, unitPrice: { kind: 'MISSING', verified: false } } }]);
    prisma.invoice.update.mockResolvedValueOnce({ ...invoice, extractedVendorName: 'Vendor', invoiceDate: new Date('2026-10-01'), total: '100' });
    await service.review('user-a', 'invoice-a', { markReviewed: true, vendorName: 'Vendor', invoiceDate: '2026-10-01', subtotal: 100, total: 100 } as any);
    expect(prisma.invoiceLineItem.update).toHaveBeenCalledWith(expect.objectContaining({
      where: { id: 'line-a' },
      data: { fieldProvenance: expect.objectContaining({
        quantity: expect.objectContaining({ kind: 'OBSERVED', verified: true }),
        unitPrice: expect.objectContaining({ kind: 'MISSING', verified: true }),
      }) },
    }));
  });

  it('records human corrections as verified provenance', async () => {
    const { service, prisma } = setup();
    prisma.invoice.findUnique.mockResolvedValue({
      ...invoice,
      fieldProvenance: {
        total: { kind: 'CALCULATED', calculatedValue: '100.00', verified: false },
      },
    });
    await service.review('user-a', 'invoice-a', {
      invoiceNumber: 'INV-42',
      total: '100.25',
      currency: 'usd',
    });
    expect(prisma.invoice.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          total: expect.anything(),
          currency: 'USD',
          fieldProvenance: expect.objectContaining({
            invoiceNumber: expect.objectContaining({ kind: 'OBSERVED', verified: true }),
            total: expect.objectContaining({ kind: 'OBSERVED', verified: true }),
            currency: expect.objectContaining({ kind: 'OBSERVED', verified: true }),
          }),
        }),
      }),
    );
  });

  it('authorizes deletion, removes the row and storage object, and audits it', async () => {
    const { service, prisma, access, storage, audit } = setup();
    await service.delete('user-a', 'invoice-a');
    expect(access.requireMember).toHaveBeenCalledWith('user-a', 'org-a', ['OWNER', 'ADMIN', 'MANAGER']);
    expect(prisma.invoice.delete).toHaveBeenCalledWith({ where: { id: 'invoice-a' } });
    expect(storage.remove).toHaveBeenCalledWith('org/file.pdf');
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'invoice.deleted' }));
  });

  it('preserves an invoice with an active bank payment link until the link is removed', async () => {
    const { service, prisma, storage } = setup();
    prisma.bankTransaction.findFirst.mockResolvedValue({ id: 'bank-payment' });

    await expect(service.delete('user-a', 'invoice-a')).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.invoice.delete).not.toHaveBeenCalled();
    expect(storage.remove).not.toHaveBeenCalled();
  });
});
