import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash } from 'crypto';
import { ReviewStatus } from '@prisma/client';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PrismaService } from '../prisma.service';
import { PriceChangeDirection, PriceChangeSort, PriceHistoryQuery, PriceIntelligenceQuery } from './dto';

export interface TrustedPriceObservation {
  invoiceId: string;
  invoiceDate: Date;
  lineNumber: number;
  vendorId: string;
  vendorName: string;
  rawDescription: string;
  normalizedName?: string | null;
  sku?: string | null;
  unit?: string | null;
  packSize?: string | null;
  unitPrice?: number | null;
  quantity?: number | null;
}

export interface PriceAnalyticsOptions {
  lookbackDays: number;
  percentThreshold: number;
  absoluteThreshold: number;
}

const rounded = (value: number, places = 2) => Number(value.toFixed(places));
const canonical = (value: string) => value.trim().toUpperCase().replace(/[^A-Z0-9/]+/g, ' ').replace(/\s+/g, ' ').trim();
export const canonicalDescription = canonical;

function productKey(row: TrustedPriceObservation) {
  const sku = row.sku ? canonical(row.sku) : '';
  if (sku) return `sku:${sku}`;
  const normalizedName = row.normalizedName ? canonical(row.normalizedName) : '';
  if (normalizedName) return `name:${normalizedName}`;
  const description = canonical(row.rawDescription);
  return description ? `description:${description}` : null;
}

function purchasingBasis(row: TrustedPriceObservation) {
  const unit = row.unit ? canonical(row.unit) : '';
  if (!unit) return null;
  const pack = row.packSize ? canonical(row.packSize) : '';
  return `unit:${unit}|pack:${pack || 'UNSPECIFIED'}`;
}

function opaqueItemKey(vendorId: string, product: string, basis: string) {
  return createHash('sha256').update(`${vendorId}|${product}|${basis}`).digest('base64url').slice(0, 24);
}

export interface PriceHistoryPoint {
  date: string;
  invoiceId: string;
  unitPrice: number;
  quantity: number | null;
}

export interface PriceChangeItem {
  vendorId: string;
  vendorName: string;
  itemKey: string;
  displayName: string;
  sku: string | null;
  unit: string;
  packSize: string | null;
  previousUnitPrice: number;
  currentUnitPrice: number;
  absoluteChange: number;
  percentageChange: number;
  typicalMonthlyQuantity: number | null;
  estimatedMonthlyImpact: number | null;
  estimatedAnnualImpact: number | null;
  firstSeenAt: string;
  latestSeenAt: string;
  consecutiveIncreases: number;
  history: PriceHistoryPoint[];
}

export function analyzePriceObservations(rows: TrustedPriceObservation[], options: PriceAnalyticsOptions) {
  const groups = new Map<string, TrustedPriceObservation[]>();
  for (const row of rows) {
    if (row.unitPrice == null || !Number.isFinite(row.unitPrice) || row.unitPrice <= 0) continue;
    const product = productKey(row);
    const basis = purchasingBasis(row);
    if (!product || !basis) continue;
    const key = `${row.vendorId}|${product}|${basis}`;
    groups.set(key, [...(groups.get(key) ?? []), row]);
  }

  const items: PriceChangeItem[] = [];
  for (const [groupKey, observations] of groups) {
    if (observations.length < 2) continue;
    observations.sort((a, b) => a.invoiceDate.getTime() - b.invoiceDate.getTime() || a.invoiceId.localeCompare(b.invoiceId) || a.lineNumber - b.lineNumber);
    const previous = observations.at(-2)!;
    const current = observations.at(-1)!;
    const previousPrice = previous.unitPrice!;
    const currentPrice = current.unitPrice!;
    if (previousPrice <= 0) continue;
    const absoluteChange = currentPrice - previousPrice;
    const percentageChange = absoluteChange / previousPrice * 100;
    if (!Number.isFinite(percentageChange)) continue;
    const knownQuantity = observations.filter((row) => row.quantity != null && Number.isFinite(row.quantity!) && row.quantity! >= 0);
    const monthlyQuantity = knownQuantity.length
      ? knownQuantity.reduce((sum, row) => sum + row.quantity!, 0) * 30 / options.lookbackDays
      : null;
    const monthlyImpact = monthlyQuantity == null ? null : absoluteChange * monthlyQuantity;
    let consecutiveIncreases = 0;
    for (let index = observations.length - 1; index > 0; index -= 1) {
      if (observations[index].unitPrice! <= observations[index - 1].unitPrice!) break;
      consecutiveIncreases += 1;
    }
    const [, product, basis] = groupKey.match(/^([^|]+)\|(.*)\|(unit:.*)$/) ?? [];
    const itemKey = opaqueItemKey(current.vendorId, product, basis);
    items.push({
      vendorId: current.vendorId,
      vendorName: current.vendorName,
      itemKey,
      displayName: current.normalizedName?.trim() || current.rawDescription,
      sku: current.sku?.trim() || null,
      unit: current.unit!.trim(),
      packSize: current.packSize?.trim() || null,
      previousUnitPrice: rounded(previousPrice),
      currentUnitPrice: rounded(currentPrice),
      absoluteChange: rounded(absoluteChange),
      percentageChange: rounded(percentageChange),
      typicalMonthlyQuantity: monthlyQuantity == null ? null : rounded(monthlyQuantity, 3),
      estimatedMonthlyImpact: monthlyImpact == null ? null : rounded(monthlyImpact),
      estimatedAnnualImpact: monthlyImpact == null ? null : rounded(monthlyImpact * 12),
      firstSeenAt: observations[0].invoiceDate.toISOString(),
      latestSeenAt: current.invoiceDate.toISOString(),
      consecutiveIncreases,
      history: observations.map((row) => ({
        date: row.invoiceDate.toISOString(),
        invoiceId: row.invoiceId,
        unitPrice: rounded(row.unitPrice!),
        quantity: row.quantity == null ? null : rounded(row.quantity, 3),
      })),
    });
  }
  return items;
}

@Injectable()
export class PriceIntelligenceService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: OrganizationAccessService,
    private readonly config: ConfigService,
  ) {}

  private thresholds() {
    const percent = Number(this.config.get<string>('PRICE_CHANGE_PERCENT_THRESHOLD') ?? 5);
    const absolute = Number(this.config.get<string>('PRICE_CHANGE_ABSOLUTE_THRESHOLD') ?? .5);
    return {
      percent: Number.isFinite(percent) && percent >= 0 ? percent : 5,
      absolute: Number.isFinite(absolute) && absolute >= 0 ? absolute : .5,
    };
  }

  private async trustedItems(userId: string, restaurantLocationId: string, lookbackDays: number) {
    const location = await this.prisma.restaurantLocation.findUnique({ where: { id: restaurantLocationId } });
    if (!location) throw new BadRequestException('Location not found');
    await this.access.requireMember(userId, location.organizationId);
    const startDate = new Date();
    startDate.setUTCDate(startDate.getUTCDate() - lookbackDays);
    const lines = await this.prisma.invoiceLineItem.findMany({
      where: {
        organizationId: location.organizationId,
        restaurantLocationId,
        unitPrice: { not: null },
        invoice: {
          reviewStatus: ReviewStatus.REVIEWED,
          vendorId: { not: null },
          invoiceDate: { gte: startDate, lte: new Date() },
        },
      },
      include: { invoice: { select: { id: true, vendorId: true, invoiceDate: true } } },
    });
    const vendorIds = [...new Set(lines.map((line) => line.invoice.vendorId).filter(Boolean) as string[])];
    const vendors = await this.prisma.vendor.findMany({ where: { organizationId: location.organizationId, id: { in: vendorIds } }, select: { id: true, name: true } });
    const vendorNames = new Map(vendors.map((vendor) => [vendor.id, vendor.name]));
    return lines.flatMap<TrustedPriceObservation>((line) => {
      const vendorId = line.invoice.vendorId;
      const invoiceDate = line.invoice.invoiceDate;
      const vendorName = vendorId ? vendorNames.get(vendorId) : null;
      if (!vendorId || !invoiceDate || !vendorName) return [];
      return [{
        invoiceId: line.invoice.id,
        invoiceDate,
        lineNumber: line.lineNumber,
        vendorId,
        vendorName,
        rawDescription: line.rawDescription,
        normalizedName: line.normalizedName,
        sku: line.sku,
        unit: line.unit,
        packSize: line.packSize,
        unitPrice: line.unitPrice == null ? null : Number(line.unitPrice.toString()),
        quantity: line.quantity == null ? null : Number(line.quantity.toString()),
      }];
    });
  }

  async changes(userId: string, query: PriceIntelligenceQuery) {
    const thresholds = this.thresholds();
    let items = analyzePriceObservations(
      await this.trustedItems(userId, query.restaurantLocationId, query.lookbackDays),
      { lookbackDays: query.lookbackDays, percentThreshold: thresholds.percent, absoluteThreshold: thresholds.absolute },
    ).filter((item) => Math.abs(item.percentageChange) >= thresholds.percent && Math.abs(item.absoluteChange) >= thresholds.absolute);
    if (query.vendorId) items = items.filter((item) => item.vendorId === query.vendorId);
    if (query.direction === PriceChangeDirection.INCREASE) items = items.filter((item) => item.absoluteChange > 0);
    if (query.direction === PriceChangeDirection.DECREASE) items = items.filter((item) => item.absoluteChange < 0);
    const sort = query.sort ?? PriceChangeSort.LARGEST_PERCENT_INCREASE;
    items.sort((a, b) => {
      const primary = sort === PriceChangeSort.LARGEST_MONTHLY_IMPACT
        ? Math.abs(b.estimatedMonthlyImpact ?? 0) - Math.abs(a.estimatedMonthlyImpact ?? 0)
        : sort === PriceChangeSort.MOST_RECENT
        ? new Date(b.latestSeenAt).getTime() - new Date(a.latestSeenAt).getTime()
        : sort === PriceChangeSort.VENDOR
        ? a.vendorName.localeCompare(b.vendorName)
        : b.percentageChange - a.percentageChange;
      return primary || a.vendorName.localeCompare(b.vendorName) || a.displayName.localeCompare(b.displayName) || a.itemKey.localeCompare(b.itemKey);
    });
    return { items: items.map(({ history: _history, ...item }) => item), lookbackDays: query.lookbackDays, thresholds: { percentage: thresholds.percent, absolute: thresholds.absolute } };
  }

  async history(userId: string, itemKey: string, query: PriceHistoryQuery) {
    const thresholds = this.thresholds();
    const items = analyzePriceObservations(
      await this.trustedItems(userId, query.restaurantLocationId, query.lookbackDays),
      { lookbackDays: query.lookbackDays, percentThreshold: thresholds.percent, absoluteThreshold: thresholds.absolute },
    );
    const item = items.find((candidate) => candidate.itemKey === itemKey);
    if (!item) throw new NotFoundException('Price history not found');
    const { history, ...summary } = item;
    return { vendor: { id: item.vendorId, name: item.vendorName }, item: summary, history };
  }
}
