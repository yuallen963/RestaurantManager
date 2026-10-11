import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { BankConnectionStatus, BankReconciliationStatus, InsightStatus, Prisma, ReviewStatus } from '@prisma/client';
import { createHash } from 'crypto';
import { DashboardService } from '../dashboard/dashboard.service';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PriceChangeDirection, PriceChangeSort } from '../price-intelligence/dto';
import { PriceIntelligenceService } from '../price-intelligence/price-intelligence.service';
import { PrismaService } from '../prisma.service';
import { NeedsAttentionQuery } from './dto';

export type AttentionSeverity = 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
export type AttentionType = 'ITEM_PRICE_INCREASE' | 'REPEATED_ITEM_PRICE_INCREASE' | 'FOOD_COST_DETERIORATION' | 'LABOR_COST_DETERIORATION' | 'VENDOR_SPEND_INCREASE' | 'CATEGORY_SPEND_INCREASE' | 'POSSIBLE_DUPLICATE_PAYMENT' | 'UNMATCHED_INVOICE' | 'UNMATCHED_PAYMENT';
export type AttentionActionType = 'OPEN_PRICE_HISTORY' | 'OPEN_DASHBOARD_COST' | 'OPEN_VENDOR' | 'OPEN_EXPENSE_CATEGORY' | 'OPEN_INVOICE' | 'OPEN_BANK_TRANSACTION';

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
  whyItMatters?: string;
  nextStep?: string;
  evidence?: Array<{ label: string; value: string; recordId?: string }>;
  status?: InsightStatus;
  sourceType: 'PRICE_INTELLIGENCE' | 'DASHBOARD' | 'VENDOR_SPEND' | 'EXPENSE_CATEGORY' | 'BANK_TRANSACTION' | 'INVOICE';
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
    return {
      ...data,
      whyItMatters: data.whyItMatters ?? 'This change may affect restaurant costs.',
      nextStep: data.nextStep ?? 'Review the supporting records and confirm whether action is needed.',
      evidence: data.evidence ?? [],
      score,
      severity: severityFor(score, thresholds),
    };
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
    const [currentDashboard, previousDashboard, priceData, currentVendors, previousVendors, currentCategories, previousCategories, bankTransactions, reviewedInvoices, bankConnectionCount] = await Promise.all([
      this.dashboard.get(userId, dashboardQuery),
      this.dashboard.get(userId, previousDashboardQuery),
      this.prices.changes(userId, { restaurantLocationId: location.id, lookbackDays: 90, sort: PriceChangeSort.LARGEST_MONTHLY_IMPACT, direction: PriceChangeDirection.INCREASE }),
      this.prisma.expense.groupBy({ by: ['vendorId'], where: { ...base, vendorId: { not: null }, date: { gte: period.start, lte: period.end } }, _sum: { amount: true }, _max: { date: true } }),
      this.prisma.expense.groupBy({ by: ['vendorId'], where: { ...base, vendorId: { not: null }, date: { gte: period.previousStart, lte: period.previousEnd } }, _sum: { amount: true } }),
      this.prisma.expense.groupBy({ by: ['expenseCategoryId'], where: { ...base, date: { gte: period.start, lte: period.end } }, _sum: { amount: true }, _max: { date: true } }),
      this.prisma.expense.groupBy({ by: ['expenseCategoryId'], where: { ...base, date: { gte: period.previousStart, lte: period.previousEnd } }, _sum: { amount: true } }),
      this.prisma.bankTransaction.findMany({
        where: {
          ...base,
          postedDate: { gte: period.start, lte: period.end },
          amount: { gt: new Prisma.Decimal(0) },
          pending: false,
          removedAt: null,
          reconciliationStatus: { not: BankReconciliationStatus.IGNORED },
        },
        select: {
          id: true, amount: true, postedDate: true, description: true,
          merchantNameNormalized: true, vendorId: true, invoiceId: true,
          suggestedInvoiceId: true, reconciliationStatus: true,
          vendor: { select: { name: true } },
        },
        orderBy: [{ postedDate: 'desc' }, { id: 'asc' }],
      }),
      this.prisma.invoice.findMany({
        where: {
          ...base,
          reviewStatus: ReviewStatus.REVIEWED,
          invoiceDate: { gte: period.start, lte: period.end },
          bankTransactions: { none: { reconciliationStatus: BankReconciliationStatus.MATCHED_INVOICE } },
        },
        select: { id: true, invoiceNumber: true, invoiceDate: true, total: true, vendor: { select: { name: true } }, extractedVendorName: true },
        orderBy: [{ invoiceDate: 'desc' }, { id: 'asc' }],
      }),
      this.prisma.bankConnection.count({
        where: {
          organizationId: location.organizationId,
          status: { not: BankConnectionStatus.DISCONNECTED },
          accounts: { some: { restaurantLocationId: location.id, active: true } },
        },
      }),
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
        whyItMatters: `The reviewed unit price changed from $${price.previousUnitPrice.toFixed(2)} to $${price.currentUnitPrice.toFixed(2)} for the same vendor and package basis.`,
        nextStep: 'Review the latest invoice or ask the supplier whether pricing changed.',
        evidence: [
          { label: 'Previous price', value: `$${price.previousUnitPrice.toFixed(2)}`, recordId: price.previousInvoiceId },
          { label: 'Current price', value: `$${price.currentUnitPrice.toFixed(2)}`, recordId: price.currentInvoiceId },
          { label: 'Vendor', value: price.vendorName },
        ],
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

    const duplicateIds = new Set<string>();
    for (let leftIndex = 0; leftIndex < bankTransactions.length; leftIndex += 1) {
      const left = bankTransactions[leftIndex];
      for (let rightIndex = leftIndex + 1; rightIndex < bankTransactions.length; rightIndex += 1) {
        const right = bankTransactions[rightIndex];
        const sameMerchant = left.vendorId && right.vendorId
          ? left.vendorId === right.vendorId
          : Boolean(left.merchantNameNormalized && right.merchantNameNormalized && left.merchantNameNormalized === right.merchantNameNormalized);
        const dayDistance = Math.abs(left.postedDate.getTime() - right.postedDate.getTime()) / 86400000;
        if (!sameMerchant || !left.amount.equals(right.amount) || dayDistance > 2) continue;
        if (left.invoiceId && left.invoiceId === right.invoiceId) continue;
        const pair = [left.id, right.id].sort();
        const signalId = `duplicate:${pair.join(':')}`;
        if (duplicateIds.has(signalId)) continue;
        duplicateIds.add(signalId);
        const merchant = left.vendor?.name ?? left.merchantNameNormalized ?? left.description;
        items.push(this.item({
          id: signalId,
          type: 'POSSIBLE_DUPLICATE_PAYMENT',
          title: `Possible duplicate payment to ${merchant}`,
          subtitle: 'Two nearby bank transactions need review',
          currentValue: money(left.amount), previousValue: money(right.amount),
          percentageChange: null, percentagePointChange: null,
          estimatedMonthlyImpact: null,
          message: `Two $${left.amount.toFixed(2)} payments to ${merchant} posted within ${Math.round(dayDistance)} day${Math.round(dayDistance) === 1 ? '' : 's'}.`,
          whyItMatters: 'This could be a duplicate charge, but multiple legitimate purchases can share the same amount.',
          nextStep: 'Compare the transaction references and supporting invoices before taking action.',
          evidence: [
            { label: 'First payment', value: left.postedDate.toISOString().slice(0, 10), recordId: left.id },
            { label: 'Second payment', value: right.postedDate.toISOString().slice(0, 10), recordId: right.id },
          ],
          sourceType: 'BANK_TRANSACTION', sourceId: left.id,
          occurredAt: left.postedDate > right.postedDate ? left.postedDate.toISOString() : right.postedDate.toISOString(),
          action: { type: 'OPEN_BANK_TRANSACTION', targetId: left.id },
        }, { estimatedMonthlyImpact: money(left.amount), occurredAt: left.postedDate, now: period.end }, config.severity));
      }
    }

    // Without an active bank connection there is no payment coverage to assess;
    // showing every reviewed invoice as unmatched would imply an unpaid bill.
    if (bankConnectionCount > 0) for (const invoice of reviewedInvoices) {
      const vendor = invoice.vendor?.name ?? invoice.extractedVendorName ?? 'Vendor';
      const candidate = bankTransactions.find((transaction) => transaction.suggestedInvoiceId === invoice.id);
      items.push(this.item({
        id: `unmatched-invoice:${invoice.id}`,
        type: 'UNMATCHED_INVOICE', title: 'Invoice has no confirmed bank match',
        subtitle: `${vendor}${invoice.invoiceNumber ? ` · ${invoice.invoiceNumber}` : ''}`,
        currentValue: money(invoice.total), previousValue: 0,
        percentageChange: null, percentagePointChange: null, estimatedMonthlyImpact: null,
        message: candidate ? 'A possible bank match exists, but it has not been confirmed.' : 'No matching transaction was found in the available bank data for this period.',
        whyItMatters: 'Bank coverage is not proof that an invoice is unpaid; confirming the supporting records prevents duplicate expense recognition.',
        nextStep: candidate ? 'Review the suggested bank transaction and confirm it only if the records match.' : 'Check the bank coverage period or supporting payment records before taking action.',
        evidence: [
          { label: 'Invoice total', value: invoice.total == null ? 'Not recorded' : `$${invoice.total.toFixed(2)}`, recordId: invoice.id },
          ...(candidate ? [{ label: 'Potential match', value: candidate.description, recordId: candidate.id }] : []),
        ],
        sourceType: 'INVOICE', sourceId: invoice.id,
        occurredAt: (invoice.invoiceDate ?? period.end).toISOString(),
        action: { type: 'OPEN_INVOICE', targetId: invoice.id },
      }, { occurredAt: invoice.invoiceDate ?? period.end, now: period.end }, config.severity));
    }

    const matchedDuplicateTransactionIds = new Set([...duplicateIds].flatMap((id) => id.split(':').slice(1)));
    for (const transaction of bankTransactions) {
      if (transaction.invoiceId || matchedDuplicateTransactionIds.has(transaction.id)) continue;
      if (transaction.reconciliationStatus !== BankReconciliationStatus.UNMATCHED
        && transaction.reconciliationStatus !== BankReconciliationStatus.NEEDS_REVIEW) continue;
      const merchant = transaction.vendor?.name ?? transaction.merchantNameNormalized ?? transaction.description;
      items.push(this.item({
        id: `unmatched-payment:${transaction.id}`,
        type: 'UNMATCHED_PAYMENT', title: 'Payment has no linked invoice', subtitle: merchant,
        currentValue: money(transaction.amount), previousValue: 0,
        percentageChange: null, percentagePointChange: null, estimatedMonthlyImpact: null,
        message: transaction.suggestedInvoiceId ? 'A possible invoice match exists, but it has not been confirmed.' : 'This bank payment is not linked to an invoice.',
        whyItMatters: 'Supporting invoices make spending easier to verify and categorize.',
        nextStep: transaction.suggestedInvoiceId ? 'Review the suggested invoice and confirm it only if the records match.' : 'Check whether an invoice or receipt is available for this payment.',
        evidence: [{ label: 'Payment', value: `$${transaction.amount.toFixed(2)} on ${transaction.postedDate.toISOString().slice(0, 10)}`, recordId: transaction.id }],
        sourceType: 'BANK_TRANSACTION', sourceId: transaction.id, occurredAt: transaction.postedDate.toISOString(),
        action: { type: 'OPEN_BANK_TRANSACTION', targetId: transaction.id },
      }, { occurredAt: transaction.postedDate, now: period.end }, config.severity));
    }

    const persistedItems = await Promise.all(items.map(async (item) => {
      const fingerprint = createHash('sha256')
        .update(`${location.id}|${item.type}|${item.sourceId}|${item.occurredAt}|${item.currentValue}`)
        .digest('hex');
      const persisted = await this.prisma.insight.upsert({
        where: { fingerprint },
        create: {
          organizationId: location.organizationId,
          restaurantLocationId: location.id,
          fingerprint,
          type: item.type,
          severity: item.severity,
          title: item.title,
          description: item.message,
          metadata: JSON.parse(JSON.stringify(item)),
          generatedAt: new Date(item.occurredAt),
        },
        update: {
          severity: item.severity,
          title: item.title,
          description: item.message,
          metadata: JSON.parse(JSON.stringify(item)),
        },
      });
      return { item, persisted };
    }));
    const visibleItems: AttentionItem[] = persistedItems
      .filter(({ persisted }) => persisted.status !== InsightStatus.DISMISSED && persisted.status !== InsightStatus.RESOLVED)
      .map(({ item, persisted }) => ({ ...item, id: persisted.id, status: persisted.status }));

    visibleItems.sort((a, b) => severityRank[b.severity] - severityRank[a.severity]
      || Math.abs(b.estimatedMonthlyImpact ?? 0) - Math.abs(a.estimatedMonthlyImpact ?? 0)
      || new Date(b.occurredAt).getTime() - new Date(a.occurredAt).getTime()
      || a.id.localeCompare(b.id));
    const summary = { critical: 0, high: 0, medium: 0, low: 0, estimatedMonthlyImpact: 0 };
    for (const item of visibleItems) summary[item.severity.toLowerCase() as 'critical' | 'high' | 'medium' | 'low'] += 1;
    // Only item-level price impact is summed to avoid double-counting overlapping
    // vendor and category increases in the headline total.
    summary.estimatedMonthlyImpact = rounded(visibleItems
      .filter((item) => item.sourceType === 'PRICE_INTELLIGENCE')
      .reduce((sum, item) => sum + Math.max(item.estimatedMonthlyImpact ?? 0, 0), 0));
    return {
      period: { startDate: period.start.toISOString(), endDate: period.end.toISOString(), previousStartDate: period.previousStart.toISOString(), previousEndDate: period.previousEnd.toISOString() },
      summary,
      items: visibleItems,
    };
  }

  async updateStatus(userId: string, id: string, status: InsightStatus) {
    const insight = await this.prisma.insight.findUnique({ where: { id } });
    if (!insight) throw new BadRequestException('Finding not found');
    await this.access.requireMember(userId, insight.organizationId);
    const now = new Date();
    return this.prisma.insight.update({
      where: { id },
      data: {
        status,
        reviewedAt: status === InsightStatus.REVIEWED ? now : insight.reviewedAt,
        resolvedAt: status === InsightStatus.RESOLVED ? now : null,
        dismissedAt: status === InsightStatus.DISMISSED ? now : null,
      },
    });
  }
}
