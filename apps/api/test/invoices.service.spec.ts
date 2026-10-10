import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { InvoicesService } from '../src/invoices/invoices.service';

const location = { id: 'loc-a', organizationId: 'org-a' };
const invoice = { id: 'invoice-a', organizationId: 'org-a', restaurantLocationId: 'loc-a', vendorId: null, storageKey: 'org/file.pdf' };

function setup() {
  const prisma: any = {
    restaurantLocation: { findUnique: jest.fn().mockResolvedValue(location) },
    invoice: {
      create: jest.fn().mockResolvedValue({ ...invoice, storageKey: 'pending' }),
      update: jest.fn().mockImplementation(({ data }: any) => Promise.resolve({ ...invoice, ...data })),
      findUnique: jest.fn().mockResolvedValue(invoice),
      findFirst: jest.fn().mockResolvedValue(null),
      findMany: jest.fn().mockResolvedValue([invoice]),
      delete: jest.fn().mockResolvedValue(invoice),
    },
    vendor: { findFirst: jest.fn().mockResolvedValue(null), findMany: jest.fn().mockResolvedValue([]) },
  };
  const access: any = { requireMember: jest.fn().mockResolvedValue({ role: 'OWNER' }) };
  const audit: any = { log: jest.fn().mockResolvedValue({}) };
  const storage: any = { putUrl: jest.fn().mockResolvedValue('https://storage/upload'), exists: jest.fn().mockResolvedValue(undefined), get: jest.fn().mockResolvedValue(Buffer.from('invoice bytes')), remove: jest.fn().mockResolvedValue(undefined) };
  const extraction: any = { isConfigured: jest.fn().mockReturnValue(false), process: jest.fn() };
  return { prisma, access, audit, storage, extraction, service: new InvoicesService(prisma, access, audit, storage, extraction) };
}

describe('InvoicesService', () => {
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
    await service.list('user-a', { restaurantLocationId: 'loc-a' });
    expect(access.requireMember).toHaveBeenCalledWith('user-a', 'org-a');
    expect(prisma.invoice.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ organizationId: 'org-a', restaurantLocationId: 'loc-a' }) }));
  });

  it('preserves explicit UTC invoice-list boundaries without rounding them', async () => {
    const { service, prisma } = setup();
    await service.list('user-a', {
      restaurantLocationId: 'loc-a',
      startDate: '2026-10-01T04:00:00.000Z',
      endDate: '2026-10-10T03:59:59.999Z',
    });
    expect(prisma.invoice.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          createdAt: {
            gte: new Date('2026-10-01T04:00:00.000Z'),
            lte: new Date('2026-10-10T03:59:59.999Z'),
          },
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

  it('validates non-negative metadata amounts', async () => {
    const { service } = setup();
    await expect(service.update('user-a', 'invoice-a', { total: '-1' })).rejects.toThrow('Total cannot be negative');
  });

  it('authorizes deletion, removes the row and storage object, and audits it', async () => {
    const { service, prisma, access, storage, audit } = setup();
    await service.delete('user-a', 'invoice-a');
    expect(access.requireMember).toHaveBeenCalledWith('user-a', 'org-a');
    expect(prisma.invoice.delete).toHaveBeenCalledWith({ where: { id: 'invoice-a' } });
    expect(storage.remove).toHaveBeenCalledWith('org/file.pdf');
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'invoice.deleted' }));
  });
});
