import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash } from 'crypto';
import { Prisma, ReviewStatus } from '@prisma/client';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PrismaService } from '../prisma.service';
import { PriceChangeDirection, PriceChangeSort, PriceHistoryQuery, PriceIntelligenceQuery } from './dto';

type DecimalLike = Prisma.Decimal | number | string;
const decimal = (value: DecimalLike) => value instanceof Prisma.Decimal ? value : new Prisma.Decimal(value.toString());

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
  unitPrice?: DecimalLike | null;
  extendedPrice?: DecimalLike | null;
  quantity?: DecimalLike | null;
  measurementUnit?: string | null;
  totalPackageQuantity?: DecimalLike | null;
  productAttributes?: unknown;
  fieldProvenance?: unknown;
  currency?: string | null;
  currencyProvenance?: unknown;
  productGroupId?: string | null;
}

export interface PriceAnalyticsOptions {
  lookbackDays: number;
  percentThreshold: number;
  absoluteThreshold: number;
}

const rounded = (value: Prisma.Decimal, places = 2) => Number(value.toFixed(places));
const canonical = (value: string) => value.trim().toUpperCase().replace(/[^A-Z0-9/]+/g, ' ').replace(/\s+/g, ' ').trim();
export const canonicalDescription = canonical;

type ProvenanceEntry = { kind?: string; verified?: boolean };
function provenance(row: TrustedPriceObservation, field: string) {
  const value = row.fieldProvenance;
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, ProvenanceEntry>)[field]
    : undefined;
}
function trusted(row: TrustedPriceObservation, field: string) {
  const entry = provenance(row, field);
  return Boolean(entry?.verified && (entry.kind === 'OBSERVED' || entry.kind === 'CALCULATED'));
}

function trustedCurrency(row: TrustedPriceObservation) {
  const value = row.currencyProvenance;
  const entry = value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, ProvenanceEntry>).currency
    : undefined;
  return Boolean(row.currency?.trim() && entry?.verified && (entry.kind === 'OBSERVED' || entry.kind === 'CALCULATED'));
}

const attributeKeys = ['brand', 'condition', 'bone', 'skin', 'organic', 'grade', 'cut', 'size'] as const;
function attributeBasis(value: unknown) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return '';
  const record = value as Record<string, unknown>;
  return attributeKeys.map((key) => `${key}:${canonical(String(record[key] ?? ''))}`).filter((part) => !part.endsWith(':')).join('|');
}

function productKey(row: TrustedPriceObservation) {
  const attributes = attributeBasis(row.productAttributes);
  if (row.productGroupId) return `group:${row.productGroupId}|${attributes}`;
  const sku = row.sku ? canonical(row.sku) : '';
  if (sku && trusted(row, 'sku')) return `sku:${sku}|${attributes}`;
  return null;
}

const weightToLb: Record<string, Prisma.Decimal> = {
  LB: decimal(1), OZ: decimal(1).dividedBy(16), KG: decimal('2.2046226218487757'), G: decimal('0.0022046226218488'),
};
const volumeToGallon: Record<string, Prisma.Decimal> = {
  GAL: decimal(1), 'FL OZ': decimal(1).dividedBy(128), L: decimal('0.2641720523581484'), ML: decimal('0.0002641720523581'),
};
const countUnits = new Set(['EA', 'EACH', 'CT', 'COUNT', 'UNIT']);

export interface NormalizedObservation {
  canonicalUnit: 'lb' | 'gallon' | 'each';
  normalizedQuantity: Prisma.Decimal;
  normalizedUnitPrice: Prisma.Decimal;
  purchasePrice: Prisma.Decimal;
}

export function normalizePriceObservation(row: TrustedPriceObservation): NormalizedObservation | null {
  if (row.quantity == null || !trusted(row, 'quantity')) return null;
  const quantity = decimal(row.quantity);
  if (!quantity.isFinite() || quantity.lte(0)) return null;
  const measurement = canonical(row.measurementUnit ?? '');
  const packageQuantity = row.totalPackageQuantity == null ? null : decimal(row.totalPackageQuantity);
  let canonicalUnit: NormalizedObservation['canonicalUnit'];
  let packageBasis: Prisma.Decimal;
  if (measurement && weightToLb[measurement] && packageQuantity?.gt(0)) {
    canonicalUnit = 'lb'; packageBasis = packageQuantity.mul(weightToLb[measurement]);
  } else if (measurement && volumeToGallon[measurement] && packageQuantity?.gt(0)) {
    canonicalUnit = 'gallon'; packageBasis = packageQuantity.mul(volumeToGallon[measurement]);
  } else if (measurement && countUnits.has(measurement) && packageQuantity?.gt(0)) {
    canonicalUnit = 'each'; packageBasis = packageQuantity;
  } else if (countUnits.has(canonical(row.unit ?? '')) && !row.packSize) {
    canonicalUnit = 'each'; packageBasis = decimal(1);
  } else return null;
  const normalizedQuantity = quantity.mul(packageBasis);
  let purchasePrice: Prisma.Decimal | null = null;
  if (row.extendedPrice != null && trusted(row, 'extendedPrice')) purchasePrice = decimal(row.extendedPrice);
  else if (row.unitPrice != null && trusted(row, 'unitPrice')) purchasePrice = decimal(row.unitPrice).mul(quantity);
  if (!purchasePrice?.isFinite() || purchasePrice.lte(0) || normalizedQuantity.lte(0)) return null;
  return { canonicalUnit, normalizedQuantity, normalizedUnitPrice: purchasePrice.dividedBy(normalizedQuantity), purchasePrice };
}

export function priceEligibilityReason(row: TrustedPriceObservation) {
  if (!trustedCurrency(row)) return 'MISSING_OR_UNVERIFIED_CURRENCY';
  if (!productKey(row)) return 'UNVERIFIED_PRODUCT_IDENTITY';
  if (row.quantity == null || !trusted(row, 'quantity')) return 'MISSING_OR_UNVERIFIED_QUANTITY';
  if (!row.measurementUnit || row.totalPackageQuantity == null) return 'MISSING_OR_UNSUPPORTED_PACKAGE';
  if ((row.extendedPrice == null || !trusted(row, 'extendedPrice')) && (row.unitPrice == null || !trusted(row, 'unitPrice'))) return 'MISSING_OR_UNVERIFIED_PRICE';
  if (!normalizePriceObservation(row)) return 'INCOMPATIBLE_OR_INVALID_UNITS';
  return null;
}

function opaqueItemKey(vendorId: string, product: string, basis: string) {
  return createHash('sha256').update(`${vendorId}|${product}|${basis}`).digest('base64url').slice(0, 24);
}

export interface PriceHistoryPoint {
  date: string;
  invoiceId: string;
  unitPrice: number;
  quantity: number | null;
  rawDescription: string;
  originalQuantity: number;
  packSize: string | null;
  purchasePrice: number;
  currency: string;
}

export interface PriceChangeItem {
  vendorId: string;
  vendorName: string;
  itemKey: string;
  displayName: string;
  sku: string | null;
  unit: string;
  currency: string;
  packSize: string | null;
  previousUnitPrice: number;
  currentUnitPrice: number;
  previousInvoiceId: string;
  currentInvoiceId: string;
  absoluteChange: number;
  percentageChange: number;
  typicalMonthlyQuantity: number | null;
  estimatedMonthlyImpact: number | null;
  estimatedAnnualImpact: number | null;
  firstSeenAt: string;
  latestSeenAt: string;
  consecutiveIncreases: number;
  observationCount: number;
  impactExplanation: string | null;
  history: PriceHistoryPoint[];
}

export function analyzePriceObservations(rows: TrustedPriceObservation[], options: PriceAnalyticsOptions) {
  const groups = new Map<string, Array<{ row: TrustedPriceObservation; normalized: NormalizedObservation }>>();
  const seen = new Set<string>();
  for (const row of rows) {
    const observationKey = `${row.invoiceId}|${row.lineNumber}`;
    if (seen.has(observationKey)) continue;
    seen.add(observationKey);
    const product = productKey(row);
    const normalized = normalizePriceObservation(row);
    if (!product || !normalized || !trustedCurrency(row)) continue;
    const currency = canonical(row.currency!);
    const key = `${row.vendorId}|${product}|unit:${normalized.canonicalUnit}|currency:${currency}`;
    groups.set(key, [...(groups.get(key) ?? []), { row, normalized }]);
  }

  const items: PriceChangeItem[] = [];
  for (const [groupKey, observations] of groups) {
    if (observations.length < 2) continue;
    observations.sort((a, b) => a.row.invoiceDate.getTime() - b.row.invoiceDate.getTime() || a.row.invoiceId.localeCompare(b.row.invoiceId) || a.row.lineNumber - b.row.lineNumber);
    const previous = observations.at(-2)!;
    const current = observations.at(-1)!;
    const previousPrice = previous.normalized.normalizedUnitPrice;
    const currentPrice = current.normalized.normalizedUnitPrice;
    if (previousPrice.lte(0)) continue;
    const absoluteChange = currentPrice.sub(previousPrice);
    const percentageChange = absoluteChange.dividedBy(previousPrice).times(100);
    if (!percentageChange.isFinite()) continue;
    const firstDate = observations[0].row.invoiceDate;
    const latestDate = current.row.invoiceDate;
    const observedDays = Math.max(1, (latestDate.getTime() - firstDate.getTime()) / 86400000 + 1);
    // Require three observations spanning at least 28 days. Two price points
    // establish a change but do not establish a recurring purchase rate.
    const sortedQuantities = observations.map((value) => value.normalized.normalizedQuantity).sort((a, b) => a.comparedTo(b));
    const medianQuantity = sortedQuantities[Math.floor(sortedQuantities.length / 2)];
    const hasVolumeOutlier = sortedQuantities.at(-1)!.gt(medianQuantity.mul(3));
    const monthlyQuantity = observations.length >= 3 && observedDays >= 28 && !hasVolumeOutlier
      ? observations.reduce((sum, value) => sum.add(value.normalized.normalizedQuantity), new Prisma.Decimal(0)).times(30).dividedBy(observedDays)
      : null;
    const monthlyImpact = monthlyQuantity == null ? null : absoluteChange.mul(monthlyQuantity);
    let consecutiveIncreases = 0;
    for (let index = observations.length - 1; index > 0; index -= 1) {
      if (observations[index].normalized.normalizedUnitPrice.lte(observations[index - 1].normalized.normalizedUnitPrice)) break;
      consecutiveIncreases += 1;
    }
    const [, product, unitBasis, currencyBasis] = groupKey.match(/^([^|]+)\|(.*)\|(unit:[^|]+)\|(currency:.*)$/) ?? [];
    const basis = `${unitBasis}|${currencyBasis}`;
    const itemKey = opaqueItemKey(current.row.vendorId, product, basis);
    items.push({
      vendorId: current.row.vendorId,
      vendorName: current.row.vendorName,
      itemKey,
      displayName: current.row.normalizedName?.trim() || current.row.rawDescription,
      sku: current.row.sku?.trim() || null,
      unit: current.normalized.canonicalUnit,
      currency: current.row.currency!.trim().toUpperCase(),
      packSize: current.row.packSize?.trim() || null,
      previousUnitPrice: rounded(previousPrice),
      currentUnitPrice: rounded(currentPrice),
      previousInvoiceId: previous.row.invoiceId,
      currentInvoiceId: current.row.invoiceId,
      absoluteChange: rounded(absoluteChange),
      percentageChange: rounded(percentageChange),
      typicalMonthlyQuantity: monthlyQuantity == null ? null : rounded(monthlyQuantity, 3),
      estimatedMonthlyImpact: monthlyImpact == null ? null : rounded(monthlyImpact),
      estimatedAnnualImpact: monthlyImpact == null ? null : rounded(monthlyImpact.times(12)),
      firstSeenAt: firstDate.toISOString(),
      latestSeenAt: latestDate.toISOString(),
      consecutiveIncreases,
      observationCount: observations.length,
      impactExplanation: monthlyQuantity == null ? null : `${rounded(observations.reduce((sum, value) => sum.add(value.normalized.normalizedQuantity), new Prisma.Decimal(0)), 3)} ${current.normalized.canonicalUnit} purchased over ${Math.round(observedDays)} days, scaled to 30 days`,
      history: observations.map(({ row, normalized }) => ({
        date: row.invoiceDate.toISOString(),
        invoiceId: row.invoiceId,
        unitPrice: rounded(normalized.normalizedUnitPrice, 4),
        quantity: rounded(normalized.normalizedQuantity, 3),
        rawDescription: row.rawDescription,
        originalQuantity: rounded(decimal(row.quantity!), 3),
        packSize: row.packSize?.trim() || null,
        purchasePrice: rounded(normalized.purchasePrice),
        currency: row.currency!.trim().toUpperCase(),
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

  private async trustedItems(userId: string, restaurantLocationId: string, lookbackDays: number, startValue?: string, endValue?: string) {
    const location = await this.prisma.restaurantLocation.findUnique({ where: { id: restaurantLocationId } });
    if (!location) throw new BadRequestException('Location not found');
    await this.access.requireMember(userId, location.organizationId);
    if (Boolean(startValue) !== Boolean(endValue)) throw new BadRequestException('startDate and endDate must be provided together');
    const endDate = endValue ? new Date(endValue) : new Date();
    const startDate = startValue ? new Date(startValue) : new Date(endDate);
    if (!startValue) startDate.setUTCDate(startDate.getUTCDate() - lookbackDays);
    if (!Number.isFinite(startDate.valueOf()) || !Number.isFinite(endDate.valueOf()) || startDate > endDate) throw new BadRequestException('Invalid date range');
    const lines = await this.prisma.invoiceLineItem.findMany({
      where: {
        organizationId: location.organizationId,
        restaurantLocationId,
        OR: [
          { unitPrice: { not: null } },
          { extendedPrice: { not: null } },
        ],
        invoice: {
          reviewStatus: ReviewStatus.REVIEWED,
          vendorId: { not: null },
          invoiceDate: { gte: startDate, lte: endDate },
        },
      },
      include: {
        invoice: { select: { id: true, vendorId: true, invoiceDate: true, currency: true, fieldProvenance: true } },
        productGroupMemberships: { where: { confirmed: true }, select: { productGroupId: true }, take: 1 },
      },
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
        unitPrice: line.unitPrice == null ? null : line.unitPrice,
        extendedPrice: line.extendedPrice == null ? null : line.extendedPrice,
        quantity: line.quantity == null ? null : line.quantity,
        measurementUnit: line.measurementUnit,
        totalPackageQuantity: line.totalPackageQuantity,
        productAttributes: line.productAttributes,
        fieldProvenance: line.fieldProvenance,
        currency: line.invoice.currency,
        currencyProvenance: line.invoice.fieldProvenance,
        productGroupId: line.productGroupMemberships[0]?.productGroupId ?? null,
      }];
    });
  }

  async changes(userId: string, query: PriceIntelligenceQuery) {
    const thresholds = this.thresholds();
    const rows = await this.trustedItems(userId, query.restaurantLocationId, query.lookbackDays, query.startDate, query.endDate);
    const exclusionReasons = rows.flatMap((row): string[] => { const reason = priceEligibilityReason(row); return reason ? [reason] : []; })
      .reduce<Record<string, number>>((counts, reason) => ({ ...counts, [reason]: (counts[reason] ?? 0) + 1 }), {});
    let items = analyzePriceObservations(
      rows,
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
    const periodDays = query.startDate && query.endDate
      ? Math.floor((new Date(query.endDate).getTime() - new Date(query.startDate).getTime()) / 86400000) + 1
      : query.lookbackDays;
    return { items: items.map(({ history: _history, ...item }) => item), lookbackDays: periodDays, thresholds: { percentage: thresholds.percent, absolute: thresholds.absolute }, eligibility: { reviewedLines: rows.length, eligibleObservations: rows.length - Object.values(exclusionReasons).reduce((sum, count) => sum + count, 0), excludedObservations: Object.values(exclusionReasons).reduce((sum, count) => sum + count, 0), reasons: exclusionReasons } };
  }

  async history(userId: string, itemKey: string, query: PriceHistoryQuery) {
    const thresholds = this.thresholds();
    const items = analyzePriceObservations(
      await this.trustedItems(userId, query.restaurantLocationId, query.lookbackDays, query.startDate, query.endDate),
      { lookbackDays: query.lookbackDays, percentThreshold: thresholds.percent, absoluteThreshold: thresholds.absolute },
    );
    const item = items.find((candidate) => candidate.itemKey === itemKey);
    if (!item) throw new NotFoundException('Price history not found');
    const { history, ...summary } = item;
    return { vendor: { id: item.vendorId, name: item.vendorName }, item: summary, history };
  }
}
