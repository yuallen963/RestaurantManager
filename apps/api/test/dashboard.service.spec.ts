import { ForbiddenException } from '@nestjs/common';
import { BankReconciliationStatus, Prisma, ReviewStatus } from '@prisma/client';
import { DashboardService } from '../src/dashboard/dashboard.service';

const dec = (value: number) => new Prisma.Decimal(value);
const location = { id: 'location-a', organizationId: 'org-a' };

function fixture(overrides: Record<string, any> = {}) {
  const prisma: any = {
    restaurantLocation: { findUnique: jest.fn().mockResolvedValue(location) },
    revenueEntry: { aggregate: jest.fn().mockResolvedValue({ _sum: { amount: dec(0) } }), count: jest.fn().mockResolvedValue(0) },
    expense: { aggregate: jest.fn().mockResolvedValue({ _sum: { amount: dec(0) } }), count: jest.fn().mockResolvedValue(0), groupBy: jest.fn().mockResolvedValue([]) },
    expenseCategory: { findMany: jest.fn().mockResolvedValue([]) },
    bankTransaction: { findMany: jest.fn().mockResolvedValue([]), aggregate: jest.fn().mockResolvedValue({ _sum: { amount: dec(0) } }) },
    bankConnection: { count: jest.fn().mockResolvedValue(0) },
    invoice: { findMany: jest.fn().mockResolvedValue([]), count: jest.fn().mockResolvedValue(0), aggregate: jest.fn().mockResolvedValue({ _sum: { total: dec(0) } }) },
    posLocationMapping: { count: jest.fn().mockResolvedValue(0) },
  };
  for (const [key, value] of Object.entries(overrides)) prisma[key] = { ...prisma[key], ...value };
  return prisma;
}

const access = () => ({ requireMember: jest.fn().mockResolvedValue({}) } as any);
const query = { restaurantLocationId: 'location-a', startDate: '2026-10-01', endDate: '2026-10-31' };

describe('DashboardService adaptive dashboard', () => {
  it('returns an explicit no-source state', async () => {
    const result = await new DashboardService(fixture(), access()).get('user-a', query);
    expect(result.availability).toEqual({ bank: false, reviewedInvoices: false, revenue: false, pos: false, expenses: false, profitability: false });
  });

  it('summarizes bank outflows without calling them expenses or revenue', async () => {
    const prisma = fixture({
      bankConnection: { count: jest.fn().mockResolvedValue(1) },
      bankTransaction: {
        findMany: jest.fn().mockResolvedValue([{ id: 'tx-1', amount: dec(125), description: 'Restaurant Depot', merchantNameNormalized: 'Restaurant Depot', categoryId: 'food', reconciliationStatus: BankReconciliationStatus.UNMATCHED, invoiceId: null, vendor: null, category: { name: 'Food' } }]),
        aggregate: jest.fn().mockResolvedValue({ _sum: { amount: dec(100) } }),
      },
    });
    const result = await new DashboardService(prisma, access()).get('user-a', query);
    expect(result.availability).toMatchObject({ bank: true, revenue: false, profitability: false });
    expect(result.bank).toMatchObject({ trackedOutflows: 125, previousTrackedOutflows: 100, unmatchedCount: 1 });
    expect(result.bank.categoryBreakdown).toEqual([{ name: 'Food', amount: 125 }]);
    expect(prisma.bankTransaction.findMany.mock.calls[0][0].where).toMatchObject({ organizationId: 'org-a', restaurantLocationId: 'location-a' });
  });

  it('summarizes only reviewed invoice purchases', async () => {
    const prisma = fixture({ invoice: {
      findMany: jest.fn().mockResolvedValue([
        { id: 'reviewed', total: dec(300), reviewStatus: ReviewStatus.REVIEWED, vendor: { name: 'Atlas' }, extractedVendorName: null, bankTransactions: [] },
        { id: 'draft', total: dec(900), reviewStatus: ReviewStatus.NEEDS_REVIEW, vendor: null, extractedVendorName: 'Draft', bankTransactions: [] },
      ]), count: jest.fn().mockResolvedValue(1),
    } });
    const result = await new DashboardService(prisma, access()).get('user-a', query);
    expect(result.availability).toMatchObject({ reviewedInvoices: true, profitability: false });
    expect(result.invoices).toMatchObject({ reviewedPurchases: 300, reviewedCount: 1, requiringReviewCount: 1, unmatchedCount: 1 });
  });

  it('keeps matched bank outflows and invoice purchases separate', async () => {
    const prisma = fixture({
      bankConnection: { count: jest.fn().mockResolvedValue(1) },
      bankTransaction: { findMany: jest.fn().mockResolvedValue([{ id: 'tx', amount: dec(100), description: 'Atlas', merchantNameNormalized: 'Atlas', categoryId: null, reconciliationStatus: BankReconciliationStatus.MATCHED_INVOICE, invoiceId: 'invoice', vendor: { name: 'Atlas' }, category: null }]) },
      invoice: { findMany: jest.fn().mockResolvedValue([{ id: 'invoice', total: dec(100), reviewStatus: ReviewStatus.REVIEWED, vendor: { name: 'Atlas' }, extractedVendorName: null, bankTransactions: [{ id: 'tx' }] }]) },
    });
    const result = await new DashboardService(prisma, access()).get('user-a', query);
    expect(result.bank.trackedOutflows).toBe(100);
    expect(result.invoices.reviewedPurchases).toBe(100);
    expect(result.bank.matchedInvoiceCount).toBe(1);
    expect(result.invoices.unmatchedCount).toBe(0);
    expect(result.availability.profitability).toBe(false);
  });

  it('shows revenue/POS availability without inventing profitability', async () => {
    const prisma = fixture({
      revenueEntry: { aggregate: jest.fn().mockResolvedValue({ _sum: { amount: dec(10000) } }), count: jest.fn().mockResolvedValue(2) },
      posLocationMapping: { count: jest.fn().mockResolvedValue(1) },
    });
    const result = await new DashboardService(prisma, access()).get('user-a', query);
    expect(result.availability).toMatchObject({ revenue: true, pos: true, expenses: false, profitability: false });
    expect(result.summary.revenue).toBe(10000);
  });

  it('exposes profitability only when revenue and cost sources are present', async () => {
    const prisma = fixture({
      revenueEntry: { aggregate: jest.fn().mockResolvedValue({ _sum: { amount: dec(10000) } }), count: jest.fn().mockResolvedValue(1) },
      expense: { aggregate: jest.fn().mockResolvedValue({ _sum: { amount: dec(6000) } }), count: jest.fn().mockResolvedValue(3), groupBy: jest.fn().mockResolvedValue([{ expenseCategoryId: 'food', _sum: { amount: dec(3000) } }, { expenseCategoryId: 'labor', _sum: { amount: dec(2500) } }]) },
      expenseCategory: { findMany: jest.fn().mockResolvedValue([{ id: 'food', name: 'Food', classification: 'FOOD' }, { id: 'labor', name: 'Labor', classification: 'LABOR' }]) },
      bankConnection: { count: jest.fn().mockResolvedValue(1) },
      invoice: { findMany: jest.fn().mockResolvedValue([{ id: 'invoice', total: dec(100), reviewStatus: ReviewStatus.REVIEWED, vendor: null, extractedVendorName: 'Vendor', bankTransactions: [] }]) },
    });
    const result = await new DashboardService(prisma, access()).get('user-a', query);
    expect(result.availability.profitability).toBe(true);
    expect(result.summary).toMatchObject({ revenue: 10000, expenses: 6000, estimatedProfit: 4000, profitMargin: 40, foodCostPercentage: 30, laborCostPercentage: 25 });
  });

  it('does not query financial data without location access', async () => {
    const prisma = fixture();
    const denied = { requireMember: jest.fn().mockRejectedValue(new ForbiddenException()) } as any;
    await expect(new DashboardService(prisma, denied).get('user-b', query)).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.revenueEntry.aggregate).not.toHaveBeenCalled();
  });
});
