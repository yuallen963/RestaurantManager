import { Prisma } from '@prisma/client';
import { duplicateCandidateKind, distinctReviewedKey, invoiceIdentity, InvoiceIdentityFields } from '../src/invoices/duplicate-identity';
import { parsePackageSize } from '../src/invoices/extraction.processor';
import { reviewDiscrepancies } from '../src/invoices/review-reconciliation';
import { normalizePriceObservation } from '../src/price-intelligence/price-intelligence.service';

const invoice = (overrides: Partial<InvoiceIdentityFields> = {}): InvoiceIdentityFields => ({
  id: 'invoice-a', organizationId: 'org-a', restaurantLocationId: 'location-a', vendorId: 'vendor-a',
  invoiceNumber: ' INV-100 ', invoiceDate: new Date('2026-10-14T00:00:00.000Z'), currency: 'USD', total: new Prisma.Decimal('120.00'),
  attachmentHash: 'file-a', ...overrides,
});

describe('invoice duplicate identity', () => {
  it('recognizes identical files and rescanned possible duplicates', () => {
    expect(duplicateCandidateKind(invoice(), invoice({ id: 'b', attachmentHash: 'file-a' }))).toBe('DEFINITE');
    expect(duplicateCandidateKind(invoice(), invoice({ id: 'b', invoiceNumber: 'inv 100', attachmentHash: 'different-file' }))).toBe('POSSIBLE');
  });
  it('keeps distinct dates, vendors, locations and tenants separate', () => {
    for (const change of [
      { invoiceDate: new Date('2026-11-14') }, { vendorId: 'vendor-b' },
      { restaurantLocationId: 'location-b' }, { organizationId: 'org-b' },
    ]) expect(duplicateCandidateKind(invoice(), invoice({ id: 'b', attachmentHash: 'different', ...change }))).toBeNull();
  });
  it('conservatively claims same-day purchases with different or missing invoice numbers', () => {
    const a = invoiceIdentity(invoice())!;
    const b = invoiceIdentity(invoice({ id: 'b', invoiceNumber: null }))!;
    expect(a.claimKey).toBe(b.claimKey);
    expect(a.fingerprint).not.toBe(b.fingerprint);
    expect(distinctReviewedKey(a.claimKey, 'b')).not.toBe(a.claimKey);
    expect(distinctReviewedKey(a.claimKey, 'b')).not.toBe(distinctReviewedKey(a.claimKey, 'c'));
  });
  it('does not invent an identity without a confirmed vendor, date, currency or total', () => {
    for (const change of [{ vendorId: null }, { invoiceDate: null }, { currency: null }, { total: null }])
      expect(invoiceIdentity(invoice(change))).toBeNull();
  });
});

describe('restaurant package normalization', () => {
  it.each([
    ['25 LB BAG', null, null, 'LB', 25], ['10 LB CASE', null, null, 'LB', 10],
    ['35 LB CONTAINER', null, null, 'LB', 35], ['6 x 5 LB', 6, 5, 'LB', 30],
    ['4/1 GAL', 4, 1, 'GAL', 4], ['12 x 16 OZ', 12, 16, 'OZ', 192],
    ['50 LB SACK', null, null, 'LB', 50], ['24 CT CASE', null, null, 'CT', 24],
  ])('parses %s without confusing cases bought with case contents', (raw, count, each, unit, total) => {
    expect(parsePackageSize(raw as string)).toEqual({ packCount: count, packUnitQuantity: each, measurementUnit: unit, totalPackageQuantity: total });
  });
  it.each(['EACH', 'CASE', '6 x CASE', 'ABOUT 25 LB', '0 LB BAG'])('leaves %s ambiguous', (raw) => {
    expect(parsePackageSize(raw)).toBeNull();
  });
  it('normalizes two 6 x 5 LB chicken cases to 60 lb and keeps volume separate', () => {
    const pack = parsePackageSize('6 x 5 LB')!;
    const provenance = { quantity: { kind: 'OBSERVED', verified: true }, extendedPrice: { kind: 'OBSERVED', verified: true } };
    const base = { invoiceId: 'a', invoiceDate: new Date('2026-10-14'), lineNumber: 1, vendorId: 'v', vendorName: 'V', rawDescription: 'Chicken',
      quantity: 2, extendedPrice: 120, measurementUnit: pack.measurementUnit, totalPackageQuantity: pack.totalPackageQuantity, fieldProvenance: provenance };
    const normalized = normalizePriceObservation(base)!;
    expect(normalized.normalizedQuantity.toNumber()).toBe(60);
    expect(normalized.normalizedUnitPrice.toNumber()).toBe(2);
    const oil = parsePackageSize('4/1 GAL')!;
    expect(normalizePriceObservation({ ...base, measurementUnit: oil.measurementUnit, totalPackageQuantity: oil.totalPackageQuantity })!.canonicalUnit).toBe('gallon');
  });
});

describe('review reconciliation with missing charges', () => {
  const amounts = { subtotal: 100, tax: null, otherFees: null, discount: null, total: 100, lines: [{ id: 'line', quantity: 1, unit: 'CASE', unitPrice: 100, extendedPrice: 100 }] };
  it('allows absent optional charges when known amounts agree and does not fill them in', () => {
    expect(reviewDiscrepancies(amounts)).toEqual([]);
    expect(amounts.tax).toBeNull();
  });
  it('treats explicit zero tax and a delivery charge and discount as known values', () => {
    expect(reviewDiscrepancies({ ...amounts, tax: 0, otherFees: 8, discount: 3, total: 105 })).toEqual([]);
    expect(reviewDiscrepancies({ ...amounts, tax: 0, otherFees: 8, discount: 3, total: 106 })).toContainEqual(expect.stringContaining('known charges reconcile'));
  });
  it('derives a missing subtotal only for validation when all line amounts exist', () => {
    expect(reviewDiscrepancies({ ...amounts, subtotal: null })).toEqual([]);
    expect(reviewDiscrepancies({ ...amounts, subtotal: null, lines: [{ ...amounts.lines[0], extendedPrice: null }] })).toContainEqual(expect.stringContaining('subtotal is missing'));
  });
  it('accepts cent-level rounding and rejects larger mismatches', () => {
    expect(reviewDiscrepancies({ ...amounts, subtotal: '100.00', total: '100.01' })).toEqual([]);
    expect(reviewDiscrepancies({ ...amounts, total: '100.02' })).not.toEqual([]);
  });
});
