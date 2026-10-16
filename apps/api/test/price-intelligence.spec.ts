import { ForbiddenException } from '@nestjs/common';
import { PriceChangeDirection, PriceChangeSort } from '../src/price-intelligence/dto';
import { analyzePriceObservations, canonicalDescription, normalizePriceObservation, PriceIntelligenceService, TrustedPriceObservation } from '../src/price-intelligence/price-intelligence.service';

const now = new Date('2026-10-08T12:00:00.000Z');
const options = { lookbackDays: 90, percentThreshold: 5, absoluteThreshold: .5 };
const row = (overrides: Partial<TrustedPriceObservation> = {}): TrustedPriceObservation => ({
  invoiceId: 'invoice-a',
  invoiceDate: new Date('2026-08-01T12:00:00.000Z'),
  lineNumber: 1,
  vendorId: 'vendor-a',
  vendorName: 'Sysco',
  rawDescription: 'CHKN BRST BNLS SKLS 4/10 LB',
  sku: '384920',
  quantity: 12,
  unit: 'CASE',
  packSize: '1 EA',
  measurementUnit: 'EA',
  totalPackageQuantity: 1,
  unitPrice: 91,
  extendedPrice: null,
  currency: 'USD',
  currencyProvenance: { currency: { kind: 'OBSERVED', verified: true } },
  fieldProvenance: Object.fromEntries(['rawDescription', 'sku', 'quantity', 'unit', 'packSize', 'unitPrice', 'extendedPrice'].map((field) => [field, { kind: 'OBSERVED', verified: true }])),
  ...overrides,
});

describe('price intelligence calculations', () => {
  it('matches the same vendor and SKU while preserving source descriptions', () => {
    const result = analyzePriceObservations([
      row(),
      row({ invoiceId: 'invoice-b', invoiceDate: now, rawDescription: 'Different printed wording', unitPrice: 106.5 }),
    ], options);
    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({ previousUnitPrice: 91, currentUnitPrice: 106.5, absoluteChange: 15.5, percentageChange: 17.03 });
    expect(result[0].displayName).toBe('Different printed wording');
  });

  it('requires a confirmed product group when SKU is absent', () => {
    expect(canonicalDescription('  CHKN BRST, BNLS   SKLS 4/10 LB ')).toBe('CHKN BRST BNLS SKLS 4/10 LB');
    expect(analyzePriceObservations([
      row({ sku: null, rawDescription: 'CHKN BRST, BNLS   SKLS 4/10 LB' }),
      row({ invoiceId: 'invoice-b', invoiceDate: now, sku: null, rawDescription: 'chkn brst bnls skls 4/10 lb', unitPrice: 98 }),
    ], options)).toEqual([]);
    const result = analyzePriceObservations([
      row({ sku: null, productGroupId: 'confirmed-chicken' }),
      row({ invoiceId: 'invoice-b', invoiceDate: now, sku: null, productGroupId: 'confirmed-chicken', unitPrice: 98 }),
    ], options);
    expect(result).toHaveLength(1);
  });

  it('never combines different vendors', () => {
    const result = analyzePriceObservations([
      row(),
      row({ invoiceId: 'invoice-b', invoiceDate: now, vendorId: 'vendor-b', vendorName: 'US Foods', unitPrice: 106.5 }),
    ], options);
    expect(result).toHaveLength(0);
  });

  it.each([
    [{ measurementUnit: 'LB', totalPackageQuantity: 40 }, { measurementUnit: 'GAL', totalPackageQuantity: 5 }],
    [{ productAttributes: { organic: 'organic' } }, { productAttributes: { organic: 'conventional' } }],
  ])('excludes incompatible product bases', (first, second) => {
    expect(analyzePriceObservations([
      row(first),
      row({ invoiceId: 'invoice-b', invoiceDate: now, unitPrice: 106.5, ...second }),
    ], options)).toHaveLength(0);
  });

  it('normalizes different verified case sizes to the same price per pound', () => {
    const first = row({ quantity: 1, unitPrice: 120, packSize: '40 LB', measurementUnit: 'LB', totalPackageQuantity: 40 });
    const second = row({ invoiceId: 'invoice-b', invoiceDate: now, quantity: 1, unitPrice: 30, packSize: '10 LB', measurementUnit: 'LB', totalPackageQuantity: 10 });
    expect(normalizePriceObservation(first)?.normalizedUnitPrice.toNumber()).toBe(3);
    const result = analyzePriceObservations([first, second], options)[0];
    expect(result.unit).toBe('lb');
    expect(result.previousUnitPrice).toBe(3);
    expect(result.currentUnitPrice).toBe(3);
  });

  it('calculates multiple cases independently from package size and line cost', () => {
    const normalized = normalizePriceObservation(row({
      quantity: 3,
      unitPrice: 120,
      packSize: '40 LB',
      measurementUnit: 'LB',
      totalPackageQuantity: 40,
    }))!;
    expect(normalized.normalizedQuantity.toNumber()).toBe(120);
    expect(normalized.purchasePrice.toNumber()).toBe(360);
    expect(normalized.normalizedUnitPrice.toNumber()).toBe(3);
  });

  it('uses an observed discounted line extension and rejects credits', () => {
    const discounted = normalizePriceObservation(row({
      quantity: 3, unitPrice: 120, extendedPrice: 330,
      packSize: '40 LB', measurementUnit: 'LB', totalPackageQuantity: 40,
    }))!;
    expect(discounted.normalizedUnitPrice.toNumber()).toBe(2.75);
    const extensionOnly = normalizePriceObservation(row({
      quantity: 3, unitPrice: null, extendedPrice: 360,
      packSize: '40 LB', measurementUnit: 'LB', totalPackageQuantity: 40,
    }))!;
    expect(extensionOnly.normalizedQuantity.toNumber()).toBe(120);
    expect(extensionOnly.purchasePrice.toNumber()).toBe(360);
    expect(extensionOnly.normalizedUnitPrice.toNumber()).toBe(3);
    expect(normalizePriceObservation(row({ unitPrice: -10 }))).toBeNull();
  });

  it('keeps fluid volume separate from weight and rejects unverified evidence', () => {
    const fluid = row({ measurementUnit: 'FL OZ', totalPackageQuantity: 128, unitPrice: 20 });
    expect(normalizePriceObservation(fluid)?.canonicalUnit).toBe('gallon');
    expect(normalizePriceObservation(row({ fieldProvenance: { quantity: { kind: 'OBSERVED', verified: false } } }))).toBeNull();
  });

  it('calculates monthly volume and estimated monthly and annual impact', () => {
    const result = analyzePriceObservations([
      row({ quantity: 12 }),
      row({ invoiceId: 'invoice-b', invoiceDate: new Date('2026-09-01'), unitPrice: 98, quantity: 12 }),
      row({ invoiceId: 'invoice-c', invoiceDate: now, unitPrice: 106.5, quantity: 12 }),
    ], options)[0];
    expect(result.typicalMonthlyQuantity).toBe(15.652);
    expect(result.absoluteChange).toBe(8.5);
    expect(result.estimatedMonthlyImpact).toBe(133.04);
    expect(result.estimatedAnnualImpact).toBe(1596.52);
  });

  it('deduplicates observations and withholds impact for a one-time volume outlier', () => {
    const observations = [
      row({ quantity: 10 }),
      row({ invoiceId: 'invoice-b', invoiceDate: new Date('2026-09-01'), unitPrice: 98, quantity: 10 }),
      row({ invoiceId: 'invoice-c', invoiceDate: now, unitPrice: 106.5, quantity: 100 }),
    ];
    const result = analyzePriceObservations([...observations, observations[2]], options)[0];
    expect(result.observationCount).toBe(3);
    expect(result.estimatedMonthlyImpact).toBeNull();
  });

  it('never compares observations in different currencies', () => {
    expect(analyzePriceObservations([
      row({ currency: 'USD' }),
      row({ invoiceId: 'invoice-b', invoiceDate: now, currency: 'CAD', unitPrice: 98 }),
    ], options)).toEqual([]);
  });

  it('rejects missing or unverified currency instead of assuming USD', () => {
    expect(analyzePriceObservations([
      row({ currency: null }),
      row({ invoiceId: 'invoice-b', invoiceDate: now, unitPrice: 98 }),
    ], options)).toEqual([]);
    expect(analyzePriceObservations([
      row({ currencyProvenance: { currency: { kind: 'OBSERVED', verified: false } } }),
      row({ invoiceId: 'invoice-b', invoiceDate: now, unitPrice: 98 }),
    ], options)).toEqual([]);
  });

  it('supports decreases and excludes missing quantity', () => {
    const result = analyzePriceObservations([
      row({ unitPrice: 55 }),
      row({ invoiceId: 'invoice-b', invoiceDate: now, unitPrice: 49 }),
    ], options)[0];
    expect(result.percentageChange).toBe(-10.91);
    expect(result.estimatedMonthlyImpact).toBeNull();
    expect(analyzePriceObservations([
      row({ quantity: null }),
      row({ invoiceId: 'invoice-b', invoiceDate: now, quantity: null }),
    ], options)).toEqual([]);
  });

  it('excludes zero and missing prices instead of producing NaN or Infinity', () => {
    const result = analyzePriceObservations([
      row({ unitPrice: 0 }),
      row({ invoiceId: 'invoice-b', invoiceDate: now, unitPrice: null }),
    ], options);
    expect(result).toEqual([]);
  });
});

describe('PriceIntelligenceService', () => {
  const location = { id: '00000000-0000-4000-8000-000000000002', organizationId: 'org-a' };
  const invoice = (id: string, vendorId: string, date: string) => ({ id, vendorId, invoiceDate: new Date(date) });
  const line = (id: string, price: number, date: string, vendorId = 'vendor-a', description = 'Chicken') => ({
    id,
    organizationId: 'org-a',
    restaurantLocationId: location.id,
    lineNumber: 1,
    rawDescription: description,
    normalizedName: null,
    sku: description,
    quantity: { toString: () => '12' },
    unit: 'CASE',
    packSize: '1 EA',
    measurementUnit: 'EA',
    totalPackageQuantity: { toString: () => '1' },
    unitPrice: { toString: () => String(price) },
    extendedPrice: null,
    productAttributes: null,
    fieldProvenance: Object.fromEntries(['rawDescription', 'sku', 'quantity', 'unit', 'packSize', 'unitPrice'].map((field) => [field, { kind: 'OBSERVED', verified: true }])),
    productGroupMemberships: [],
    invoice: {
      ...invoice(`invoice-${id}`, vendorId, date),
      currency: 'USD',
      fieldProvenance: { currency: { kind: 'OBSERVED', verified: true } },
    },
  });

  function setup(lines: any[], requireMember = jest.fn()) {
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue(location) },
      invoiceLineItem: { findMany: jest.fn().mockResolvedValue(lines) },
      vendor: { findMany: jest.fn().mockResolvedValue([{ id: 'vendor-a', name: 'Sysco' }]) },
    };
    const service = new PriceIntelligenceService(
      prisma,
      { requireMember } as any,
      { get: jest.fn((key: string) => key.includes('PERCENT') ? '5' : '.5') } as any,
    );
    return { service, prisma, requireMember };
  }

  it('queries only reviewed invoices in the authorized organization and location', async () => {
    const { service, prisma, requireMember } = setup([
      line('one', 91, '2026-08-01'),
      line('two', 106.5, '2026-10-01'),
    ]);
    await service.changes('user-a', { restaurantLocationId: location.id, lookbackDays: 90, sort: PriceChangeSort.LARGEST_PERCENT_INCREASE });
    expect(requireMember).toHaveBeenCalledWith('user-a', 'org-a');
    expect(prisma.invoiceLineItem.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({
        organizationId: 'org-a',
        restaurantLocationId: location.id,
        OR: [
          { unitPrice: { not: null } },
          { extendedPrice: { not: null } },
        ],
        invoice: expect.objectContaining({ reviewStatus: 'REVIEWED' }),
      }),
    }));
  });

  it('applies significance threshold, direction filtering, and deterministic sorting', async () => {
    const { service } = setup([
      line('a1', 100, '2026-08-01', 'vendor-a', 'Chicken'),
      line('a2', 110, '2026-10-01', 'vendor-a', 'Chicken'),
      line('b1', 50, '2026-08-02', 'vendor-a', 'Beverage'),
      line('b2', 49, '2026-10-02', 'vendor-a', 'Beverage'),
      line('c1', 55, '2026-08-03', 'vendor-a', 'Produce'),
      line('c2', 49, '2026-10-03', 'vendor-a', 'Produce'),
    ]);
    const result = await service.changes('user-a', { restaurantLocationId: location.id, lookbackDays: 90, sort: PriceChangeSort.MOST_RECENT, direction: PriceChangeDirection.DECREASE });
    expect(result.items.map((item) => item.displayName)).toEqual(['Produce']);
  });

  it('does not query price history when tenant authorization fails', async () => {
    const denied = jest.fn().mockRejectedValue(new ForbiddenException());
    const { service, prisma } = setup([], denied);
    await expect(service.changes('other-user', { restaurantLocationId: location.id, lookbackDays: 90, sort: PriceChangeSort.VENDOR })).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.invoiceLineItem.findMany).not.toHaveBeenCalled();
  });

  it('returns traceable history for the requested opaque item key', async () => {
    const { service } = setup([
      line('one', 91, '2026-08-01'),
      line('two', 106.5, '2026-10-01'),
    ]);
    const changes = await service.changes('user-a', { restaurantLocationId: location.id, lookbackDays: 90, sort: PriceChangeSort.VENDOR });
    const history = await service.history('user-a', changes.items[0].itemKey, { restaurantLocationId: location.id, lookbackDays: 90 });
    expect(history.history).toEqual([
      expect.objectContaining({ invoiceId: 'invoice-one', unitPrice: 91 }),
      expect.objectContaining({ invoiceId: 'invoice-two', unitPrice: 106.5 }),
    ]);
  });
});
