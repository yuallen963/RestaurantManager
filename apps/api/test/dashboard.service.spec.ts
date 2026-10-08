import { ForbiddenException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { DashboardService } from '../src/dashboard/dashboard.service';

const dec = (value: number) => new Prisma.Decimal(value);
const location = { id: 'location-a', organizationId: 'org-a' };
function fixture(overrides: Record<string, unknown> = {}) {
  return {
    restaurantLocation: { findUnique: jest.fn().mockResolvedValue(location) },
    revenueEntry: { aggregate: jest.fn().mockResolvedValue({ _sum: { amount: dec(10000) } }) },
    expense: {
      aggregate: jest.fn().mockResolvedValue({ _sum: { amount: dec(6000) } }),
      groupBy: jest.fn().mockResolvedValue([
        { expenseCategoryId: 'food', _sum: { amount: dec(3000) } },
        { expenseCategoryId: 'labor', _sum: { amount: dec(2500) } },
        { expenseCategoryId: 'utilities', _sum: { amount: dec(500) } },
      ]),
    },
    expenseCategory: { findMany: jest.fn().mockResolvedValue([
      { id: 'food', name: 'Food', classification: 'FOOD' },
      { id: 'labor', name: 'Labor', classification: 'LABOR' },
      { id: 'utilities', name: 'Utilities', classification: 'UTILITIES' },
    ]) },
    ...overrides,
  } as any;
}
describe('DashboardService financial calculations', () => {
  it('calculates exact totals, percentages, classifications, and expense breakdown', async () => {
    const prisma = fixture(); const access = { requireMember: jest.fn().mockResolvedValue({}) } as any;
    const result = await new DashboardService(prisma, access).get('user-a', { restaurantLocationId: 'location-a', startDate: '2026-10-01', endDate: '2026-10-31' });
    expect(result.summary).toEqual({ revenue: 10000, expenses: 6000, estimatedProfit: 4000, profitMargin: 40, foodCost: 3000, foodCostPercentage: 30, laborCost: 2500, laborCostPercentage: 25 });
    expect(result.expenseBreakdown).toEqual(expect.arrayContaining([{ categoryId: 'food', categoryName: 'Food', amount: 3000, percentageOfExpenses: 50 }, { categoryId: 'labor', categoryName: 'Labor', amount: 2500, percentageOfExpenses: 41.7 }, { categoryId: 'utilities', categoryName: 'Utilities', amount: 500, percentageOfExpenses: 8.3 }]));
    expect(prisma.revenueEntry.aggregate.mock.calls[0][0].where.date).toEqual({ gte: new Date('2026-10-01'), lte: expect.any(Date) });
  });
  it('returns safe zero percentages when revenue is zero', async () => {
    const prisma = fixture({ revenueEntry: { aggregate: jest.fn().mockResolvedValue({ _sum: { amount: dec(0) } }) }, expense: { aggregate: jest.fn().mockResolvedValue({ _sum: { amount: dec(500) } }), groupBy: jest.fn().mockResolvedValue([]) } });
    const result = await new DashboardService(prisma, { requireMember: jest.fn().mockResolvedValue({}) } as any).get('user-a', { restaurantLocationId: 'location-a' });
    expect(result.summary.profitMargin).toBe(0); expect(result.summary.foodCostPercentage).toBe(0); expect(result.summary.laborCostPercentage).toBe(0); expect(result.summary.estimatedProfit).toBe(-500);
  });
  it('does not query data when the caller cannot access the location organization', async () => {
    const prisma = fixture(); const access = { requireMember: jest.fn().mockRejectedValue(new ForbiddenException()) } as any;
    await expect(new DashboardService(prisma, access).get('user-b', { restaurantLocationId: 'location-a' })).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.revenueEntry.aggregate).not.toHaveBeenCalled();
  });
});
