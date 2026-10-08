import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { DashboardService } from '../dashboard/dashboard.service';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PriceChangeDirection, PriceChangeSort } from '../price-intelligence/dto';
import { PriceIntelligenceService } from '../price-intelligence/price-intelligence.service';
import { PrismaService } from '../prisma.service';
import { NeedsAttentionQuery } from './dto';

export type AttentionSeverity = 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
export type AttentionType = 'ITEM_PRICE_INCREASE' | 'REPEATED_ITEM_PRICE_INCREASE' | 'FOOD_COST_DETERIORATION' | 'LABOR_COST_DETERIORATION' | 'VENDOR_SPEND_INCREASE' | 'CATEGORY_SPEND_INCREASE';
export type AttentionActionType = 'OPEN_PRICE_HISTORY' | 'OPEN_DASHBOARD_COST' | 'OPEN_VENDOR' | 'OPEN_EXPENSE_CATEGORY';

export interface SeverityInput {
  estimatedMonthlyImpact?: number | null;
  percentageChange?: number | null;
  consecutiveIncreases?: number;
  percentagePointChange?: number | null;
  occurredAt: Date;
  now: Date;
}

export interface SeverityThresholds {
  medium: number;
  high: number;
  critical: number;
}

export function severityScore(input: SeverityInput) {
  const impact = Math.abs(input.estimatedMonthlyImpact ?? 0);
  const percentage = Math.abs(input.percentageChange ?? 0);
  const points = Math.abs(input.percentagePointChange ?? 0);
  const ageDays = Math.max(0, (input.now.getTime() - input.occurredAt.getTime()) / 86400000);
  return (impact >= 1000 ? 4 : impact >= 500 ? 3 : impact >= 200 ? 2 : impact >= 50 ? 1 : 0)
    + (percentage >= 50 ? 3 : percentage >= 25 ? 2 : percentage >= 10 ? 1 : 0)
    + ((input.consecutiveIncreases ?? 0) >= 3 ? 2 : (input.consecutiveIncreases ?? 0) >= 2 ? 1 : 0)
    + (points >= 5 ? 3 : points >= 3 ? 2 : points >= 2 ? 1 : 0)
    + (ageDays <= 7 ? 1 : 0);
}

export function severityFor(score: number, thresholds: SeverityThresholds): AttentionSeverity {
  if (score >= thresholds.critical) return 'CRITICAL';
  if (score >= thresholds.high) return 'HIGH';
  if (score >= thresholds.medium) return 'MEDIUM';
  return 'LOW';
}

export function comparisonPeriod(startValue?: string, endValue?: string, now = new Date()) {
  if (Boolean(startValue) !== Boolean(endValue)) throw new BadRequestException('startDate and endDate must be provided together');
  const start = startValue ? new Date(startValue) : new Date(now.getFullYear(), now.getMonth(), 1);
  const end = endValue ? new Date(endValue) : new Date(now);
  const explicitZone = Boolean(endValue && /(?:Z|[+-]\d{2}:\d{2})$/i.test(endValue));
  if (explicitZone) end.setUTCHours(23, 59, 59, 999);
  else end.setHours(23, 59, 59, 999);
  if (Number.isNaN(start.valueOf()) || Number.isNaN(end.valueOf()) || start > end) throw new BadRequestException('Invalid date range');
  const startDayNumber = explicitZone
    ? Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate())
    : Date.UTC(start.getFullYear(), start.getMonth(), start.getDate());
  const endDayNumber = explicitZone
    ? Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate())
    : Date.UTC(end.getFullYear(), end.getMonth(), end.getDate());
  const dayCount = Math.floor((endDayNumber - startDayNumber) / 86400000) + 1;
  const previousEnd = new Date(start);
  previousEnd.setMilliseconds(-1);
  const previousStart = new Date(start);
  if (explicitZone) previousStart.setUTCDate(previousStart.getUTCDate() - dayCount);
  else previousStart.setDate(previousStart.getDate() - dayCount);
  return { start, end, previousStart, previousEnd, dayCount };
}

export interface AttentionItem {
  id: string;
  type: AttentionType;
  severity: AttentionSeverity;
  score: number;
  title: string;
  subtitle: string | null;
  currentValue: number;
  previousValue: number;
  percentageChange: number | null;
  percentagePointChange: number | null;
  estimatedMonthlyImpact: number | null;
  message: string;
  sourceType: 'PRICE_INTELLIGENCE' | 'DASHBOARD' | 'VENDOR_SPEND' | 'EXPENSE_CATEGORY';
  sourceId: string;
  occurredAt: string;
  action: { type: AttentionActionType; targetId: string };
}

const rounded = (value: number, places = 2) => Number(value.toFixed(places));
const percentChange = (current: number, previous: number) => previous <= 0 ? null : rounded((current - previous) / previous * 100);
const money = (value: Prisma.Decimal | null | undefined) => Number((value ?? new Prisma.Decimal(0)).toFixed(2));
const severityRank: Record<AttentionSeverity, number> = { LOW: 1, MEDIUM: 2, HIGH: 3, CRITICAL: 4 };

@Injectable()
export class NeedsAttentionService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: OrganizationAccessService,
    private readonly dashboard: DashboardService,
    private readonly prices: PriceIntelligenceService,
    private readonly config: ConfigService,
  ) {}

  private number(name: string, fallback: number) {
    const value = Number(this.config.get<string>(name) ?? fallback);
    return Number.isFinite(value) && value >= 0 ? value : fallback;
  }

  private configValues() {
    return {
      foodPoints: this.number('FOOD_COST_DETERIORATION_THRESHOLD', 2),
      laborPoints: this.number('LABOR_COST_DETERIORATION_THRESHOLD', 2),
      vendorPercent: this.number('VENDOR_SPEND_PERCENT_THRESHOLD', 15),
      vendorDollars: this.number('VENDOR_SPEND_DOLLAR_THRESHOLD', 250),
      categoryPercent: this.number('CATEGORY_SPEND_PERCENT_THRESHOLD', 15),
      categoryDollars: this.number('CATEGORY_SPEND_DOLLAR_THRESHOLD', 200),
      severity: {
        medium: this.number('ATTENTION_MEDIUM_SCORE_THRESHOLD', 3),
        high: this.number('ATTENTION_HIGH_SCORE_THRESHOLD', 5),
        critical: this.number('ATTENTION_CRITICAL_SCORE_THRESHOLD', 7),
      },
    };
  }

  private item(data: Omit<AttentionItem, 'severity' | 'score'>, input: SeverityInput, thresholds: SeverityThresholds): AttentionItem {
    const score = severityScore(input);
    return { ...data, score, severity: severityFor(score, thresholds) };
  }

  async get(userId: string, query: NeedsAttentionQuery) {
    const location = await this.prisma.restaurantLocation.findUnique({ where: { id: query.restaurantLocationId } });
    if (!location) throw new BadRequestException('Location not found');
    await this.access.requireMember(userId, location.organizationId);
    const period = comparisonPeriod(query.startDate, query.endDate);
    const config = this.configValues();
    const dashboardQuery = { restaurantLocationId: location.id, startDate: period.start.toISOString(), endDate: period.end.toISOString() };
    const previousDashboardQuery = { restaurantLocationId: location.id, startDate: period.previousStart.toISOString(), endDate: period.previousEnd.toISOString() };
    const base = { organizationId: location.organizationId, restaurantLocationId: location.id };
    const [currentDashboard, previousDashboard, priceData, currentVendors, previousVendors, currentCategories, previousCategories] = await Promise.all([
      this.dashboard.get(userId, dashboardQuery),
      this.dashboard.get(userId, previousDashboardQuery),
      this.prices.changes(userId, { restaurantLocationId: location.id, lookbackDays: 90, sort: PriceChangeSort.LARGEST_MONTHLY_IMPACT, direction: PriceChangeDirection.INCREASE }),
      this.prisma.expense.groupBy({ by: ['vendorId'], where: { ...base, vendorId: { not: null }, date: { gte: period.start, lte: period.end } }, _sum: { amount: true }, _max: { date: true } }),
      this.prisma.expense.groupBy({ by: ['vendorId'], where: { ...base, vendorId: { not: null }, date: { gte: period.previousStart, lte: period.previousEnd } }, _sum: { amount: true } }),
      this.prisma.expense.groupBy({ by: ['expenseCategoryId'], where: { ...base, date: { gte: period.start, lte: period.end } }, _sum: { amount: true }, _max: { date: true } }),
      this.prisma.expense.groupBy({ by: ['expenseCategoryId'], where: { ...base, date: { gte: period.previousStart, lte: period.previousEnd } }, _sum: { amount: true } }),
    ]);
    const vendorIds = [...new Set((currentVendors as any[]).map((row) => row.vendorId).filter(Boolean))] as string[];
    const categoryIds = [...new Set((currentCategories as any[]).map((row) => row.expenseCategoryId))] as string[];
    const [vendors, categories] = await Promise.all([
      this.prisma.vendor.findMany({ where: { organizationId: location.organizationId, id: { in: vendorIds } }, select: { id: true, name: true } }),
      this.prisma.expenseCategory.findMany({ where: { id: { in: categoryIds }, OR: [{ organizationId: null }, { organizationId: location.organizationId }] }, select: { id: true, name: true } }),
    ]);
    const vendorNames = new Map(vendors.map((vendor) => [vendor.id, vendor.name]));
    const categoryNames = new Map(categories.map((category) => [category.id, category.name]));
    const items: AttentionItem[] = [];

    for (const price of priceData.items) {
      const repeated = price.consecutiveIncreases >= 2;
      const occurredAt = new Date(price.latestSeenAt);
      items.push(this.item({
        id: `price:${price.itemKey}`,
        type: repeated ? 'REPEATED_ITEM_PRICE_INCREASE' : 'ITEM_PRICE_INCREASE',
        title: repeated ? `${price.displayName} keeps increasing` : `${price.displayName} cost increased`,
        subtitle: price.vendorName,
        currentValue: price.currentUnitPrice,
        previousValue: price.previousUnitPrice,
        percentageChange: price.percentageChange,
        percentagePointChange: null,
        estimatedMonthlyImpact: price.estimatedMonthlyImpact,
        message: repeated
          ? `${price.displayName} increased on ${price.consecutiveIncreases} consecutive purchases.`
          : `${price.displayName} increased ${price.percentageChange.toFixed(1)}% since the previous purchase.`,
        sourceType: 'PRICE_INTELLIGENCE',
        sourceId: price.itemKey,
        occurredAt: price.latestSeenAt,
        action: { type: 'OPEN_PRICE_HISTORY', targetId: price.itemKey },
      }, { estimatedMonthlyImpact: price.estimatedMonthlyImpact, percentageChange: price.percentageChange, consecutiveIncreases: price.consecutiveIncreases, occurredAt, now: period.end }, config.severity));
    }

    const costSignals = [
      { type: 'FOOD_COST_DETERIORATION' as const, label: 'Food cost', key: 'food', current: currentDashboard.summary.foodCostPercentage, previous: previousDashboard.summary.foodCostPercentage, threshold: config.foodPoints },
      { type: 'LABOR_COST_DETERIORATION' as const, label: 'Labor cost', key: 'labor', current: currentDashboard.summary.laborCostPercentage, previous: previousDashboard.summary.laborCostPercentage, threshold: config.laborPoints },
    ];
    for (const signal of costSignals) {
      const pointChange = rounded(signal.current - signal.previous, 1);
      if (pointChange < signal.threshold) continue;
      const relativeChange = percentChange(signal.current, signal.previous);
      items.push(this.item({
        id: `${signal.key}:${period.start.toISOString().slice(0, 10)}`,
        type: signal.type,
        title: `${signal.label} increased`,
        subtitle: location.name,
        currentValue: signal.current,
        previousValue: signal.previous,
        percentageChange: relativeChange,
        percentagePointChange: pointChange,
        estimatedMonthlyImpact: null,
        message: `${signal.label} rose from ${signal.previous.toFixed(1)}% to ${signal.current.toFixed(1)}% this period.`,
        sourceType: 'DASHBOARD',
        sourceId: signal.key,
        occurredAt: period.end.toISOString(),
        action: { type: 'OPEN_DASHBOARD_COST', targetId: signal.key },
      }, { percentageChange: relativeChange, percentagePointChange: pointChange, occurredAt: period.end, now: period.end }, config.severity));
    }

    const previousVendor = new Map((previousVendors as any[]).map((row) => [row.vendorId, money(row._sum.amount)]));
    for (const row of currentVendors as any[]) {
      const vendorId = row.vendorId as string;
      const current = money(row._sum.amount);
      const previous = previousVendor.get(vendorId) ?? 0;
      const increase = current - previous;
      const percentage = percentChange(current, previous);
      if (percentage == null || percentage < config.vendorPercent || increase < config.vendorDollars) continue;
      const monthlyImpact = rounded(increase * 30 / period.dayCount);
      const occurredAt = row._max.date ?? period.end;
      const name = vendorNames.get(vendorId) ?? 'Vendor';
      items.push(this.item({
        id: `vendor:${vendorId}:${period.start.toISOString().slice(0, 10)}`,
        type: 'VENDOR_SPEND_INCREASE', title: `${name} spend increased`, subtitle: name,
        currentValue: current, previousValue: previous, percentageChange: percentage, percentagePointChange: null,
        estimatedMonthlyImpact: monthlyImpact,
        message: `${name} spend is up ${percentage.toFixed(1)}% compared with the previous period.`,
        sourceType: 'VENDOR_SPEND', sourceId: vendorId, occurredAt: new Date(occurredAt).toISOString(),
        action: { type: 'OPEN_VENDOR', targetId: vendorId },
      }, { estimatedMonthlyImpact: monthlyImpact, percentageChange: percentage, occurredAt: new Date(occurredAt), now: period.end }, config.severity));
    }

    const previousCategory = new Map((previousCategories as any[]).map((row) => [row.expenseCategoryId, money(row._sum.amount)]));
    for (const row of currentCategories as any[]) {
      const categoryId = row.expenseCategoryId as string;
      const current = money(row._sum.amount);
      const previous = previousCategory.get(categoryId) ?? 0;
      const increase = current - previous;
      const percentage = percentChange(current, previous);
      if (percentage == null || percentage < config.categoryPercent || increase < config.categoryDollars) continue;
      const monthlyImpact = rounded(increase * 30 / period.dayCount);
      const occurredAt = row._max.date ?? period.end;
      const name = categoryNames.get(categoryId) ?? 'Expense category';
      items.push(this.item({
        id: `category:${categoryId}:${period.start.toISOString().slice(0, 10)}`,
        type: 'CATEGORY_SPEND_INCREASE', title: `${name} spending increased`, subtitle: name,
        currentValue: current, previousValue: previous, percentageChange: percentage, percentagePointChange: null,
        estimatedMonthlyImpact: monthlyImpact,
        message: `${name} spending is up ${percentage.toFixed(1)}% compared with the previous period.`,
        sourceType: 'EXPENSE_CATEGORY', sourceId: categoryId, occurredAt: new Date(occurredAt).toISOString(),
        action: { type: 'OPEN_EXPENSE_CATEGORY', targetId: categoryId },
      }, { estimatedMonthlyImpact: monthlyImpact, percentageChange: percentage, occurredAt: new Date(occurredAt), now: period.end }, config.severity));
    }

    items.sort((a, b) => severityRank[b.severity] - severityRank[a.severity]
      || Math.abs(b.estimatedMonthlyImpact ?? 0) - Math.abs(a.estimatedMonthlyImpact ?? 0)
      || new Date(b.occurredAt).getTime() - new Date(a.occurredAt).getTime()
      || a.id.localeCompare(b.id));
    const summary = { critical: 0, high: 0, medium: 0, low: 0, estimatedMonthlyImpact: 0 };
    for (const item of items) summary[item.severity.toLowerCase() as 'critical' | 'high' | 'medium' | 'low'] += 1;
    // Only item-level price impact is summed to avoid double-counting overlapping
    // vendor and category increases in the headline total.
    summary.estimatedMonthlyImpact = rounded(items
      .filter((item) => item.sourceType === 'PRICE_INTELLIGENCE')
      .reduce((sum, item) => sum + Math.max(item.estimatedMonthlyImpact ?? 0, 0), 0));
    return {
      period: { startDate: period.start.toISOString(), endDate: period.end.toISOString(), previousStartDate: period.previousStart.toISOString(), previousEndDate: period.previousEnd.toISOString() },
      summary,
      items,
    };
  }
}
