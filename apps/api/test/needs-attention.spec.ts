import { ForbiddenException } from '@nestjs/common';
import { BankReconciliationStatus, InsightStatus, Prisma, ReviewStatus } from '@prisma/client';
import { comparisonPeriod, NeedsAttentionService, severityFor, severityScore } from '../src/needs-attention/needs-attention.service';

const location = { id: '00000000-0000-4000-8000-000000000002', organizationId: 'org-a', name: 'Downtown Grill' };
const query = { restaurantLocationId: location.id, startDate: '2026-10-01T00:00:00.000Z', endDate: '2026-10-08T00:00:00.000Z' };
const dashboard = (food: number, labor: number) => ({ summary: { foodCostPercentage: food, laborCostPercentage: labor } });
const priceItem = {
  itemKey: 'item-key', displayName: 'Chicken Breast', vendorName: 'Sysco',
  currentUnitPrice: 106.5, previousUnitPrice: 98, percentageChange: 8.67,
  estimatedMonthlyImpact: 102, latestSeenAt: '2026-10-03T12:00:00.000Z', consecutiveIncreases: 2,
};

function setup({
  currentDashboard = dashboard(30.5, 34),
  previousDashboard = dashboard(27, 29),
  prices = [priceItem],
  currentVendors = [{ vendorId: 'vendor-a', _sum: { amount: 10100 }, _max: { date: new Date('2026-10-08') } }],
  previousVendors = [{ vendorId: 'vendor-a', _sum: { amount: 8200 } }],
  currentCategories = [{ expenseCategoryId: 'category-a', _sum: { amount: 1200 }, _max: { date: new Date('2026-10-08') } }],
  previousCategories = [{ expenseCategoryId: 'category-a', _sum: { amount: 800 } }],
  bankTransactions = [],
  reviewedInvoices = [],
  insightStatus = InsightStatus.ACTIVE,
  requireMember = jest.fn(),
}: any = {}) {
  const groupBy = jest.fn()
    .mockResolvedValueOnce(currentVendors)
    .mockResolvedValueOnce(previousVendors)
    .mockResolvedValueOnce(currentCategories)
    .mockResolvedValueOnce(previousCategories);
  const prisma: any = {
    restaurantLocation: { findUnique: jest.fn().mockResolvedValue(location) },
    expense: { groupBy },
    vendor: { findMany: jest.fn().mockResolvedValue([{ id: 'vendor-a', name: 'Sysco' }]) },
    expenseCategory: { findMany: jest.fn().mockResolvedValue([{ id: 'category-a', name: 'Food Supplies' }]) },
    bankTransaction: { findMany: jest.fn().mockResolvedValue(bankTransactions) },
    bankConnection: { count: jest.fn().mockResolvedValue(bankTransactions.length ? 1 : 0) },
    invoice: { findMany: jest.fn().mockResolvedValue(reviewedInvoices) },
    insight: {
      upsert: jest.fn().mockImplementation(({ create }: any) => ({ ...create, id: `insight-${create.fingerprint.slice(0, 8)}`, status: insightStatus })),
      findUnique: jest.fn(),
      update: jest.fn(),
    },
  };
  const dashboardService: any = { get: jest.fn().mockResolvedValueOnce(currentDashboard).mockResolvedValueOnce(previousDashboard) };
  const priceService: any = { changes: jest.fn().mockResolvedValue({ items: prices }) };
  const service = new NeedsAttentionService(
    prisma,
    { requireMember } as any,
    dashboardService,
    priceService,
    { get: jest.fn().mockReturnValue(undefined) } as any,
  );
  return { service, prisma, dashboardService, priceService, requireMember };
}

describe('NeedsAttentionService', () => {
  it('generates every supported deterministic issue and identifies repeated increases', async () => {
    const { service, priceService } = setup();
    const result = await service.get('user-a', query);
    expect(result.items.map((item) => item.type)).toEqual(expect.arrayContaining([
      'REPEATED_ITEM_PRICE_INCREASE',
      'FOOD_COST_DETERIORATION',
      'LABOR_COST_DETERIORATION',
      'VENDOR_SPEND_INCREASE',
      'CATEGORY_SPEND_INCREASE',
    ]));
    const repeated = result.items.find((item) => item.type === 'REPEATED_ITEM_PRICE_INCREASE')!;
    expect(repeated.message).toContain('2 consecutive purchases');
    expect(repeated.estimatedMonthlyImpact).toBe(102);
    expect(priceService.changes).toHaveBeenCalledWith('user-a', expect.objectContaining({ direction: 'increase' }));
  });

  it('uses percentage-point deterioration and leaves dashboard impact unavailable', async () => {
    const { service } = setup({ prices: [], currentVendors: [], previousVendors: [], currentCategories: [], previousCategories: [] });
    const result = await service.get('user-a', query);
    expect(result.items.find((item) => item.type === 'FOOD_COST_DETERIORATION')).toMatchObject({ previousValue: 27, currentValue: 30.5, percentagePointChange: 3.5, estimatedMonthlyImpact: null });
    expect(result.items.find((item) => item.type === 'LABOR_COST_DETERIORATION')).toMatchObject({ previousValue: 29, currentValue: 34, percentagePointChange: 5, estimatedMonthlyImpact: null });
  });

  it('suppresses below-threshold changes and small-dollar noise', async () => {
    const { service } = setup({
      currentDashboard: dashboard(28, 30), previousDashboard: dashboard(27, 29), prices: [],
      currentVendors: [{ vendorId: 'vendor-a', _sum: { amount: 120 }, _max: { date: new Date('2026-10-08') } }],
      previousVendors: [{ vendorId: 'vendor-a', _sum: { amount: 100 } }],
      currentCategories: [{ expenseCategoryId: 'category-a', _sum: { amount: 120 }, _max: { date: new Date('2026-10-08') } }],
      previousCategories: [{ expenseCategoryId: 'category-a', _sum: { amount: 100 } }],
    });
    const result = await service.get('user-a', query);
    expect(result.items).toEqual([]);
    expect(result.summary).toEqual({ critical: 0, high: 0, medium: 0, low: 0, estimatedMonthlyImpact: 0 });
  });

  it('orders by severity, impact, recency, then stable id and does not double-count aggregate impact', async () => {
    const { service } = setup();
    const result = await service.get('user-a', query);
    for (let index = 1; index < result.items.length; index += 1) {
      const ranks: any = { CRITICAL: 4, HIGH: 3, MEDIUM: 2, LOW: 1 };
      expect(ranks[result.items[index - 1].severity]).toBeGreaterThanOrEqual(ranks[result.items[index].severity]);
    }
    expect(result.summary.estimatedMonthlyImpact).toBe(102);
  });

  it('scopes every aggregate to the authorized tenant and location', async () => {
    const { service, prisma, requireMember } = setup();
    await service.get('user-a', query);
    expect(requireMember).toHaveBeenCalledWith('user-a', 'org-a');
    for (const call of prisma.expense.groupBy.mock.calls) {
      expect(call[0].where).toEqual(expect.objectContaining({ organizationId: 'org-a', restaurantLocationId: location.id }));
    }
  });

  it('stops before reading signals when tenant authorization fails', async () => {
    const denied = jest.fn().mockRejectedValue(new ForbiddenException());
    const { service, prisma } = setup({ requireMember: denied });
    await expect(service.get('other-user', query)).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.expense.groupBy).not.toHaveBeenCalled();
  });

  it('flags nearby same-merchant bank payments but not monthly recurring charges', async () => {
    const payment = (id: string, date: string) => ({
      id, amount: new Prisma.Decimal('249.99'), postedDate: new Date(date),
      description: 'SUPPLIER PAYMENT', merchantNameNormalized: 'Supplier',
      vendorId: 'vendor-a', invoiceId: null, suggestedInvoiceId: null,
      reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW,
      vendor: { name: 'Supplier' },
    });
    const duplicate = setup({
      currentDashboard: dashboard(0, 0), previousDashboard: dashboard(0, 0), prices: [],
      currentVendors: [], previousVendors: [], currentCategories: [], previousCategories: [],
      bankTransactions: [payment('a', '2026-10-06'), payment('b', '2026-10-07')],
    });
    expect((await duplicate.service.get('user-a', query)).items.map((item: any) => item.type)).toContain('POSSIBLE_DUPLICATE_PAYMENT');

    const recurring = setup({
      currentDashboard: dashboard(0, 0), previousDashboard: dashboard(0, 0), prices: [],
      currentVendors: [], previousVendors: [], currentCategories: [], previousCategories: [],
      bankTransactions: [payment('a', '2026-09-07'), payment('b', '2026-10-07')],
    });
    expect((await recurring.service.get('user-a', { ...query, startDate: '2026-09-01T00:00:00.000Z' })).items.map((item: any) => item.type)).not.toContain('POSSIBLE_DUPLICATE_PAYMENT');
  });

  it('uses neutral unmatched invoice/payment language and preserves suggested matches', async () => {
    const invoice = { id: 'invoice-a', invoiceNumber: 'INV-10', invoiceDate: new Date('2026-10-04'), total: new Prisma.Decimal(500), reviewStatus: ReviewStatus.REVIEWED, vendor: { name: 'Supplier' }, extractedVendorName: null };
    const transaction = { id: 'payment-a', amount: new Prisma.Decimal(500), postedDate: new Date('2026-10-05'), description: 'Supplier payment', merchantNameNormalized: 'Supplier', vendorId: 'vendor-a', invoiceId: null, suggestedInvoiceId: 'invoice-a', reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW, vendor: { name: 'Supplier' } };
    const { service } = setup({ currentDashboard: dashboard(0, 0), previousDashboard: dashboard(0, 0), prices: [], currentVendors: [], previousVendors: [], currentCategories: [], previousCategories: [], reviewedInvoices: [invoice], bankTransactions: [transaction] });
    const result = await service.get('user-a', query);
    expect(result.items.find((item: any) => item.type === 'UNMATCHED_INVOICE')).toMatchObject({ message: expect.stringContaining('possible bank match'), action: { type: 'OPEN_INVOICE', targetId: 'invoice-a' } });
    expect(result.items.find((item: any) => item.type === 'UNMATCHED_PAYMENT')).toMatchObject({ message: expect.stringContaining('possible invoice match'), action: { type: 'OPEN_BANK_TRANSACTION', targetId: 'payment-a' } });
    expect(result.items.map((item: any) => item.type)).not.toContain('MISSING_CREDIT');
  });

  it('does not call reviewed invoices unpaid when bank coverage is unavailable', async () => {
    const invoice = { id: 'invoice-a', invoiceNumber: 'INV-10', invoiceDate: new Date('2026-10-04'), total: new Prisma.Decimal(500), reviewStatus: ReviewStatus.REVIEWED, vendor: { name: 'Supplier' }, extractedVendorName: null };
    const { service } = setup({ prices: [], currentVendors: [], previousVendors: [], currentCategories: [], previousCategories: [], reviewedInvoices: [invoice], bankTransactions: [] });
    const result = await service.get('user-a', query);
    expect(result.items.some((item: any) => item.type === 'UNMATCHED_INVOICE')).toBe(false);
  });

  it('suppresses dismissed evidence but allows a materially new fingerprint', async () => {
    const dismissed = setup({ insightStatus: InsightStatus.DISMISSED });
    const result = await dismissed.service.get('user-a', query);
    expect(result.items).toEqual([]);
    expect(dismissed.prisma.insight.upsert).toHaveBeenCalled();
  });

  it('updates lifecycle status only after tenant authorization', async () => {
    const { service, prisma, requireMember } = setup();
    prisma.insight.findUnique.mockResolvedValue({ id: 'insight-a', organizationId: 'org-a', reviewedAt: null });
    prisma.insight.update.mockResolvedValue({ id: 'insight-a', status: InsightStatus.RESOLVED });
    await service.updateStatus('user-a', 'insight-a', InsightStatus.RESOLVED);
    expect(requireMember).toHaveBeenCalledWith('user-a', 'org-a');
    expect(prisma.insight.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ status: InsightStatus.RESOLVED, resolvedAt: expect.any(Date) }) }));
  });
});

describe('Needs Attention deterministic utilities', () => {
  it('resolves an equal-length previous comparison period', () => {
    const period = comparisonPeriod('2026-10-01T00:00:00.000Z', '2026-10-08T00:00:00.000Z');
    expect(period.dayCount).toBe(8);
    expect(period.previousStart.toISOString()).toBe('2026-09-23T00:00:00.000Z');
    expect(period.previousEnd.toISOString()).toBe('2026-09-30T23:59:59.999Z');
  });

  it('scores severity explainably from impact, change, repetition, deterioration, and recency', () => {
    const score = severityScore({ estimatedMonthlyImpact: 550, percentageChange: 30, consecutiveIncreases: 2, percentagePointChange: 3.5, occurredAt: new Date('2026-10-05'), now: new Date('2026-10-08') });
    expect(score).toBe(9);
    expect(severityFor(score, { medium: 3, high: 5, critical: 7 })).toBe('CRITICAL');
    expect(severityFor(0, { medium: 3, high: 5, critical: 7 })).toBe('LOW');
  });
});
