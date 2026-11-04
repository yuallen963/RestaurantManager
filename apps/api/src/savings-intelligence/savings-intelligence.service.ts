import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InvoiceDuplicateResolution, Prisma, ProductMatchStatus, ReviewStatus } from '@prisma/client';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { normalizePriceObservation, priceEligibilityReason, TrustedPriceObservation } from '../price-intelligence/price-intelligence.service';
import { PrismaService } from '../prisma.service';
import { SavingsOpportunitiesQuery } from './dto';

export interface SavingsObservation {
  productGroupId: string;
  productName: string;
  vendorId: string;
  vendorName: string;
  invoiceId: string;
  lineItemId: string;
  date: Date;
  unit: 'lb' | 'gallon' | 'each';
  currency: 'USD';
  packSize: string;
  normalizedUnitPrice: Prisma.Decimal | number | string;
  normalizedQuantity: Prisma.Decimal | number | string;
}

export interface SavingsThresholds {
  minimumPercentageDifference: number;
  minimumMonthlySavings: number;
}

const decimal = (value: Prisma.Decimal | number | string) => value instanceof Prisma.Decimal ? value : new Prisma.Decimal(value.toString());
const rounded = (value: Prisma.Decimal, places = 2) => Number(value.toFixed(places));
const canonical = (value: string | null | undefined) => (value ?? '').trim().toUpperCase().replace(/[^A-Z0-9]+/g, ' ').replace(/\s+/g, ' ');
const attributeKeys = ['brand', 'condition', 'bone', 'skin', 'organic', 'grade', 'cut', 'size'] as const;
function attributes(value: unknown) {
  const record = value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
  return attributeKeys.map((key) => `${key}:${canonical(String(record[key] ?? ''))}`).join('|');
}
function verifiedField(value: unknown, field: string) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const entry = (value as Record<string, unknown>)[field];
  return Boolean(entry && typeof entry === 'object' && (entry as { verified?: boolean; kind?: string }).verified === true
    && ['OBSERVED', 'CALCULATED'].includes((entry as { kind?: string }).kind ?? ''));
}

export function calculateSavingsOpportunities(observations: SavingsObservation[], lookbackDays: number, thresholds: SavingsThresholds) {
  const byGroup = new Map<string, SavingsObservation[]>();
  const seen = new Set<string>();
  for (const observation of observations) {
    const key = `${observation.productGroupId}|${observation.lineItemId}`;
    if (seen.has(key)) continue;
    seen.add(key);
    byGroup.set(observation.productGroupId, [...(byGroup.get(observation.productGroupId) ?? []), observation]);
  }
  const items = [];
  let insufficientHistoryGroups = 0;
  let incompatibleGroups = 0;
  for (const [productGroupId, rows] of byGroup) {
    const compatible = rows.filter((row) => decimal(row.normalizedUnitPrice).gt(0) && decimal(row.normalizedQuantity).gt(0));
    if (compatible.length < 2) continue;
    compatible.sort((a, b) => b.date.getTime() - a.date.getTime() || a.invoiceId.localeCompare(b.invoiceId));
    const current = compatible[0];
    const sameBasis = compatible.filter((row) => row.unit === current.unit && row.currency === current.currency);
    const latestByVendor = new Map<string, SavingsObservation>();
    for (const row of sameBasis) if (!latestByVendor.has(row.vendorId)) latestByVendor.set(row.vendorId, row);
    if (latestByVendor.size < 2) { incompatibleGroups++; continue; }
    const alternatives = [...latestByVendor.values()].filter((row) => row.vendorId !== current.vendorId).sort((a, b) => decimal(a.normalizedUnitPrice).cmp(decimal(b.normalizedUnitPrice)) || b.date.getTime() - a.date.getTime() || a.vendorId.localeCompare(b.vendorId));
    const lower = alternatives[0];
    if (!lower || decimal(lower.normalizedUnitPrice).gte(decimal(current.normalizedUnitPrice))) continue;
    const observedDays = Math.max(1, (current.date.getTime() - sameBasis.at(-1)!.date.getTime()) / 86400000 + 1);
    const quantities = sameBasis.map((row) => decimal(row.normalizedQuantity)).sort((a, b) => a.comparedTo(b));
    const median = quantities[Math.floor(quantities.length / 2)];
    if (sameBasis.length < 3 || observedDays < 28 || quantities.at(-1)!.gt(median.mul(3))) {
      insufficientHistoryGroups++;
      continue;
    }
    const absoluteDifference = decimal(current.normalizedUnitPrice).sub(decimal(lower.normalizedUnitPrice));
    const percentageDifference = absoluteDifference.dividedBy(decimal(current.normalizedUnitPrice)).times(100);
    const typicalMonthlyQuantity = sameBasis.reduce((sum, row) => sum.add(decimal(row.normalizedQuantity)), new Prisma.Decimal(0)).times(30).dividedBy(observedDays);
    const estimatedMonthlySavings = absoluteDifference.mul(typicalMonthlyQuantity);
    if (percentageDifference.lt(thresholds.minimumPercentageDifference) || estimatedMonthlySavings.lt(thresholds.minimumMonthlySavings)) continue;
    items.push({
      productGroupId,
      productName: current.productName,
      currentVendor: { id: current.vendorId, name: current.vendorName, unitPrice: rounded(decimal(current.normalizedUnitPrice)) },
      lowerCostVendor: { id: lower.vendorId, name: lower.vendorName, unitPrice: rounded(decimal(lower.normalizedUnitPrice)) },
      unit: current.unit,
      currency: current.currency,
      packSize: current.packSize,
      absoluteDifference: rounded(absoluteDifference),
      percentageDifference: rounded(percentageDifference),
      typicalMonthlyQuantity: rounded(typicalMonthlyQuantity, 3),
      estimatedMonthlySavings: rounded(estimatedMonthlySavings),
      estimatedAnnualSavings: rounded(estimatedMonthlySavings.times(12)),
      latestHigherPriceDate: current.date.toISOString(),
      latestLowerPriceDate: lower.date.toISOString(),
      evidence: sameBasis.map((row) => ({ invoiceId: row.invoiceId, vendorId: row.vendorId, vendorName: row.vendorName, date: row.date.toISOString(), unitPrice: rounded(decimal(row.normalizedUnitPrice)), quantity: rounded(decimal(row.normalizedQuantity), 3) })),
    });
  }
  items.sort((a, b) => b.estimatedMonthlySavings - a.estimatedMonthlySavings || b.percentageDifference - a.percentageDifference || new Date(b.latestHigherPriceDate).getTime() - new Date(a.latestHigherPriceDate).getTime() || a.productGroupId.localeCompare(b.productGroupId));
  return {
    summary: { opportunityCount: items.length, estimatedMonthlySavings: rounded(items.reduce((sum, item) => sum.add(decimal(item.estimatedMonthlySavings)), new Prisma.Decimal(0))), estimatedAnnualSavings: rounded(items.reduce((sum, item) => sum.add(decimal(item.estimatedAnnualSavings)), new Prisma.Decimal(0))) },
    items,
    lookbackDays,
    eligibility: { insufficientHistoryGroups, incompatibleGroups },
  };
}

@Injectable()
export class SavingsIntelligenceService {
  constructor(private readonly prisma: PrismaService, private readonly access: OrganizationAccessService, private readonly config: ConfigService) {}

  private threshold(name: string, fallback: number) {
    const value = Number(this.config.get<string>(name) ?? fallback);
    return Number.isFinite(value) && value >= 0 ? value : fallback;
  }

  async get(userId: string, query: SavingsOpportunitiesQuery) {
    const location = await this.prisma.restaurantLocation.findUnique({ where: { id: query.restaurantLocationId } });
    if (!location) throw new BadRequestException('Location not found');
    await this.access.requireMember(userId, location.organizationId);
    const start = new Date();
    start.setUTCDate(start.getUTCDate() - query.lookbackDays);
    const groups = await this.prisma.productGroup.findMany({
      where: { organizationId: location.organizationId, restaurantLocationId: location.id, decisions: { some: { status: ProductMatchStatus.CONFIRMED } } },
      include: { members: { where: { confirmed: true }, include: { vendor: { select: { id: true, name: true } }, invoiceLineItem: true } } },
    });
    if (!groups.length) { const empty = calculateSavingsOpportunities([], query.lookbackDays, { minimumPercentageDifference: 5, minimumMonthlySavings: 25 }); return { ...empty, eligibility: { ...empty.eligibility, excludedObservations: {} as Record<string, number> } }; }
    const vendorIds = [...new Set(groups.flatMap((group) => group.members.map((member) => member.vendorId)))];
    const lines = await this.prisma.invoiceLineItem.findMany({
      where: { organizationId: location.organizationId, restaurantLocationId: location.id, OR: [{ unitPrice: { not: null } }, { extendedPrice: { not: null } }], quantity: { not: null }, invoice: { reviewStatus: ReviewStatus.REVIEWED, duplicateResolution: { not: InvoiceDuplicateResolution.DUPLICATE }, vendorId: { in: vendorIds }, invoiceDate: { gte: start, lte: new Date() } } },
      include: { invoice: { select: { id: true, vendorId: true, invoiceDate: true, currency: true, fieldProvenance: true } } },
      orderBy: { invoice: { invoiceDate: 'desc' } },
      take: 1000,
    });
    const observations: SavingsObservation[] = [];
    const excludedObservations: Record<string, number> = {};
    const exclude = (reason: string) => { excludedObservations[reason] = (excludedObservations[reason] ?? 0) + 1; };
    for (const group of groups) {
      for (const member of group.members) {
        const exemplar = member.invoiceLineItem;
        for (const line of lines) {
          if (line.invoice.vendorId !== member.vendorId || !line.invoice.invoiceDate || line.quantity == null) continue;
          const sameProduct = line.id === exemplar.id || Boolean(exemplar.sku && line.sku && verifiedField(exemplar.fieldProvenance, 'sku') && verifiedField(line.fieldProvenance, 'sku') && canonical(exemplar.sku) === canonical(line.sku));
          if (!sameProduct) continue;
          if (attributes(exemplar.productAttributes) !== attributes(line.productAttributes)) { exclude('PRODUCT_ATTRIBUTES_DIFFER'); continue; }
          const candidate: TrustedPriceObservation = { invoiceId: line.invoice.id, invoiceDate: line.invoice.invoiceDate, lineNumber: line.lineNumber, vendorId: member.vendor.id, vendorName: member.vendor.name, rawDescription: line.rawDescription, sku: line.sku, unit: line.unit, packSize: line.packSize, unitPrice: line.unitPrice, extendedPrice: line.extendedPrice, quantity: line.quantity, measurementUnit: line.measurementUnit, totalPackageQuantity: line.totalPackageQuantity, productAttributes: line.productAttributes, fieldProvenance: line.fieldProvenance, currency: line.invoice.currency, currencyProvenance: line.invoice.fieldProvenance, productGroupId: group.id };
          const reason = priceEligibilityReason(candidate);
          if (reason) { exclude(reason); continue; }
          if (line.packSize && !verifiedField(line.fieldProvenance, 'packSize')) { exclude('UNVERIFIED_PACKAGE'); continue; }
          if (line.invoice.currency !== 'USD') { exclude('UNSUPPORTED_CURRENCY'); continue; }
          const normalized = normalizePriceObservation(candidate)!;
          observations.push({ productGroupId: group.id, productName: group.displayName, vendorId: member.vendor.id, vendorName: member.vendor.name, invoiceId: line.invoice.id, lineItemId: line.id, date: line.invoice.invoiceDate, unit: normalized.canonicalUnit, currency: 'USD', packSize: line.packSize ?? '', normalizedUnitPrice: normalized.normalizedUnitPrice, normalizedQuantity: normalized.normalizedQuantity });
        }
      }
    }
    const result = calculateSavingsOpportunities(observations, query.lookbackDays, {
      minimumPercentageDifference: this.threshold('SAVINGS_MINIMUM_PERCENTAGE_DIFFERENCE', 5),
      minimumMonthlySavings: this.threshold('SAVINGS_MINIMUM_MONTHLY_AMOUNT', 25),
    });
    return { ...result, eligibility: { ...result.eligibility, excludedObservations } };
  }
}
