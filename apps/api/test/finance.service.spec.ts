import { ForbiddenException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
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
  it('returns filtered totals, sorting, and pagination metadata', async () => {
    const items = [{ id: 'expense-1', amount: new Prisma.Decimal(250) }];
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) },
      vendor: { findMany: jest.fn().mockResolvedValue([]) },
      expense: {
        findMany: jest.fn().mockResolvedValue(items),
        count: jest.fn().mockResolvedValue(3),
        aggregate: jest.fn().mockResolvedValue({ _sum: { amount: new Prisma.Decimal(625.5) } }),
      },
    };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    const result = await new FinanceService(prisma, access, audit).expenses('user-a', {
      restaurantLocationId: 'loc-a', page: 2, limit: 2, categoryId: 'category-a',
      startDate: '2026-10-01', endDate: '2026-10-08', sort: 'highestAmount',
    });
    expect(result).toEqual({
      items,
      pagination: { page: 2, limit: 2, totalItems: 3, totalPages: 2, hasMore: false },
      summary: { totalAmount: 625.5 },
    });
    expect(prisma.expense.findMany).toHaveBeenCalledWith(expect.objectContaining({
      skip: 2, take: 2,
      orderBy: [{ amount: 'desc' }, { date: 'desc' }, { id: 'asc' }],
      where: expect.objectContaining({ organizationId: 'org-a', restaurantLocationId: 'loc-a', expenseCategoryId: 'category-a' }),
    }));
    expect(prisma.expense.aggregate).toHaveBeenCalledWith({
      where: expect.objectContaining({ organizationId: 'org-a', restaurantLocationId: 'loc-a' }),
      _sum: { amount: true },
    });
  });
  it('searches descriptions and organization-scoped vendor names', async () => {
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) },
      vendor: { findMany: jest.fn().mockResolvedValue([{ id: 'vendor-a' }]) },
      expense: {
        findMany: jest.fn().mockResolvedValue([]),
        count: jest.fn().mockResolvedValue(0),
        aggregate: jest.fn().mockResolvedValue({ _sum: { amount: null } }),
      },
    };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    await new FinanceService(prisma, access, audit).expenses('user-a', {
      restaurantLocationId: 'loc-a', search: 'sysco',
    });
    expect(prisma.vendor.findMany).toHaveBeenCalledWith({
      where: { organizationId: 'org-a', name: { contains: 'sysco', mode: 'insensitive' } },
      select: { id: true },
    });
    expect(prisma.expense.findMany.mock.calls[0][0].where.OR).toEqual([
      { description: { contains: 'sysco', mode: 'insensitive' } },
      { vendorId: { in: ['vendor-a'] } },
    ]);
  });
  it('does not query expenses when location membership is denied', async () => {
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-b', organizationId: 'org-b' }) },
      expense: { findMany: jest.fn(), count: jest.fn(), aggregate: jest.fn() },
    };
    const access = { requireMember: jest.fn().mockRejectedValue(new ForbiddenException()) } as any;
    await expect(new FinanceService(prisma, access, audit).expenses('user-a', { restaurantLocationId: 'loc-b' })).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.expense.findMany).not.toHaveBeenCalled();
  });
});
