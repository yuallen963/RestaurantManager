import { ForbiddenException } from '@nestjs/common';
import { FinanceService } from '../src/finance/finance.service';

describe('FinanceService tenant enforcement', () => {
  const audit = { log: jest.fn() } as any;
  it('denies a revenue record belonging to another organization', async () => {
    const prisma: any = { revenueEntry: { findUnique: jest.fn().mockResolvedValue({ id: 'revenue-b', organizationId: 'org-b' }) } };
    const access = { requireMember: jest.fn().mockRejectedValue(new ForbiddenException()) } as any;
    await expect(new FinanceService(prisma, access, audit).revenueDetail('user-a', 'revenue-b')).rejects.toBeInstanceOf(ForbiddenException);
  });
  it('normalizes vendor names before persistence', async () => {
    const prisma: any = { vendor: { create: jest.fn().mockResolvedValue({ id: 'vendor-1' }) } };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    await new FinanceService(prisma, access, audit).vendor('user-a', { organizationId: 'org-a', name: '  Sysco   Foods ' });
    expect(prisma.vendor.create).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ name: 'Sysco   Foods', normalizedName: 'sysco foods' }) }));
  });
  it('rejects a non-positive monetary amount', async () => {
    const prisma: any = { restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) }, revenueEntry: { create: jest.fn() } };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    await expect(new FinanceService(prisma, access, audit).revenue('user-a', { restaurantLocationId: 'loc-a', amount: 0, date: '2026-10-01' })).rejects.toThrow('Amount must be positive');
  });
});
