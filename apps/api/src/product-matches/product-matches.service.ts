import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { ProductMatchConfidence, ProductMatchStatus, ReviewStatus } from '@prisma/client';
import { AuditService } from '../audit.service';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PrismaService } from '../prisma.service';

export interface MatchableProductItem {
  id: string;
  vendorId: string;
  vendorName: string;
  rawDescription: string;
  normalizedName?: string | null;
  unit?: string | null;
  packSize?: string | null;
  sku?: string | null;
}

export interface ProductMatchSuggestion {
  itemA: MatchableProductItem;
  itemB: MatchableProductItem;
  confidence: ProductMatchConfidence;
  reason: string;
}

const aliases: Record<string, string> = {
  CHKN: 'CHICKEN', BRST: 'BREAST', BNLS: 'BONELESS', SKLS: 'SKINLESS',
  'B/S': 'BONELESS SKINLESS', FRZ: 'FROZEN', CS: 'CASE',
};
const packaging = new Set(['LB', 'LBS', 'OZ', 'CASE', 'CS', 'CT', 'EA', 'PK', 'PACK']);
const conflicts = [['BREAST', 'THIGH'], ['FRESH', 'FROZEN'], ['ORGANIC', 'CONVENTIONAL']];

function words(value: string) {
  return value.toUpperCase().replace(/B\/?S/g, ' B/S ').replace(/[^A-Z0-9/]+/g, ' ').trim().split(/\s+/)
    .flatMap((token) => (aliases[token] ?? token).split(' '));
}

function descriptionTokens(item: MatchableProductItem) {
  return new Set(words(item.normalizedName?.trim() || item.rawDescription).filter((token) => !packaging.has(token) && !/^\d+(?:\/\d+)?$/.test(token)));
}

function normalizedUnit(value?: string | null) {
  const unit = words(value ?? '')[0] ?? '';
  return aliases[unit] ?? unit;
}

export function totalWeightPounds(packSize?: string | null) {
  if (!packSize) return null;
  const value = packSize.toUpperCase().replace(/POUNDS?/g, 'LB').replace(/LBS/g, 'LB');
  const multiplied = value.match(/(\d+(?:\.\d+)?)\s*(?:X|\/)\s*(\d+(?:\.\d+)?)\s*LB/);
  if (multiplied) return Number(multiplied[1]) * Number(multiplied[2]);
  const direct = value.match(/(\d+(?:\.\d+)?)\s*LB/);
  return direct ? Number(direct[1]) : null;
}

function incompatibleDescriptors(a: Set<string>, b: Set<string>) {
  return conflicts.some(([left, right]) => (a.has(left) && b.has(right)) || (a.has(right) && b.has(left)));
}

export function compareProductItems(a: MatchableProductItem, b: MatchableProductItem): Omit<ProductMatchSuggestion, 'itemA' | 'itemB'> | null {
  if (a.vendorId === b.vendorId) return null;
  const unitA = normalizedUnit(a.unit);
  const unitB = normalizedUnit(b.unit);
  if (!unitA || !unitB || unitA !== unitB) return null;
  const weightA = totalWeightPounds(a.packSize);
  const weightB = totalWeightPounds(b.packSize);
  if (weightA != null && weightB != null && Math.abs(weightA - weightB) > .01) return null;
  const tokensA = descriptionTokens(a);
  const tokensB = descriptionTokens(b);
  if (incompatibleDescriptors(tokensA, tokensB)) return null;
  const intersection = [...tokensA].filter((token) => tokensB.has(token)).length;
  const union = new Set([...tokensA, ...tokensB]).size;
  const similarity = union ? intersection / union : 0;
  if (intersection < 2 || similarity < .5) return null;
  const strongBasis = weightA != null && weightB != null;
  const confidence = similarity >= .75 && strongBasis ? ProductMatchConfidence.HIGH : similarity >= .6 ? ProductMatchConfidence.MEDIUM : ProductMatchConfidence.LOW;
  return {
    confidence,
    reason: `${Math.round(similarity * 100)}% normalized description overlap; same ${unitA}${strongBasis ? ` and ${weightA} lb total weight` : ''}`,
  };
}

export function generateProductMatchSuggestions(items: MatchableProductItem[]) {
  const buckets = new Map<string, MatchableProductItem[]>();
  for (const item of items) {
    const unit = normalizedUnit(item.unit);
    if (!unit) continue;
    const weight = totalWeightPounds(item.packSize);
    const key = `${unit}|${weight ?? 'UNKNOWN'}`;
    buckets.set(key, [...(buckets.get(key) ?? []), item]);
  }
  const suggestions: ProductMatchSuggestion[] = [];
  for (const bucket of buckets.values()) {
    for (let left = 0; left < bucket.length; left += 1) {
      for (let right = left + 1; right < bucket.length; right += 1) {
        const result = compareProductItems(bucket[left], bucket[right]);
        if (result) suggestions.push({ itemA: bucket[left], itemB: bucket[right], ...result });
      }
    }
  }
  return suggestions;
}

const memberInclude = {
  vendor: { select: { id: true, name: true } },
  invoiceLineItem: { select: { id: true, rawDescription: true, normalizedName: true, unit: true, packSize: true, sku: true } },
} as const;

@Injectable()
export class ProductMatchesService {
  constructor(private readonly prisma: PrismaService, private readonly access: OrganizationAccessService, private readonly audit: AuditService) {}

  private async location(userId: string, restaurantLocationId: string) {
    const location = await this.prisma.restaurantLocation.findUnique({ where: { id: restaurantLocationId } });
    if (!location) throw new BadRequestException('Location not found');
    await this.access.requireMember(userId, location.organizationId);
    return location;
  }

  private async ownedDecision(userId: string, id: string) {
    const decision = await this.prisma.productMatchDecision.findUnique({ where: { id }, include: { candidateLineItemA: { include: { invoice: true } }, candidateLineItemB: { include: { invoice: true } } } });
    if (!decision) throw new NotFoundException('Product match not found');
    await this.access.requireMember(userId, decision.organizationId);
    return decision;
  }

  async candidates(userId: string, restaurantLocationId: string) {
    const location = await this.location(userId, restaurantLocationId);
    const since = new Date();
    since.setUTCDate(since.getUTCDate() - 180);
    const lines = await this.prisma.invoiceLineItem.findMany({
      where: { organizationId: location.organizationId, restaurantLocationId, invoice: { reviewStatus: ReviewStatus.REVIEWED, vendorId: { not: null }, invoiceDate: { gte: since } } },
      include: { invoice: { select: { vendorId: true } } },
      orderBy: { createdAt: 'desc' },
      take: 500,
    });
    const vendorIds = [...new Set(lines.map((line) => line.invoice.vendorId).filter(Boolean) as string[])];
    const vendors = await this.prisma.vendor.findMany({ where: { organizationId: location.organizationId, id: { in: vendorIds } }, select: { id: true, name: true } });
    const names = new Map(vendors.map((vendor) => [vendor.id, vendor.name]));
    const items = lines.flatMap<MatchableProductItem>((line) => {
      const vendorId = line.invoice.vendorId;
      const vendorName = vendorId ? names.get(vendorId) : null;
      return vendorId && vendorName ? [{ id: line.id, vendorId, vendorName, rawDescription: line.rawDescription, normalizedName: line.normalizedName, unit: line.unit, packSize: line.packSize, sku: line.sku }] : [];
    });
    // The query is newest-first. Keep only the latest observation of the same
    // vendor product/basis so invoice history cannot create duplicate reviews.
    const latestProducts = new Map<string, MatchableProductItem>();
    for (const item of items) {
      const signature = `${item.vendorId}|${normalizedUnit(item.unit)}|${totalWeightPounds(item.packSize) ?? 'UNKNOWN'}|${[...descriptionTokens(item)].sort().join('-')}`;
      if (!latestProducts.has(signature)) latestProducts.set(signature, item);
    }
    const suggestions = generateProductMatchSuggestions([...latestProducts.values()]).map((suggestion) => {
      const [itemA, itemB] = [suggestion.itemA, suggestion.itemB].sort((a, b) => a.id.localeCompare(b.id));
      return { ...suggestion, itemA, itemB };
    });
    if (suggestions.length) await this.prisma.productMatchDecision.createMany({ data: suggestions.map((match) => ({ organizationId: location.organizationId, restaurantLocationId, candidateLineItemAId: match.itemA.id, candidateLineItemBId: match.itemB.id, confidence: match.confidence, reason: match.reason })), skipDuplicates: true });
    return this.prisma.productMatchDecision.findMany({ where: { organizationId: location.organizationId, restaurantLocationId, status: ProductMatchStatus.PENDING }, include: { candidateLineItemA: { include: { invoice: { include: { vendor: { select: { id: true, name: true } } } } } }, candidateLineItemB: { include: { invoice: { include: { vendor: { select: { id: true, name: true } } } } } } }, orderBy: [{ confidence: 'asc' }, { createdAt: 'desc' }] });
  }

  async confirm(userId: string, id: string) {
    const decision = await this.ownedDecision(userId, id);
    if (decision.status !== ProductMatchStatus.PENDING) throw new BadRequestException('Product match was already reviewed');
    const vendorA = decision.candidateLineItemA.invoice.vendorId;
    const vendorB = decision.candidateLineItemB.invoice.vendorId;
    if (!vendorA || !vendorB || vendorA === vendorB) throw new BadRequestException('Candidates must belong to different vendors');
    const displayName = decision.candidateLineItemA.normalizedName?.trim() || decision.candidateLineItemB.normalizedName?.trim() || decision.candidateLineItemA.rawDescription;
    const group = await this.prisma.$transaction(async (tx) => {
      const created = await tx.productGroup.create({ data: { organizationId: decision.organizationId, restaurantLocationId: decision.restaurantLocationId, displayName } });
      await tx.productGroupMember.createMany({ data: [{ productGroupId: created.id, invoiceLineItemId: decision.candidateLineItemAId, vendorId: vendorA, confirmed: true }, { productGroupId: created.id, invoiceLineItemId: decision.candidateLineItemBId, vendorId: vendorB, confirmed: true }] });
      await tx.productMatchDecision.update({ where: { id }, data: { status: ProductMatchStatus.CONFIRMED, productGroupId: created.id, reviewedByUserId: userId, reviewedAt: new Date() } });
      return created;
    });
    await this.audit.log({ userId, organizationId: decision.organizationId, action: 'product-match.confirmed', entityType: 'ProductMatchDecision', entityId: id, metadata: { productGroupId: group.id, restaurantLocationId: decision.restaurantLocationId } });
    return this.group(userId, group.id);
  }

  async reject(userId: string, id: string) {
    const decision = await this.ownedDecision(userId, id);
    if (decision.status !== ProductMatchStatus.PENDING) throw new BadRequestException('Product match was already reviewed');
    const result = await this.prisma.productMatchDecision.update({ where: { id }, data: { status: ProductMatchStatus.REJECTED, reviewedByUserId: userId, reviewedAt: new Date() } });
    await this.audit.log({ userId, organizationId: decision.organizationId, action: 'product-match.rejected', entityType: 'ProductMatchDecision', entityId: id, metadata: { restaurantLocationId: decision.restaurantLocationId } });
    return result;
  }

  async groups(userId: string, restaurantLocationId: string) {
    const location = await this.location(userId, restaurantLocationId);
    return this.prisma.productGroup.findMany({ where: { organizationId: location.organizationId, restaurantLocationId }, include: { members: { include: memberInclude } }, orderBy: { displayName: 'asc' } });
  }

  async group(userId: string, id: string) {
    const group = await this.prisma.productGroup.findUnique({ where: { id }, include: { members: { include: memberInclude } } });
    if (!group) throw new NotFoundException('Product group not found');
    await this.access.requireMember(userId, group.organizationId);
    return group;
  }

  async rename(userId: string, id: string, displayName: string) {
    const group = await this.group(userId, id);
    const updated = await this.prisma.productGroup.update({ where: { id }, data: { displayName: displayName.trim() }, include: { members: { include: memberInclude } } });
    await this.audit.log({ userId, organizationId: group.organizationId, action: 'product-group.renamed', entityType: 'ProductGroup', entityId: id, metadata: { restaurantLocationId: group.restaurantLocationId } });
    return updated;
  }
}
