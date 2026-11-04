import { ForbiddenException } from '@nestjs/common';
import { calculateSavingsOpportunities, SavingsIntelligenceService, SavingsObservation } from '../src/savings-intelligence/savings-intelligence.service';

const now = new Date('2026-10-09T12:00:00.000Z');
const observation = (overrides: Partial<SavingsObservation> = {}): SavingsObservation => ({
  productGroupId: 'group-a', productName: 'Chicken Breast', vendorId: 'sysco', vendorName: 'Sysco', invoiceId: 'invoice-a', lineItemId: 'line-a', date: now,
  unit: 'lb', currency: 'USD', packSize: '40 lb', normalizedUnitPrice: 2.6625, normalizedQuantity: 40, ...overrides,
});
const thresholds = { minimumPercentageDifference: 5, minimumMonthlySavings: 25 };
const history = () => [
  observation(),
  observation({ invoiceId: 'invoice-b', lineItemId: 'line-b', date: new Date('2026-09-01'), normalizedQuantity: 40 }),
  observation({ vendorId: 'usf', vendorName: 'US Foods', invoiceId: 'invoice-c', lineItemId: 'line-c', date: new Date('2026-09-20'), normalizedUnitPrice: 2, normalizedQuantity: 40 }),
];

describe('savings calculations', () => {
  it('uses normalized price and historical normalized volume', () => {
    const result = calculateSavingsOpportunities(history(), 90, thresholds).items[0];
    expect(result.currentVendor.unitPrice).toBe(2.66);
    expect(result.lowerCostVendor.unitPrice).toBe(2);
    expect(result.typicalMonthlyQuantity).toBeCloseTo(91.139, 2);
    expect(result.estimatedMonthlySavings).toBeGreaterThan(60);
    expect(result.estimatedAnnualSavings).toBeCloseTo(result.estimatedMonthlySavings * 12, 0);
  });

  it('withholds projections for fewer than three observations or less than 28 days', () => {
    const tooFew = calculateSavingsOpportunities(history().slice(0, 2), 90, thresholds);
    expect(tooFew.items).toEqual([]);
    const tooShort = calculateSavingsOpportunities(history().map((row, index) => ({ ...row, date: new Date(`2026-10-0${3 - index}`) })), 90, thresholds);
    expect(tooShort.items).toEqual([]);
    expect(tooShort.eligibility.insufficientHistoryGroups).toBe(1);
  });

  it('excludes incompatible units and currencies', () => {
    const rows = history().map((row) => row.vendorId === 'usf' ? { ...row, unit: 'gallon' as const } : row);
    expect(calculateSavingsOpportunities(rows, 90, thresholds).items).toEqual([]);
    expect(calculateSavingsOpportunities(history().map((row) => row.vendorId === 'usf' ? { ...row, currency: 'EUR' as any } : row), 90, thresholds).items).toEqual([]);
  });

  it('deduplicates repeated group members for the same line', () => {
    expect(calculateSavingsOpportunities([...history(), ...history()], 90, thresholds).items[0].evidence).toHaveLength(3);
  });

  it('rejects implausible one-off volume as a reliable projection', () => {
    const rows = history(); rows[0].normalizedQuantity = 1000;
    expect(calculateSavingsOpportunities(rows, 90, thresholds).items).toEqual([]);
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
        invoice: expect.objectContaining({ reviewStatus: 'REVIEWED', duplicateResolution: { not: 'DUPLICATE' }, vendorId: { in: ['vendor-a'] }, invoiceDate: { gte: expect.any(Date), lte: expect.any(Date) } }),
      }),
    }));
  });

  it('excludes unverified package evidence and never matches names alone', async () => {
    const { service, prisma } = setup();
    const verified = { kind: 'OBSERVED', verified: true };
    prisma.productGroup.findMany.mockResolvedValue([{ id: 'group-a', displayName: 'Rice', members: [{ vendorId: 'vendor-a', vendor: { id: 'vendor-a', name: 'Vendor A' }, invoiceLineItem: { id: 'exemplar', sku: 'RICE-25', rawDescription: 'Rice', fieldProvenance: { sku: verified }, productAttributes: null } }] }]);
    const base = { organizationId: 'org-a', restaurantLocationId: location.id, lineNumber: 1, rawDescription: 'Rice', normalizedName: 'Rice', quantity: 1, unit: 'CASE', packSize: '25 lb', totalPackageQuantity: 25, measurementUnit: 'LB', unitPrice: 25, extendedPrice: 25, productAttributes: null, invoice: { id: 'invoice-a', vendorId: 'vendor-a', invoiceDate: now, currency: 'USD', fieldProvenance: { currency: verified } } };
    prisma.invoiceLineItem.findMany.mockResolvedValue([
      { ...base, id: 'unverified', sku: 'RICE-25', fieldProvenance: { sku: verified, quantity: verified, extendedPrice: verified } },
      { ...base, id: 'name-only', sku: 'OTHER', fieldProvenance: { sku: verified, quantity: verified, extendedPrice: verified, packSize: verified } },
    ]);
    const result = await service.get('user-a', { restaurantLocationId: location.id, lookbackDays: 90 });
    expect(result.items).toEqual([]);
    expect(result.eligibility.excludedObservations).toEqual({ UNVERIFIED_PACKAGE: 1 });
  });

  it('rejects cross-tenant access before reading groups', async () => {
    const denied = jest.fn().mockRejectedValue(new ForbiddenException());
    const { service, prisma } = setup(denied);
    await expect(service.get('other-user', { restaurantLocationId: location.id, lookbackDays: 90 })).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.productGroup.findMany).not.toHaveBeenCalled();
  });
});
