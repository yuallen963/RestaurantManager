import { ExtractionStatus, InvoiceStatus, ReviewStatus } from '@prisma/client';
import { InvoiceRecoveryService } from '../src/invoices/invoice-recovery.service';

describe('InvoiceRecoveryService', () => {
  const now = new Date('2026-10-11T16:00:00.000Z');

  function setup() {
    const prisma: any = {
      invoice: {
        findMany: jest.fn().mockResolvedValueOnce([]).mockResolvedValueOnce([]),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const extraction: any = { isConfigured: jest.fn().mockReturnValue(true), process: jest.fn().mockResolvedValue(undefined) };
    const audit: any = { log: jest.fn().mockResolvedValue(undefined) };
    return { prisma, extraction, audit, service: new InvoiceRecoveryService(prisma, extraction, audit) };
  }

  it('marks abandoned upload intents failed without deleting their records', async () => {
    const { prisma, service, audit } = setup();
    prisma.invoice.findMany.mockReset().mockResolvedValueOnce([{ id: 'upload-a', organizationId: 'org-a', createdByUserId: 'user-a' }]).mockResolvedValueOnce([]);
    await service.recover(now);
    expect(prisma.invoice.updateMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ id: 'upload-a', status: InvoiceStatus.PROCESSING, attachmentHash: null }),
      data: expect.objectContaining({ status: InvoiceStatus.FAILED, extractionStatus: ExtractionStatus.FAILED }),
    }));
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'invoice.upload_abandoned', metadata: expect.objectContaining({ errorCode: 'UPLOAD_EXPIRED' }) }));
  });

  it('atomically claims and restarts stale extraction after a backend interruption', async () => {
    jest.useFakeTimers();
    const { prisma, service, extraction, audit } = setup();
    prisma.invoice.findMany.mockReset().mockResolvedValueOnce([]).mockResolvedValueOnce([{ id: 'invoice-a', organizationId: 'org-a', createdByUserId: 'user-a', extractionAttemptCount: 1 }]);
    await service.recover(now);
    jest.runAllTimers();
    expect(prisma.invoice.updateMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ id: 'invoice-a', extractionStatus: ExtractionStatus.PROCESSING, reviewStatus: { not: ReviewStatus.REVIEWED } }),
      data: expect.objectContaining({ extractionAttemptCount: { increment: 1 } }),
    }));
    expect(extraction.process).toHaveBeenCalledWith('invoice-a', 'user-a');
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'invoice.extraction_recovered', metadata: expect.objectContaining({ attempt: 2 }) }));
    jest.useRealTimers();
  });

  it('does not launch work when another process wins the recovery claim', async () => {
    jest.useFakeTimers();
    const { prisma, service, extraction } = setup();
    prisma.invoice.findMany.mockReset().mockResolvedValueOnce([]).mockResolvedValueOnce([{ id: 'invoice-a', organizationId: 'org-a', createdByUserId: 'user-a', extractionAttemptCount: 1 }]);
    prisma.invoice.updateMany.mockResolvedValueOnce({ count: 0 }).mockResolvedValueOnce({ count: 0 });
    await service.recover(now);
    jest.runAllTimers();
    expect(extraction.process).not.toHaveBeenCalled();
    jest.useRealTimers();
  });

  it('fails stale processing after the bounded retry limit', async () => {
    const { prisma, service } = setup();
    await service.recover(now);
    expect(prisma.invoice.updateMany).toHaveBeenLastCalledWith(expect.objectContaining({
      where: expect.objectContaining({ extractionAttemptCount: { gte: 3 } }),
      data: expect.objectContaining({ status: InvoiceStatus.FAILED, extractionStatus: ExtractionStatus.FAILED }),
    }));
  });
});
