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
  it('returns authoritative revenue summary, trend, sorting, and pagination', async () => {
    const dayOne = new Date('2026-10-01T12:00:00.000Z');
    const dayTwo = new Date('2026-10-02T12:00:00.000Z');
    const normalizedDayOne = new Date('2026-10-01T00:00:00.000Z');
    const normalizedDayTwo = new Date('2026-10-02T00:00:00.000Z');
    const items = [{ id: 'revenue-2', amount: new Prisma.Decimal(500), date: dayTwo }];
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) },
      revenueEntry: {
        findMany: jest.fn().mockResolvedValue(items),
        count: jest.fn().mockResolvedValue(3),
        aggregate: jest.fn().mockResolvedValueOnce({ _sum: { amount: new Prisma.Decimal(900) } }).mockResolvedValueOnce({ _sum: { amount: new Prisma.Decimal(600) } }),
        groupBy: jest.fn().mockResolvedValue([
          { date: dayOne, _sum: { amount: new Prisma.Decimal(300) } },
          { date: new Date('2026-10-01T18:00:00.000Z'), _sum: { amount: new Prisma.Decimal(100) } },
          { date: dayTwo, _sum: { amount: new Prisma.Decimal(500) } },
        ]),
      },
    };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    const result = await new FinanceService(prisma, access, audit).revenues('user-a', { restaurantLocationId: 'loc-a', startDate: '2026-10-01', endDate: '2026-10-02', page: 2, limit: 2, sort: 'highestRevenue' });
    expect(result.pagination).toEqual({ page: 2, limit: 2, totalItems: 3, totalPages: 2, hasMore: false });
    expect(result.summary).toEqual({ totalRevenue: 900, previousTotalRevenue: 600, averageDailyRevenue: 450, highestDay: { date: normalizedDayTwo, amount: 500 }, lowestDay: { date: normalizedDayOne, amount: 400 }, dailyTrend: [{ date: normalizedDayOne, amount: 400 }, { date: normalizedDayTwo, amount: 500 }] });
    expect(prisma.revenueEntry.findMany).toHaveBeenCalledWith(expect.objectContaining({ skip: 2, take: 2, orderBy: [{ amount: 'desc' }, { date: 'desc' }, { id: 'asc' }], where: expect.objectContaining({ organizationId: 'org-a', restaurantLocationId: 'loc-a' }) }));
  });
  it('does not query revenue when location membership is denied', async () => {
    const prisma: any = { restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-b', organizationId: 'org-b' }) }, revenueEntry: { findMany: jest.fn(), count: jest.fn(), aggregate: jest.fn(), groupBy: jest.fn() } };
    const access = { requireMember: jest.fn().mockRejectedValue(new ForbiddenException()) } as any;
    await expect(new FinanceService(prisma, access, audit).revenues('user-a', { restaurantLocationId: 'loc-b' })).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.revenueEntry.findMany).not.toHaveBeenCalled();
  });
});
