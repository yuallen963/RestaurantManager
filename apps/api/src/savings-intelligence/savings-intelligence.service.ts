import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ProductMatchStatus, ReviewStatus } from '@prisma/client';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { totalWeightPounds } from '../product-matches/product-matches.service';
import { PrismaService } from '../prisma.service';
import { SavingsOpportunitiesQuery } from './dto';

export interface SavingsObservation {
  productGroupId: string;
  productName: string;
  vendorId: string;
  vendorName: string;
  invoiceId: string;
  date: Date;
  unit: string;
  packSize: string;
  totalWeightPounds: number;
  unitPrice: number;
  quantity: number;
}

export interface SavingsThresholds {
  minimumPercentageDifference: number;
  minimumMonthlySavings: number;
}

const rounded = (value: number, places = 2) => Number(value.toFixed(places));
const canonical = (value: string | null | undefined) => (value ?? '').trim().toUpperCase().replace(/[^A-Z0-9]+/g, ' ').replace(/\s+/g, ' ');

export function calculateSavingsOpportunities(observations: SavingsObservation[], lookbackDays: number, thresholds: SavingsThresholds) {
  const byGroup = new Map<string, SavingsObservation[]>();
  for (const observation of observations) byGroup.set(observation.productGroupId, [...(byGroup.get(observation.productGroupId) ?? []), observation]);
  const items = [];
  for (const [productGroupId, rows] of byGroup) {
    const compatible = rows.filter((row) => row.unitPrice > 0 && row.quantity >= 0 && row.unit && row.packSize && row.totalWeightPounds > 0);
    if (compatible.length < 2) continue;
    compatible.sort((a, b) => b.date.getTime() - a.date.getTime() || a.invoiceId.localeCompare(b.invoiceId));
    const current = compatible[0];
    const sameBasis = compatible.filter((row) => canonical(row.unit) === canonical(current.unit) && Math.abs(row.totalWeightPounds - current.totalWeightPounds) <= .01);
    const latestByVendor = new Map<string, SavingsObservation>();
    for (const row of sameBasis) if (!latestByVendor.has(row.vendorId)) latestByVendor.set(row.vendorId, row);
    if (latestByVendor.size < 2) continue;
    const alternatives = [...latestByVendor.values()].filter((row) => row.vendorId !== current.vendorId).sort((a, b) => a.unitPrice - b.unitPrice || b.date.getTime() - a.date.getTime() || a.vendorId.localeCompare(b.vendorId));
    const lower = alternatives[0];
    if (!lower || lower.unitPrice >= current.unitPrice) continue;
    const absoluteDifference = current.unitPrice - lower.unitPrice;
    const percentageDifference = absoluteDifference / current.unitPrice * 100;
    const typicalMonthlyQuantity = sameBasis.reduce((sum, row) => sum + row.quantity, 0) * 30 / lookbackDays;
    if (!Number.isFinite(typicalMonthlyQuantity) || typicalMonthlyQuantity <= 0) continue;
    const estimatedMonthlySavings = absoluteDifference * typicalMonthlyQuantity;
    if (percentageDifference < thresholds.minimumPercentageDifference || estimatedMonthlySavings < thresholds.minimumMonthlySavings) continue;
    items.push({
      productGroupId,
      productName: current.productName,
      currentVendor: { id: current.vendorId, name: current.vendorName, unitPrice: rounded(current.unitPrice) },
      lowerCostVendor: { id: lower.vendorId, name: lower.vendorName, unitPrice: rounded(lower.unitPrice) },
      unit: current.unit,
      packSize: current.packSize,
      absoluteDifference: rounded(absoluteDifference),
      percentageDifference: rounded(percentageDifference),
      typicalMonthlyQuantity: rounded(typicalMonthlyQuantity, 3),
      estimatedMonthlySavings: rounded(estimatedMonthlySavings),
      estimatedAnnualSavings: rounded(estimatedMonthlySavings * 12),
      latestHigherPriceDate: current.date.toISOString(),
      latestLowerPriceDate: lower.date.toISOString(),
      evidence: sameBasis.map((row) => ({ invoiceId: row.invoiceId, vendorId: row.vendorId, vendorName: row.vendorName, date: row.date.toISOString(), unitPrice: rounded(row.unitPrice), quantity: rounded(row.quantity, 3) })),
    });
  }
  items.sort((a, b) => b.estimatedMonthlySavings - a.estimatedMonthlySavings || b.percentageDifference - a.percentageDifference || new Date(b.latestHigherPriceDate).getTime() - new Date(a.latestHigherPriceDate).getTime() || a.productGroupId.localeCompare(b.productGroupId));
  return {
    summary: { opportunityCount: items.length, estimatedMonthlySavings: rounded(items.reduce((sum, item) => sum + item.estimatedMonthlySavings, 0)), estimatedAnnualSavings: rounded(items.reduce((sum, item) => sum + item.estimatedAnnualSavings, 0)) },
    items,
    lookbackDays,
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
    if (!groups.length) return calculateSavingsOpportunities([], query.lookbackDays, { minimumPercentageDifference: 5, minimumMonthlySavings: 25 });
    const vendorIds = [...new Set(groups.flatMap((group) => group.members.map((member) => member.vendorId)))];
    const lines = await this.prisma.invoiceLineItem.findMany({
      where: { organizationId: location.organizationId, restaurantLocationId: location.id, unitPrice: { not: null }, quantity: { not: null }, invoice: { reviewStatus: ReviewStatus.REVIEWED, vendorId: { in: vendorIds }, invoiceDate: { gte: start, lte: new Date() } } },
      include: { invoice: { select: { id: true, vendorId: true, invoiceDate: true } } },
      orderBy: { invoice: { invoiceDate: 'desc' } },
      take: 1000,
    });
    const observations: SavingsObservation[] = [];
    for (const group of groups) {
      for (const member of group.members) {
        const exemplar = member.invoiceLineItem;
        const exemplarWeight = totalWeightPounds(exemplar.packSize);
        if (!exemplar.unit || !exemplar.packSize || exemplarWeight == null) continue;
        for (const line of lines) {
          if (line.invoice.vendorId !== member.vendorId || !line.invoice.invoiceDate || line.unitPrice == null || line.quantity == null) continue;
          const sameProduct = (exemplar.sku && line.sku && canonical(exemplar.sku) === canonical(line.sku)) || (exemplar.normalizedName && line.normalizedName && canonical(exemplar.normalizedName) === canonical(line.normalizedName)) || canonical(exemplar.rawDescription) === canonical(line.rawDescription);
          const weight = totalWeightPounds(line.packSize);
          if (!sameProduct || canonical(line.unit) !== canonical(exemplar.unit) || weight == null || Math.abs(weight - exemplarWeight) > .01) continue;
          observations.push({ productGroupId: group.id, productName: group.displayName, vendorId: member.vendor.id, vendorName: member.vendor.name, invoiceId: line.invoice.id, date: line.invoice.invoiceDate, unit: line.unit!, packSize: line.packSize!, totalWeightPounds: weight, unitPrice: Number(line.unitPrice.toString()), quantity: Number(line.quantity.toString()) });
        }
      }
    }
    return calculateSavingsOpportunities(observations, query.lookbackDays, {
      minimumPercentageDifference: this.threshold('SAVINGS_MINIMUM_PERCENTAGE_DIFFERENCE', 5),
      minimumMonthlySavings: this.threshold('SAVINGS_MINIMUM_MONTHLY_AMOUNT', 25),
    });
  }
}
