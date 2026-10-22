import { BadRequestException, Injectable } from '@nestjs/common';
import {
  BankConnectionStatus,
  BankReconciliationStatus,
  ExpenseClassification,
  PosConnectionStatus,
  Prisma,
  ReviewStatus,
} from '@prisma/client';
import { IsISO8601, IsOptional, IsUUID } from 'class-validator';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PrismaService } from '../prisma.service';

export class DashboardQuery {
  @IsUUID()
  restaurantLocationId!: string;

  @IsOptional()
  @IsISO8601()
  startDate?: string;

  @IsOptional()
  @IsISO8601()
  endDate?: string;
}

const zero = () => new Prisma.Decimal(0);
const decimal = (value: Prisma.Decimal | null | undefined) => value ?? zero();
const money = (value: Prisma.Decimal | null | undefined) =>
  Number(decimal(value).toFixed(2));
const percent = (part: Prisma.Decimal, total: Prisma.Decimal) =>
  total.isZero()
    ? 0
    : Number(part.dividedBy(total).times(100).toFixed(1));
const businessDayBoundary = (value: string, end = false) => {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  if (!match) throw new BadRequestException('Invalid date range');
  const start = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  if (start.toISOString().slice(0, 10) !== `${match[1]}-${match[2]}-${match[3]}`) throw new BadRequestException('Invalid date range');
  return end ? new Date(start.getTime() + 86400000 - 1) : start;
};

type NamedAmount = { name: string; amount: number };

@Injectable()
export class DashboardService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: OrganizationAccessService,
  ) {}

  async get(userId: string, query: DashboardQuery) {
    if (!query.restaurantLocationId) {
      throw new BadRequestException('restaurantLocationId is required');
    }
    const location = await this.prisma.restaurantLocation.findUnique({
      where: { id: query.restaurantLocationId },
    });
    if (!location) throw new BadRequestException('Location not found');
    await this.access.requireMember(userId, location.organizationId);

    const startDate = query.startDate
      ? businessDayBoundary(query.startDate)
      : new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    const endDate = query.endDate ? businessDayBoundary(query.endDate, true) : new Date();
    if (!query.endDate) endDate.setHours(23, 59, 59, 999);
    if (
      Number.isNaN(startDate.valueOf()) ||
      Number.isNaN(endDate.valueOf()) ||
      startDate > endDate
    ) {
      throw new BadRequestException('Invalid date range');
    }

    const organizationId = location.organizationId;
    const restaurantLocationId = location.id;
    const financeWhere = {
      organizationId,
      restaurantLocationId,
      date: { gte: startDate, lte: endDate },
    };
    const bankWhere = {
      organizationId,
      restaurantLocationId,
      postedDate: { gte: startDate, lte: endDate },
      pending: false,
      removedAt: null,
      amount: { gt: zero() },
      reconciliationStatus: { not: BankReconciliationStatus.IGNORED },
    };
    const invoiceWhere = {
      organizationId,
      restaurantLocationId,
      invoiceDate: { gte: startDate, lte: endDate },
    };

    const periodMs = endDate.getTime() - startDate.getTime() + 1;
    const previousStart = new Date(startDate.getTime() - periodMs);
    const previousEnd = new Date(startDate.getTime() - 1);

    const [
      revenue,
      revenueCount,
      expenses,
      expenseCount,
      expenseGroups,
      bankTransactions,
      previousBank,
      bankConnectionCount,
      invoices,
      invoiceReviewCount,
      previousInvoices,
      posMappingCount,
    ] = await Promise.all([
      this.prisma.revenueEntry.aggregate({
        where: financeWhere,
        _sum: { amount: true },
      }),
      this.prisma.revenueEntry.count({ where: financeWhere }),
      this.prisma.expense.aggregate({
        where: financeWhere,
        _sum: { amount: true },
      }),
      this.prisma.expense.count({ where: financeWhere }),
      this.prisma.expense.groupBy({
        by: ['expenseCategoryId'],
        where: financeWhere,
        _sum: { amount: true },
      }),
      this.prisma.bankTransaction.findMany({
        where: bankWhere,
        select: {
          id: true,
          amount: true,
          description: true,
          merchantNameNormalized: true,
          categoryId: true,
          reconciliationStatus: true,
          invoiceId: true,
          vendor: { select: { name: true } },
          category: { select: { name: true } },
        },
        orderBy: { amount: 'desc' },
      }),
      this.prisma.bankTransaction.aggregate({
        where: {
          ...bankWhere,
          postedDate: { gte: previousStart, lte: previousEnd },
        },
        _sum: { amount: true },
      }),
      this.prisma.bankConnection.count({
        where: {
          organizationId,
          status: { not: BankConnectionStatus.DISCONNECTED },
          accounts: {
            some: { restaurantLocationId, active: true },
          },
        },
      }),
      this.prisma.invoice.findMany({
        where: invoiceWhere,
        select: {
          id: true,
          total: true,
          reviewStatus: true,
          vendor: { select: { name: true } },
          extractedVendorName: true,
          bankTransactions: {
            where: {
              reconciliationStatus: BankReconciliationStatus.MATCHED_INVOICE,
            },
            select: { id: true },
            take: 1,
          },
        },
      }),
      this.prisma.invoice.count({
        where: {
          ...invoiceWhere,
          reviewStatus: { not: ReviewStatus.REVIEWED },
        },
      }),
      this.prisma.invoice.aggregate({
        where: {
          organizationId,
          restaurantLocationId,
          invoiceDate: { gte: previousStart, lte: previousEnd },
          reviewStatus: ReviewStatus.REVIEWED,
        },
        _sum: { total: true },
      }),
      this.prisma.posLocationMapping.count({
        where: {
          organizationId,
          restaurantLocationId,
          active: true,
          connection: { status: PosConnectionStatus.CONNECTED },
        },
      }),
    ]);

    const categoryIds = expenseGroups.map((group) => group.expenseCategoryId);
    const categories = await this.prisma.expenseCategory.findMany({
      where: { id: { in: categoryIds } },
    });
    const categoryLookup = new Map(
      categories.map((category) => [category.id, category]),
    );

    const totalRevenue = decimal(revenue._sum.amount);
    const totalExpenses = decimal(expenses._sum.amount);
    const foodCost = expenseGroups
      .filter(
        (group) =>
          categoryLookup.get(group.expenseCategoryId)?.classification ===
          ExpenseClassification.FOOD,
      )
      .reduce((sum, group) => sum.plus(decimal(group._sum.amount)), zero());
    const laborCost = expenseGroups
      .filter(
        (group) =>
          categoryLookup.get(group.expenseCategoryId)?.classification ===
          ExpenseClassification.LABOR,
      )
      .reduce((sum, group) => sum.plus(decimal(group._sum.amount)), zero());

    const trackedOutflows = bankTransactions.reduce(
      (sum, transaction) => sum.plus(transaction.amount),
      zero(),
    );
    const bankCategoryTotals = new Map<string, Prisma.Decimal>();
    const bankVendorTotals = new Map<string, Prisma.Decimal>();
    for (const transaction of bankTransactions) {
      const category = transaction.category?.name ?? 'Uncategorized';
      bankCategoryTotals.set(
        category,
        (bankCategoryTotals.get(category) ?? zero()).plus(transaction.amount),
      );
      const vendor =
        transaction.vendor?.name ??
        transaction.merchantNameNormalized ??
        transaction.description;
      bankVendorTotals.set(
        vendor,
        (bankVendorTotals.get(vendor) ?? zero()).plus(transaction.amount),
      );
    }

    const reviewedInvoices = invoices.filter(
      (invoice) => invoice.reviewStatus === ReviewStatus.REVIEWED,
    );
    const reviewedPurchases = reviewedInvoices.reduce(
      (sum, invoice) => sum.plus(decimal(invoice.total)),
      zero(),
    );
    const invoiceVendorTotals = new Map<string, Prisma.Decimal>();
    for (const invoice of reviewedInvoices) {
      const vendor =
        invoice.vendor?.name ?? invoice.extractedVendorName ?? 'Unknown vendor';
      invoiceVendorTotals.set(
        vendor,
        (invoiceVendorTotals.get(vendor) ?? zero()).plus(
          decimal(invoice.total),
        ),
      );
    }

    const hasBankData = bankConnectionCount > 0 || bankTransactions.length > 0;
    const hasReviewedInvoices = reviewedInvoices.length > 0;
    const hasRevenueData = revenueCount > 0;
    const hasPosData = posMappingCount > 0;
    const hasExpenseData = expenseCount > 0;
    const profitabilityAvailable =
      hasRevenueData &&
      hasExpenseData &&
      hasBankData &&
      hasReviewedInvoices;

    return {
      period: {
        startDate: startDate.toISOString(),
        endDate: endDate.toISOString(),
      },
      availability: {
        bank: hasBankData,
        reviewedInvoices: hasReviewedInvoices,
        revenue: hasRevenueData,
        pos: hasPosData,
        expenses: hasExpenseData,
        profitability: profitabilityAvailable,
      },
      summary: {
        revenue: money(totalRevenue),
        expenses: money(totalExpenses),
        estimatedProfit: money(totalRevenue.minus(totalExpenses)),
        profitMargin: percent(totalRevenue.minus(totalExpenses), totalRevenue),
        foodCost: money(foodCost),
        foodCostPercentage: percent(foodCost, totalRevenue),
        laborCost: money(laborCost),
        laborCostPercentage: percent(laborCost, totalRevenue),
      },
      expenseBreakdown: expenseGroups
        .map((group) => ({
          categoryId: group.expenseCategoryId,
          categoryName:
            categoryLookup.get(group.expenseCategoryId)?.name ?? 'Unknown',
          amount: money(group._sum.amount),
          percentageOfExpenses: percent(
            decimal(group._sum.amount),
            totalExpenses,
          ),
        }))
        .sort((a, b) => b.amount - a.amount),
      bank: {
        trackedOutflows: money(trackedOutflows),
        previousTrackedOutflows: money(previousBank._sum.amount),
        uncategorizedCount: bankTransactions.filter(
          (transaction) => !transaction.categoryId,
        ).length,
        unmatchedCount: bankTransactions.filter((transaction) =>
          [
            BankReconciliationStatus.UNMATCHED,
            BankReconciliationStatus.NEEDS_REVIEW,
          ].includes(
            transaction.reconciliationStatus as
              | 'UNMATCHED'
              | 'NEEDS_REVIEW',
          ),
        ).length,
        matchedInvoiceCount: bankTransactions.filter(
          (transaction) => transaction.invoiceId != null,
        ).length,
        categoryBreakdown: this.namedAmounts(bankCategoryTotals),
        topVendors: this.namedAmounts(bankVendorTotals).slice(0, 5),
        largestExpenses: bankTransactions.slice(0, 5).map((transaction) => ({
          id: transaction.id,
          name:
            transaction.vendor?.name ??
            transaction.merchantNameNormalized ??
            transaction.description,
          amount: money(transaction.amount),
        })),
      },
      invoices: {
        reviewedPurchases: money(reviewedPurchases),
        previousReviewedPurchases: money(previousInvoices._sum.total),
        reviewedCount: reviewedInvoices.length,
        requiringReviewCount: invoiceReviewCount,
        unmatchedCount: hasBankData
          ? reviewedInvoices.filter(
              (invoice) => invoice.bankTransactions.length === 0,
            ).length
          : 0,
        topVendors: this.namedAmounts(invoiceVendorTotals).slice(0, 5),
      },
    };
  }

  private namedAmounts(values: Map<string, Prisma.Decimal>): NamedAmount[] {
    return [...values.entries()]
      .map(([name, amount]) => ({ name, amount: money(amount) }))
      .sort((a, b) => b.amount - a.amount);
  }
}
