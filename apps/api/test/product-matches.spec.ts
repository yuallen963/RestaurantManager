import { ForbiddenException } from '@nestjs/common';
import { ProductMatchConfidence, ProductMatchStatus } from '@prisma/client';
import { compareProductItems, generateProductMatchSuggestions, MatchableProductItem, ProductMatchesService } from '../src/product-matches/product-matches.service';

const item = (overrides: Partial<MatchableProductItem> = {}): MatchableProductItem => ({
  id: 'item-a', vendorId: 'vendor-a', vendorName: 'Sysco', rawDescription: 'CHKN BRST BNLS SKLS 4/10 LB', unit: 'CASE', packSize: '4 x 10 lb', ...overrides,
});

describe('deterministic cross-vendor product matching', () => {
  it('generates an obvious chicken match with high confidence', () => {
    const result = compareProductItems(item(), item({ id: 'item-b', vendorId: 'vendor-b', vendorName: 'US Foods', rawDescription: 'CHICKEN BREAST B/S 40LB', packSize: '40 lb' }));
    expect(result).toMatchObject({ confidence: ProductMatchConfidence.HIGH });
  });

  it.each([
    [{ unit: 'CASE' }, { unit: 'LB' }],
    [{ packSize: '4 x 10 lb' }, { packSize: '2 x 10 lb' }],
  ])('excludes incompatible unit or pack size', (a, b) => {
    expect(compareProductItems(item(a), item({ id: 'item-b', vendorId: 'vendor-b', ...b }))).toBeNull();
  });

  it('excludes a clearly different product', () => {
    expect(generateProductMatchSuggestions([item(), item({ id: 'item-b', vendorId: 'vendor-b', rawDescription: 'FROZEN CHICKEN THIGH', packSize: '40 lb' })])).toEqual([]);
  });
});

describe('ProductMatchesService', () => {
  const location = { id: '00000000-0000-4000-8000-000000000002', organizationId: 'org-a' };
  const decision = {
    id: 'decision-a', organizationId: 'org-a', restaurantLocationId: location.id, status: ProductMatchStatus.PENDING,
    candidateLineItemAId: 'item-a', candidateLineItemBId: 'item-b',
    candidateLineItemA: { normalizedName: 'Boneless Skinless Chicken Breast', rawDescription: 'Chicken A', invoice: { vendorId: 'vendor-a' } },
    candidateLineItemB: { normalizedName: null, rawDescription: 'Chicken B', invoice: { vendorId: 'vendor-b' } },
  };

  function setup(requireMember = jest.fn()) {
    const tx = {
      productGroup: { create: jest.fn().mockResolvedValue({ id: 'group-a', organizationId: 'org-a', restaurantLocationId: location.id, displayName: 'Boneless Skinless Chicken Breast' }) },
      productGroupMember: { createMany: jest.fn().mockResolvedValue({ count: 2 }) },
      productMatchDecision: { update: jest.fn().mockResolvedValue({}) },
    };
    const prisma: any = {
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue(location) },
      invoiceLineItem: { findMany: jest.fn().mockResolvedValue([]) },
      vendor: { findMany: jest.fn().mockResolvedValue([]) },
      productMatchDecision: { createMany: jest.fn(), findMany: jest.fn().mockResolvedValue([]), findUnique: jest.fn().mockResolvedValue(decision), update: jest.fn().mockResolvedValue({ ...decision, status: ProductMatchStatus.REJECTED }) },
      productGroup: { findMany: jest.fn().mockResolvedValue([]), findUnique: jest.fn().mockResolvedValue({ id: 'group-a', organizationId: 'org-a', restaurantLocationId: location.id, displayName: 'Boneless Skinless Chicken Breast', members: [] }), update: jest.fn() },
      $transaction: jest.fn((callback) => callback(tx)),
    };
    const audit = { log: jest.fn().mockResolvedValue({}) };
    return { service: new ProductMatchesService(prisma, { requireMember } as any, audit as any), prisma, tx, requireMember };
  }

  it('does not resurface rejected pairs because only pending decisions are returned', async () => {
    const { service, prisma } = setup();
    await service.candidates('user-a', location.id);
    expect(prisma.productMatchDecision.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ status: ProductMatchStatus.PENDING }) }));
  });

  it('confirms a pair by creating a trusted group with both vendor items', async () => {
    const { service, tx } = setup();
    const result = await service.confirm('user-a', 'decision-a');
    expect(tx.productGroupMember.createMany).toHaveBeenCalledWith({ data: expect.arrayContaining([expect.objectContaining({ invoiceLineItemId: 'item-a', confirmed: true }), expect.objectContaining({ invoiceLineItemId: 'item-b', confirmed: true })]) });
    expect(tx.productMatchDecision.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ status: ProductMatchStatus.CONFIRMED, productGroupId: 'group-a' }) }));
    expect(result.id).toBe('group-a');
  });

  it('persists rejection', async () => {
    const { service, prisma } = setup();
    await service.reject('user-a', 'decision-a');
    expect(prisma.productMatchDecision.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ status: ProductMatchStatus.REJECTED, reviewedByUserId: 'user-a' }) }));
  });

  it('enforces tenant membership before querying location candidates', async () => {
    const denied = jest.fn().mockRejectedValue(new ForbiddenException());
    const { service, prisma } = setup(denied);
    await expect(service.candidates('other-user', location.id)).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.invoiceLineItem.findMany).not.toHaveBeenCalled();
  });
});
