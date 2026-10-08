import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { ExpenseSource, Prisma, RevenueSource } from '@prisma/client';
import { AuditService } from '../audit.service';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PrismaService } from '../prisma.service';

const decimal = (value: string | number) => {
  const result = new Prisma.Decimal(value);
  if (!result.isFinite() || result.lte(0)) throw new BadRequestException('Amount must be positive');
  return result;
};

@Injectable()
export class FinanceService {
  constructor(private readonly prisma: PrismaService, private readonly access: OrganizationAccessService, private readonly audit: AuditService) {}

  async location(userId: string, id: string) {
    const location = await this.prisma.restaurantLocation.findUnique({ where: { id } });
    if (!location) throw new NotFoundException('Location not found');
    await this.access.requireMember(userId, location.organizationId);
    return location;
  }

  async owned(userId: string, table: 'revenueEntry' | 'expense' | 'vendor', id: string) {
    const row = await (this.prisma[table] as any).findUnique({ where: { id } });
    if (!row) throw new NotFoundException('Record not found');
    await this.access.requireMember(userId, row.organizationId);
    return row;
  }

  async revenue(userId: string, data: any) {
    const location = await this.location(userId, data.restaurantLocationId);
    const row = await this.prisma.revenueEntry.create({ data: { organizationId: location.organizationId, restaurantLocationId: location.id, date: new Date(data.date), amount: decimal(data.amount), notes: data.notes, source: RevenueSource.MANUAL, createdByUserId: userId } });
    await this.audit.log({ userId, organizationId: location.organizationId, action: 'revenue.created', entityType: 'RevenueEntry', entityId: row.id });
    return row;
  }

  async revenues(userId: string, query: any) {
    const location = await this.location(userId, query.restaurantLocationId);
    const page = Math.max(Number(query.page ?? 1), 1);
    const take = Math.min(Number(query.limit ?? 50), 100);
    const skip = (page - 1) * take;
    const startDate = query.startDate ? new Date(query.startDate) : undefined;
    const endDate = query.endDate ? new Date(query.endDate) : undefined;
    if (endDate) endDate.setHours(23, 59, 59, 999);
    const where: Prisma.RevenueEntryWhereInput = { organizationId: location.organizationId, restaurantLocationId: location.id, source: query.source || undefined, date: { gte: startDate, lte: endDate } };
    const orderBy: Prisma.RevenueEntryOrderByWithRelationInput[] = query.sort === 'oldest'
      ? [{ date: 'asc' }, { id: 'asc' }]
      : query.sort === 'highestRevenue'
      ? [{ amount: 'desc' }, { date: 'desc' }, { id: 'asc' }]
      : query.sort === 'lowestRevenue'
      ? [{ amount: 'asc' }, { date: 'desc' }, { id: 'asc' }]
      : [{ date: 'desc' }, { id: 'asc' }];
    let previousWhere: Prisma.RevenueEntryWhereInput | undefined;
    let dayCount = 0;
    if (startDate && endDate) {
      dayCount = Math.floor((new Date(endDate.getFullYear(), endDate.getMonth(), endDate.getDate()).getTime() - new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate()).getTime()) / 86400000) + 1;
      const previousEnd = new Date(startDate);
      previousEnd.setDate(previousEnd.getDate() - 1);
      previousEnd.setHours(23, 59, 59, 999);
      const previousStart = new Date(startDate);
      previousStart.setDate(previousStart.getDate() - dayCount);
      previousWhere = { organizationId: location.organizationId, restaurantLocationId: location.id, source: query.source || undefined, date: { gte: previousStart, lte: previousEnd } };
    }
    const [items, totalItems, total, previous, daily] = await Promise.all([
      this.prisma.revenueEntry.findMany({ where, orderBy, take, skip }),
      this.prisma.revenueEntry.count({ where }),
      this.prisma.revenueEntry.aggregate({ where, _sum: { amount: true } }),
      previousWhere ? this.prisma.revenueEntry.aggregate({ where: previousWhere, _sum: { amount: true } }) : Promise.resolve({ _sum: { amount: null } }),
      this.prisma.revenueEntry.groupBy({ by: ['date'], where, _sum: { amount: true }, orderBy: { date: 'asc' } }),
    ]);
    const dailyTotals = new Map<string, { date: Date; amount: number }>();
    for (const row of daily as any[]) {
      const date = new Date(row.date);
      const key = `${date.getUTCFullYear()}-${date.getUTCMonth()}-${date.getUTCDate()}`;
      const amount = Number((row._sum.amount ?? new Prisma.Decimal(0)).toFixed(2));
      const existing = dailyTotals.get(key);
      dailyTotals.set(key, { date: existing?.date ?? new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate())), amount: Number(((existing?.amount ?? 0) + amount).toFixed(2)) });
    }
    const dailyTrend = [...dailyTotals.values()].sort((a, b) => a.date.getTime() - b.date.getTime());
    const highestDay = dailyTrend.reduce((best: any, row: any) => !best || row.amount > best.amount ? row : best, null);
    const lowestDay = dailyTrend.reduce((best: any, row: any) => !best || row.amount < best.amount ? row : best, null);
    const totalRevenue = Number((total._sum.amount ?? new Prisma.Decimal(0)).toFixed(2));
    if (!dayCount) dayCount = dailyTrend.length;
    return { items, pagination: { page, limit: take, totalItems, totalPages: Math.ceil(totalItems / take), hasMore: skip + items.length < totalItems }, summary: { totalRevenue, previousTotalRevenue: Number((previous._sum.amount ?? new Prisma.Decimal(0)).toFixed(2)), averageDailyRevenue: dayCount > 0 ? Number((totalRevenue / dayCount).toFixed(2)) : 0, highestDay, lowestDay, dailyTrend } };
  }

  async revenueDetail(userId: string, id: string) { return this.owned(userId, 'revenueEntry', id); }
  async updateRevenue(userId: string, id: string, data: any) { const record = await this.owned(userId, 'revenueEntry', id); const row = await this.prisma.revenueEntry.update({ where: { id }, data: { date: data.date ? new Date(data.date) : undefined, amount: data.amount ? decimal(data.amount) : undefined, notes: data.notes } }); await this.audit.log({ userId, organizationId: record.organizationId, action: 'revenue.updated', entityType: 'RevenueEntry', entityId: id }); return row; }
  async deleteRevenue(userId: string, id: string) { const record = await this.owned(userId, 'revenueEntry', id); await this.prisma.revenueEntry.delete({ where: { id } }); await this.audit.log({ userId, organizationId: record.organizationId, action: 'revenue.deleted', entityType: 'RevenueEntry', entityId: id }); }
  async categories(userId: string, organizationId: string) { await this.access.requireMember(userId, organizationId); return this.prisma.expenseCategory.findMany({ where: { OR: [{ organizationId: null }, { organizationId }] }, orderBy: { name: 'asc' } }); }
  async category(organizationId: string, id: string) { const category = await this.prisma.expenseCategory.findFirst({ where: { id, OR: [{ organizationId: null }, { organizationId }] } }); if (!category) throw new ForbiddenException('Category is not available'); return category; }
  async expense(userId: string, data: any) { const location = await this.location(userId, data.restaurantLocationId); await this.category(location.organizationId, data.expenseCategoryId); if (data.vendorId) { const vendor = await this.owned(userId, 'vendor', data.vendorId); if (vendor.organizationId !== location.organizationId) throw new ForbiddenException('Vendor is not available'); } const row = await this.prisma.expense.create({ data: { organizationId: location.organizationId, restaurantLocationId: location.id, expenseCategoryId: data.expenseCategoryId, vendorId: data.vendorId, date: new Date(data.date), amount: decimal(data.amount), description: data.description, notes: data.notes, source: ExpenseSource.MANUAL, createdByUserId: userId } }); await this.audit.log({ userId, organizationId: location.organizationId, action: 'expense.created', entityType: 'Expense', entityId: row.id }); return row; }
  async expenses(userId: string, query: any) { const location = await this.location(userId, query.restaurantLocationId); const page = Math.max(Number(query.page ?? 1), 1), take = Math.min(Number(query.limit ?? 50), 100), skip = (page - 1) * take; const endDate = query.endDate ? new Date(query.endDate) : undefined; if (endDate) endDate.setHours(23, 59, 59, 999); const search = query.search?.trim(); const matchingVendors = search ? await this.prisma.vendor.findMany({ where: { organizationId: location.organizationId, name: { contains: search, mode: 'insensitive' } }, select: { id: true } }) : []; const where: Prisma.ExpenseWhereInput = { organizationId: location.organizationId, restaurantLocationId: location.id, expenseCategoryId: query.categoryId || undefined, vendorId: query.vendorId || undefined, date: { gte: query.startDate ? new Date(query.startDate) : undefined, lte: endDate }, OR: search ? [{ description: { contains: search, mode: 'insensitive' } }, { vendorId: { in: matchingVendors.map((vendor) => vendor.id) } }] : undefined }; const orderBy: Prisma.ExpenseOrderByWithRelationInput[] = query.sort === 'oldest' ? [{ date: 'asc' }, { id: 'asc' }] : query.sort === 'highestAmount' ? [{ amount: 'desc' }, { date: 'desc' }, { id: 'asc' }] : query.sort === 'lowestAmount' ? [{ amount: 'asc' }, { date: 'desc' }, { id: 'asc' }] : [{ date: 'desc' }, { id: 'asc' }]; const [items, totalItems, total] = await Promise.all([this.prisma.expense.findMany({ where, orderBy, take, skip }), this.prisma.expense.count({ where }), this.prisma.expense.aggregate({ where, _sum: { amount: true } })]); return { items, pagination: { page, limit: take, totalItems, totalPages: Math.ceil(totalItems / take), hasMore: skip + items.length < totalItems }, summary: { totalAmount: Number((total._sum.amount ?? new Prisma.Decimal(0)).toFixed(2)) } }; }
  async expenseDetail(userId: string, id: string) { return this.owned(userId, 'expense', id); }
  async updateExpense(userId: string, id: string, data: any) { const expense = await this.owned(userId, 'expense', id); if (data.expenseCategoryId) await this.category(expense.organizationId, data.expenseCategoryId); if (data.vendorId) { const vendor = await this.owned(userId, 'vendor', data.vendorId); if (vendor.organizationId !== expense.organizationId) throw new ForbiddenException('Vendor is not available'); } const row = await this.prisma.expense.update({ where: { id }, data: { ...data, date: data.date ? new Date(data.date) : undefined, amount: data.amount ? decimal(data.amount) : undefined } }); await this.audit.log({ userId, organizationId: expense.organizationId, action: 'expense.updated', entityType: 'Expense', entityId: id }); return row; }
  async deleteExpense(userId: string, id: string) { const expense = await this.owned(userId, 'expense', id); await this.prisma.expense.delete({ where: { id } }); await this.audit.log({ userId, organizationId: expense.organizationId, action: 'expense.deleted', entityType: 'Expense', entityId: id }); }
  async vendorSummaries(userId: string, query: any) {
    const location = await this.location(userId, query.restaurantLocationId);
    const start = new Date(query.startDate);
    const end = new Date(query.endDate); end.setHours(23, 59, 59, 999);
    const days = Math.floor((new Date(end.getFullYear(), end.getMonth(), end.getDate()).getTime() - new Date(start.getFullYear(), start.getMonth(), start.getDate()).getTime()) / 86400000) + 1;
    const previousEnd = new Date(start); previousEnd.setDate(previousEnd.getDate() - 1); previousEnd.setHours(23, 59, 59, 999);
    const previousStart = new Date(start); previousStart.setDate(previousStart.getDate() - days);
    const vendorWhere: Prisma.VendorWhereInput = { organizationId: location.organizationId, name: query.search?.trim() ? { contains: query.search.trim(), mode: 'insensitive' } : undefined };
    const vendors = await this.prisma.vendor.findMany({ where: vendorWhere, select: { id: true, name: true } });
    const vendorIds = vendors.map((vendor) => vendor.id);
    const base = { organizationId: location.organizationId, restaurantLocationId: location.id, vendorId: { in: vendorIds } };
    const [current, previous] = await Promise.all([
      this.prisma.expense.groupBy({ by: ['vendorId'], where: { ...base, date: { gte: start, lte: end } }, _sum: { amount: true }, _count: { _all: true }, _max: { date: true } }),
      this.prisma.expense.groupBy({ by: ['vendorId'], where: { ...base, date: { gte: previousStart, lte: previousEnd } }, _sum: { amount: true } }),
    ]);
    const currentByVendor = new Map(current.map((row: any) => [row.vendorId, row]));
    const previousByVendor = new Map(previous.map((row: any) => [row.vendorId, row]));
    const summaries = vendors.map((vendor) => {
      const currentRow: any = currentByVendor.get(vendor.id);
      const previousRow: any = previousByVendor.get(vendor.id);
      const currentSpend = Number((currentRow?._sum.amount ?? new Prisma.Decimal(0)).toFixed(2));
      const previousSpend = Number((previousRow?._sum.amount ?? new Prisma.Decimal(0)).toFixed(2));
      const percentageChange = previousSpend === 0 ? null : Number((((currentSpend - previousSpend) / Math.abs(previousSpend)) * 100).toFixed(1));
      return { id: vendor.id, name: vendor.name, currentSpend, previousSpend, percentageChange, transactionCount: currentRow?._count._all ?? 0, lastPurchaseDate: currentRow?._max.date ?? null };
    }).filter((vendor) => vendor.currentSpend > 0 || vendor.previousSpend > 0);
    const compare = query.sort === 'lowestSpend' ? (a: any, b: any) => a.currentSpend - b.currentSpend || a.name.localeCompare(b.name) : query.sort === 'largestIncrease' ? (a: any, b: any) => (b.percentageChange ?? -Infinity) - (a.percentageChange ?? -Infinity) || a.name.localeCompare(b.name) : query.sort === 'mostTransactions' ? (a: any, b: any) => b.transactionCount - a.transactionCount || b.currentSpend - a.currentSpend || a.name.localeCompare(b.name) : query.sort === 'alphabetical' ? (a: any, b: any) => a.name.localeCompare(b.name) : (a: any, b: any) => b.currentSpend - a.currentSpend || a.name.localeCompare(b.name);
    summaries.sort(compare);
    const page = Math.max(Number(query.page ?? 1), 1), limit = Math.min(Number(query.limit ?? 25), 100), skip = (page - 1) * limit;
    const items = summaries.slice(skip, skip + limit);
    return { items, pagination: { page, limit, totalItems: summaries.length, totalPages: Math.ceil(summaries.length / limit), hasMore: skip + items.length < summaries.length } };
  }

  async vendorSummary(userId: string, id: string, query: any) {
    const location = await this.location(userId, query.restaurantLocationId);
    const vendor = await this.prisma.vendor.findFirst({ where: { id, organizationId: location.organizationId }, select: { id: true, name: true } });
    if (!vendor) throw new NotFoundException('Vendor not found');
    const start = new Date(query.startDate);
    const end = new Date(query.endDate); end.setHours(23, 59, 59, 999);
    const days = Math.floor((new Date(end.getFullYear(), end.getMonth(), end.getDate()).getTime() - new Date(start.getFullYear(), start.getMonth(), start.getDate()).getTime()) / 86400000) + 1;
    const previousEnd = new Date(start); previousEnd.setDate(previousEnd.getDate() - 1); previousEnd.setHours(23, 59, 59, 999);
    const previousStart = new Date(start); previousStart.setDate(previousStart.getDate() - days);
    const base = { organizationId: location.organizationId, restaurantLocationId: location.id, vendorId: id };
    const [current, previous, recentExpenses, rawTrend] = await Promise.all([
      this.prisma.expense.aggregate({ where: { ...base, date: { gte: start, lte: end } }, _sum: { amount: true }, _count: { _all: true }, _max: { date: true } }),
      this.prisma.expense.aggregate({ where: { ...base, date: { gte: previousStart, lte: previousEnd } }, _sum: { amount: true } }),
      this.prisma.expense.findMany({ where: { ...base, date: { gte: start, lte: end } }, orderBy: [{ date: 'desc' }, { id: 'asc' }], take: 10 }),
      this.prisma.expense.groupBy({ by: ['date'], where: { ...base, date: { gte: start, lte: end } }, _sum: { amount: true }, orderBy: { date: 'asc' } }),
    ]);
    const categoryIds = [...new Set(recentExpenses.map((expense) => expense.expenseCategoryId))];
    const categories = await this.prisma.expenseCategory.findMany({ where: { id: { in: categoryIds }, OR: [{ organizationId: null }, { organizationId: location.organizationId }] }, select: { id: true, name: true } });
    const categoryNames = new Map(categories.map((category) => [category.id, category.name]));
    const trendMap = new Map<string, { date: Date; amount: number }>();
    for (const row of rawTrend as any[]) { const date = new Date(row.date); const key = `${date.getUTCFullYear()}-${date.getUTCMonth()}-${date.getUTCDate()}`; const existing = trendMap.get(key); trendMap.set(key, { date: existing?.date ?? new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate())), amount: Number(((existing?.amount ?? 0) + Number(row._sum.amount ?? 0)).toFixed(2)) }); }
    const currentSpend = Number((current._sum.amount ?? new Prisma.Decimal(0)).toFixed(2));
    const previousSpend = Number((previous._sum.amount ?? new Prisma.Decimal(0)).toFixed(2));
    const transactionCount = current._count._all;
    return { vendor, summary: { currentSpend, previousSpend, percentageChange: previousSpend === 0 ? null : Number((((currentSpend - previousSpend) / Math.abs(previousSpend)) * 100).toFixed(1)), transactionCount, averageTransaction: transactionCount === 0 ? 0 : Number((currentSpend / transactionCount).toFixed(2)), lastPurchaseDate: current._max.date }, trend: [...trendMap.values()].sort((a, b) => a.date.getTime() - b.date.getTime()), recentExpenses: recentExpenses.map((expense) => ({ id: expense.id, date: expense.date, description: expense.description, categoryName: categoryNames.get(expense.expenseCategoryId) ?? 'Unknown category', amount: Number(expense.amount.toFixed(2)) })) };
  }

  async vendor(userId: string, data: any) { await this.access.requireMember(userId, data.organizationId); const normalizedName = data.name.trim().toLowerCase().replace(/\s+/g, ' '); const row = await this.prisma.vendor.create({ data: { organizationId: data.organizationId, name: data.name.trim(), normalizedName, email: data.email, phone: data.phone, notes: data.notes } }); await this.audit.log({ userId, organizationId: data.organizationId, action: 'vendor.created', entityType: 'Vendor', entityId: row.id }); return row; }
  async vendors(userId: string, organizationId: string) { await this.access.requireMember(userId, organizationId); return this.prisma.vendor.findMany({ where: { organizationId }, orderBy: { name: 'asc' } }); }
  async vendorDetail(userId: string, id: string) { return this.owned(userId, 'vendor', id); }
  async updateVendor(userId: string, id: string, data: any) { const vendor = await this.owned(userId, 'vendor', id); const name = data.name?.trim(); const row = await this.prisma.vendor.update({ where: { id }, data: { ...data, name, normalizedName: name?.toLowerCase().replace(/\s+/g, ' ') } }); await this.audit.log({ userId, organizationId: vendor.organizationId, action: 'vendor.updated', entityType: 'Vendor', entityId: id }); return row; }
  async deleteVendor(userId: string, id: string) { const vendor = await this.owned(userId, 'vendor', id); await this.prisma.vendor.delete({ where: { id } }); await this.audit.log({ userId, organizationId: vendor.organizationId, action: 'vendor.deleted', entityType: 'Vendor', entityId: id }); }
}
