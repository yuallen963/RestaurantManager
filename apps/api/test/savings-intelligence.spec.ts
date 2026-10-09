import { ForbiddenException } from '@nestjs/common';
import { calculateSavingsOpportunities, SavingsIntelligenceService, SavingsObservation } from '../src/savings-intelligence/savings-intelligence.service';

const now = new Date('2026-10-09T12:00:00.000Z');
const observation = (overrides: Partial<SavingsObservation> = {}): SavingsObservation => ({
  productGroupId: 'group-a', productName: 'Chicken Breast', vendorId: 'sysco', vendorName: 'Sysco', invoiceId: 'invoice-a', date: now,
  unit: 'CASE', packSize: '40 lb', totalWeightPounds: 40, unitPrice: 106.5, quantity: 12, ...overrides,
});
const thresholds = { minimumPercentageDifference: 5, minimumMonthlySavings: 25 };

describe('savings calculations', () => {
  it('uses the most recent purchase as current and the lowest recent alternative', () => {
    const result = calculateSavingsOpportunities([
      observation(),
      observation({ vendorId: 'usf', vendorName: 'US Foods', invoiceId: 'invoice-b', date: new Date('2026-10-01'), unitPrice: 94.2 }),
      observation({ vendorId: 'gfs', vendorName: 'GFS', invoiceId: 'invoice-c', date: new Date('2026-09-28'), unitPrice: 98 }),
    ], 90, thresholds).items[0];
    expect(result.currentVendor).toMatchObject({ name: 'Sysco', unitPrice: 106.5 });
    expect(result.lowerCostVendor).toMatchObject({ name: 'US Foods', unitPrice: 94.2 });
  });

  it('calculates monthly volume and monthly/annual savings', () => {
    const result = calculateSavingsOpportunities([
      observation({ quantity: 12 }),
      observation({ invoiceId: 'invoice-old', date: new Date('2026-09-01'), quantity: 12 }),
      observation({ vendorId: 'usf', vendorName: 'US Foods', invoiceId: 'invoice-b', date: new Date('2026-10-01'), unitPrice: 94.2, quantity: 12 }),
    ], 90, thresholds).items[0];
    expect(result.typicalMonthlyQuantity).toBe(12);
    expect(result.absoluteDifference).toBe(12.3);
    expect(result.estimatedMonthlySavings).toBe(147.6);
    expect(result.estimatedAnnualSavings).toBe(1771.2);
  });

  it('excludes incompatible purchasing bases', () => {
    expect(calculateSavingsOpportunities([observation(), observation({ vendorId: 'usf', unit: 'LB', totalWeightPounds: 1, unitPrice: 2 })], 90, thresholds).items).toEqual([]);
  });

  it('suppresses opportunities below percentage or monthly thresholds', () => {
    expect(calculateSavingsOpportunities([observation(), observation({ vendorId: 'usf', unitPrice: 103 })], 90, thresholds).items).toEqual([]);
    expect(calculateSavingsOpportunities([observation({ quantity: .1 }), observation({ vendorId: 'usf', unitPrice: 90, quantity: .1 })], 90, thresholds).items).toEqual([]);
  });

  it('excludes a group when the latest purchase is already cheapest', () => {
    expect(calculateSavingsOpportunities([observation({ unitPrice: 90 }), observation({ vendorId: 'usf', date: new Date('2026-10-01'), unitPrice: 94.2 })], 90, thresholds).items).toEqual([]);
  });

  it('sorts deterministically by monthly savings then percentage and recency', () => {
    const result = calculateSavingsOpportunities([
      observation({ productGroupId: 'group-b', productName: 'Oil', unitPrice: 120 }), observation({ productGroupId: 'group-b', vendorId: 'usf', unitPrice: 90, date: new Date('2026-10-01') }),
      observation(), observation({ vendorId: 'usf', unitPrice: 94.2, date: new Date('2026-10-01') }),
    ], 90, thresholds);
    expect(result.items.map((item) => item.productGroupId)).toEqual(['group-b', 'group-a']);
  });
});

describe('SavingsIntelligenceService scoping', () => {
  const location = { id: '00000000-0000-4000-8000-000000000002', organizationId: 'org-a' };
  function setup(requireMember = jest.fn()) {
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue(location) },
      productGroup: { findMany: jest.fn().mockResolvedValue([]) },
      invoiceLineItem: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = new SavingsIntelligenceService(prisma, { requireMember } as any, { get: jest.fn() } as any);
    return { service, prisma, requireMember };
  }

  it('queries confirmed groups only within the authorized tenant/location', async () => {
    const { service, prisma, requireMember } = setup();
    await service.get('user-a', { restaurantLocationId: location.id, lookbackDays: 90 });
    expect(requireMember).toHaveBeenCalledWith('user-a', 'org-a');
    expect(prisma.productGroup.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: { organizationId: 'org-a', restaurantLocationId: location.id, decisions: { some: { status: 'CONFIRMED' } } } }));
  });

  it('loads only reviewed, fresh invoice evidence for confirmed group vendors', async () => {
    const { service, prisma } = setup();
    prisma.productGroup.findMany.mockResolvedValue([{
      id: 'group-a', displayName: 'Chicken', members: [{
        vendorId: 'vendor-a', vendor: { id: 'vendor-a', name: 'Sysco' },
        invoiceLineItem: { sku: 'SKU-A', normalizedName: null, rawDescription: 'Chicken', unit: 'CASE', packSize: '40 lb' },
      }],
    }]);
    await service.get('user-a', { restaurantLocationId: location.id, lookbackDays: 90 });
    expect(prisma.invoiceLineItem.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({
        organizationId: 'org-a', restaurantLocationId: location.id,
        invoice: expect.objectContaining({ reviewStatus: 'REVIEWED', vendorId: { in: ['vendor-a'] }, invoiceDate: { gte: expect.any(Date), lte: expect.any(Date) } }),
      }),
    }));
  });

  it('rejects cross-tenant access before reading groups', async () => {
    const denied = jest.fn().mockRejectedValue(new ForbiddenException());
    const { service, prisma } = setup(denied);
    await expect(service.get('other-user', { restaurantLocationId: location.id, lookbackDays: 90 })).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.productGroup.findMany).not.toHaveBeenCalled();
  });
});
