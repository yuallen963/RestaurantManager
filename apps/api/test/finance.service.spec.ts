import { ConflictException, ForbiddenException } from '@nestjs/common';
import { OrganizationRole, Prisma } from '@prisma/client';
import { FinanceService } from '../src/finance/finance.service';

describe('FinanceService tenant enforcement', () => {
  const audit = { log: jest.fn() } as any;
  it('requires a financial manager role before creating an expense', async () => {
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) },
      expenseCategory: { findFirst: jest.fn().mockResolvedValue({ id: 'category-a' }) },
      expense: { create: jest.fn().mockResolvedValue({ id: 'expense-a' }) },
    };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    await new FinanceService(prisma, access, audit).expense('user-a', {
      restaurantLocationId: 'loc-a', expenseCategoryId: 'category-a',
      amount: 10, date: '2026-10-01', description: 'Supplies',
    });
    expect(access.requireMember).toHaveBeenCalledWith('user-a', 'org-a', [
      OrganizationRole.OWNER,
      OrganizationRole.ADMIN,
      OrganizationRole.MANAGER,
    ]);
  });
  it('rejects a viewer before mutating financial records', async () => {
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) },
      expense: { create: jest.fn() },
    };
    const access = { requireMember: jest.fn((_userId, _organizationId, roles) => {
      if (roles) throw new ForbiddenException();
    }) } as any;
    await expect(new FinanceService(prisma, access, audit).expense('viewer', {
      restaurantLocationId: 'loc-a', expenseCategoryId: 'category-a',
      amount: 10, date: '2026-10-01', description: 'Supplies',
    })).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.expense.create).not.toHaveBeenCalled();
  });
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
  it('prevents a manual total from double-counting a Square business day', async () => {
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) },
      revenueEntry: { findFirst: jest.fn().mockResolvedValue({ id: 'square-day', source: 'POS_IMPORT' }), create: jest.fn() },
    };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    await expect(new FinanceService(prisma, access, audit).revenue('user-a', { restaurantLocationId: 'loc-a', amount: 100, date: '2026-10-01' })).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.revenueEntry.create).not.toHaveBeenCalled();
  });
  it('creates typed manual revenue and preserves its audit snapshot', async () => {
    const created = {
      id: 'revenue-a', organizationId: 'org-a', restaurantLocationId: 'loc-a',
      amount: new Prisma.Decimal(125.25), date: new Date('2026-10-01T00:00:00.000Z'),
      source: 'MANUAL', manualType: 'CASH', additionalToPos: false, notes: 'Lunch',
    };
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) },
      revenueEntry: { findFirst: jest.fn().mockResolvedValue(null), create: jest.fn().mockResolvedValue(created) },
    };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    const result = await new FinanceService(prisma, access, audit).revenue('user-a', {
      restaurantLocationId: 'loc-a', amount: 125.25, date: '2026-10-01', manualType: 'CASH', notes: ' Lunch ',
    });
    expect(result).toBe(created);
    expect(prisma.revenueEntry.create).toHaveBeenCalledWith({ data: expect.objectContaining({
      organizationId: 'org-a', restaurantLocationId: 'loc-a', source: 'MANUAL', manualType: 'CASH', notes: 'Lunch',
    }) });
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({
      action: 'revenue.created', metadata: expect.objectContaining({ amount: '125.25', manualType: 'CASH' }),
    }));
  });
  it('requires editing instead of creating a same-day sales-type duplicate', async () => {
    const existing = { id: 'existing', source: 'MANUAL' };
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) },
      revenueEntry: {
        findFirst: jest.fn().mockResolvedValueOnce(null).mockResolvedValueOnce(existing),
        create: jest.fn(),
      },
    };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    const service = new FinanceService(prisma, access, audit);
    await expect(service.revenue('user-a', {
      restaurantLocationId: 'loc-a', amount: 100, date: '2026-10-01', manualType: 'CARD',
    })).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.revenueEntry.create).not.toHaveBeenCalled();

  });
  it('allows explicitly acknowledged off-POS sales without replacing Square', async () => {
    const square = { id: 'square-day', source: 'POS_IMPORT' };
    const created = {
      id: 'additional', amount: new Prisma.Decimal(25), date: new Date('2026-10-01'),
      source: 'MANUAL', manualType: 'CASH', additionalToPos: true, restaurantLocationId: 'loc-a',
    };
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) },
      revenueEntry: {
        findFirst: jest.fn().mockResolvedValueOnce(square).mockResolvedValueOnce(null),
        create: jest.fn().mockResolvedValue(created),
      },
    };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    await expect(new FinanceService(prisma, access, audit).revenue('user-a', {
      restaurantLocationId: 'loc-a', amount: 25, date: '2026-10-01', manualType: 'CASH', additionalToPos: true,
    })).resolves.toBe(created);
    expect(prisma.revenueEntry.create).toHaveBeenCalledWith({ data: expect.objectContaining({ additionalToPos: true }) });
  });
  it('maps a concurrent manual revenue uniqueness collision to a conflict', async () => {
    const collision = new Prisma.PrismaClientKnownRequestError('duplicate', { code: 'P2002', clientVersion: '6.19.3' });
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) },
      revenueEntry: { findFirst: jest.fn().mockResolvedValue(null), create: jest.fn().mockRejectedValue(collision) },
    };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    await expect(new FinanceService(prisma, access, audit).revenue('user-a', {
      restaurantLocationId: 'loc-a', amount: 100, date: '2026-10-01', manualType: 'CARD',
    })).rejects.toBeInstanceOf(ConflictException);
  });
  it('stores the selected restaurant business date without timezone shifting', async () => {
    const created = {
      id: 'revenue-date', amount: new Prisma.Decimal(10), date: new Date('2026-10-01T00:00:00.000Z'),
      source: 'MANUAL', manualType: 'OTHER', additionalToPos: false, restaurantLocationId: 'loc-a',
    };
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a', timezone: 'America/Los_Angeles' }) },
      revenueEntry: { findFirst: jest.fn().mockResolvedValue(null), create: jest.fn().mockResolvedValue(created) },
    };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    await new FinanceService(prisma, access, audit).revenue('user-a', {
      restaurantLocationId: 'loc-a', amount: 10, date: '2026-10-01T23:30:00-07:00', manualType: 'OTHER',
    });
    expect(prisma.revenueEntry.create.mock.calls[0][0].data.date).toEqual(new Date('2026-10-01T00:00:00.000Z'));
  });
  it('does not allow manual mutations of Square revenue', async () => {
    const square = { id: 'square', organizationId: 'org-a', source: 'POS_IMPORT' };
    const prisma: any = { revenueEntry: { findUnique: jest.fn().mockResolvedValue(square), update: jest.fn(), delete: jest.fn() } };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    const service = new FinanceService(prisma, access, audit);
    await expect(service.updateRevenue('user-a', 'square', { amount: 10 })).rejects.toThrow('Square revenue is managed by POS sync');
    await expect(service.deleteRevenue('user-a', 'square')).rejects.toThrow('Square revenue is managed by POS sync');
    expect(prisma.revenueEntry.update).not.toHaveBeenCalled();
    expect(prisma.revenueEntry.delete).not.toHaveBeenCalled();
  });
  it('requires a revenue-management role for manual writes', async () => {
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) },
      revenueEntry: { create: jest.fn() },
    };
    const access = {
      requireMember: jest.fn()
        .mockResolvedValueOnce({})
        .mockRejectedValueOnce(new ForbiddenException()),
    } as any;
    await expect(new FinanceService(prisma, access, audit).revenue('viewer', {
      restaurantLocationId: 'loc-a', amount: 100, date: '2026-10-01', manualType: 'OTHER',
    })).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.revenueEntry.create).not.toHaveBeenCalled();
    expect(access.requireMember.mock.calls[1][2]).toEqual(expect.arrayContaining(['OWNER', 'ADMIN', 'MANAGER']));
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
  it('rejects generic edits of a bank-linked expense', async () => {
    const expense = { id: 'expense-a', organizationId: 'org-a', restaurantLocationId: 'loc-a', amount: new Prisma.Decimal(25) };
    const prisma: any = {
      expense: { findUnique: jest.fn().mockResolvedValue(expense), update: jest.fn() },
      bankTransaction: { findFirst: jest.fn().mockResolvedValue({ id: 'bank-a' }) },
    };
    prisma.$transaction = jest.fn((callback: any) => callback(prisma));
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;

    await expect(new FinanceService(prisma, access, audit).updateExpense('user-a', 'expense-a', { amount: 30 }))
      .rejects.toThrow('linked to a bank transaction');
    expect(prisma.expense.update).not.toHaveBeenCalled();
  });
  it('rejects generic deletion of a bank-linked expense while preserving it', async () => {
    const expense = { id: 'expense-a', organizationId: 'org-a', restaurantLocationId: 'loc-a', amount: new Prisma.Decimal(25) };
    const prisma: any = {
      expense: { findUnique: jest.fn().mockResolvedValue(expense), delete: jest.fn() },
      bankTransaction: { findFirst: jest.fn().mockResolvedValue({ id: 'bank-a' }) },
    };
    prisma.$transaction = jest.fn((callback: any) => callback(prisma));
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;

    await expect(new FinanceService(prisma, access, audit).deleteExpense('user-a', 'expense-a'))
      .rejects.toThrow('through Bank Transactions');
    expect(prisma.expense.delete).not.toHaveBeenCalled();
  });
  it('allows generic edits and deletion when an expense has no bank link', async () => {
    const expense = { id: 'expense-a', organizationId: 'org-a', restaurantLocationId: 'loc-a', amount: new Prisma.Decimal(25) };
    const prisma: any = {
      expense: {
        findUnique: jest.fn().mockResolvedValue(expense),
        update: jest.fn().mockResolvedValue({ ...expense, amount: new Prisma.Decimal(30) }),
        delete: jest.fn().mockResolvedValue(expense),
      },
      bankTransaction: { findFirst: jest.fn().mockResolvedValue(null) },
    };
    prisma.$transaction = jest.fn((callback: any) => callback(prisma));
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    const service = new FinanceService(prisma, access, audit);

    await expect(service.updateExpense('user-a', 'expense-a', { amount: 30 })).resolves.toEqual(expect.objectContaining({ amount: new Prisma.Decimal(30) }));
    await expect(service.deleteExpense('user-a', 'expense-a')).resolves.toBeUndefined();
    expect(prisma.expense.update).toHaveBeenCalledTimes(1);
    expect(prisma.expense.delete).toHaveBeenCalledTimes(1);
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
  it('aggregates, searches, sorts, and paginates location-scoped vendor spend', async () => {
    const lastPurchase = new Date('2026-10-06T12:00:00.000Z');
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) },
      vendor: { findMany: jest.fn().mockResolvedValue([{ id: 'vendor-a', name: 'Sysco' }, { id: 'vendor-b', name: 'ADP' }]) },
      expense: { groupBy: jest.fn().mockResolvedValueOnce([{ vendorId: 'vendor-a', _sum: { amount: new Prisma.Decimal(1200) }, _count: { _all: 4 }, _max: { date: lastPurchase } }, { vendorId: 'vendor-b', _sum: { amount: new Prisma.Decimal(800) }, _count: { _all: 1 }, _max: { date: lastPurchase } }]).mockResolvedValueOnce([{ vendorId: 'vendor-a', _sum: { amount: new Prisma.Decimal(1000) } }, { vendorId: 'vendor-b', _sum: { amount: new Prisma.Decimal(400) } }]) },
    };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    const result = await new FinanceService(prisma, access, audit).vendorSummaries('user-a', { restaurantLocationId: 'loc-a', startDate: '2026-10-01', endDate: '2026-10-08', search: 's', sort: 'largestIncrease', page: 1, limit: 1 });
    expect(prisma.vendor.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: { organizationId: 'org-a', name: { contains: 's', mode: 'insensitive' } } }));
    expect(prisma.expense.groupBy.mock.calls[0][0].where).toEqual(expect.objectContaining({ organizationId: 'org-a', restaurantLocationId: 'loc-a' }));
    expect(result.items[0]).toEqual(expect.objectContaining({ id: 'vendor-b', currentSpend: 800, previousSpend: 400, percentageChange: 100, transactionCount: 1, lastPurchaseDate: lastPurchase }));
    expect(result.pagination).toEqual({ page: 1, limit: 1, totalItems: 2, totalPages: 2, hasMore: true });
  });
  it('returns vendor detail metrics, recent expenses, and daily trend', async () => {
    const date = new Date('2026-10-06T12:00:00.000Z');
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-a', organizationId: 'org-a' }) },
      vendor: { findFirst: jest.fn().mockResolvedValue({ id: 'vendor-a', name: 'Sysco' }) },
      expense: { aggregate: jest.fn().mockResolvedValueOnce({ _sum: { amount: new Prisma.Decimal(1200) }, _count: { _all: 4 }, _max: { date } }).mockResolvedValueOnce({ _sum: { amount: new Prisma.Decimal(1000) } }), findMany: jest.fn().mockResolvedValue([{ id: 'expense-a', date, description: 'Food delivery', expenseCategoryId: 'food', amount: new Prisma.Decimal(300) }]), groupBy: jest.fn().mockResolvedValue([{ date, _sum: { amount: new Prisma.Decimal(1200) } }]) },
      expenseCategory: { findMany: jest.fn().mockResolvedValue([{ id: 'food', name: 'Food' }]) },
    };
    const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    const result = await new FinanceService(prisma, access, audit).vendorSummary('user-a', 'vendor-a', { restaurantLocationId: 'loc-a', startDate: '2026-10-01', endDate: '2026-10-08' });
    expect(result.summary).toEqual(expect.objectContaining({ currentSpend: 1200, previousSpend: 1000, percentageChange: 20, transactionCount: 4, averageTransaction: 300, lastPurchaseDate: date }));
    expect(result.recentExpenses[0]).toEqual(expect.objectContaining({ categoryName: 'Food', amount: 300 }));
    expect(result.trend).toEqual([{ date: new Date('2026-10-06T00:00:00.000Z'), amount: 1200 }]);
  });
  it('does not aggregate vendors when location membership is denied', async () => {
    const prisma: any = { restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-b', organizationId: 'org-b' }) }, vendor: { findMany: jest.fn() }, expense: { groupBy: jest.fn() } };
    const access = { requireMember: jest.fn().mockRejectedValue(new ForbiddenException()) } as any;
    await expect(new FinanceService(prisma, access, audit).vendorSummaries('user-a', { restaurantLocationId: 'loc-b', startDate: '2026-10-01', endDate: '2026-10-08' })).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.vendor.findMany).not.toHaveBeenCalled();
    expect(prisma.expense.groupBy).not.toHaveBeenCalled();
  });
});
