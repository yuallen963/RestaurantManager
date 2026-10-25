import { ExpenseSource, Prisma, PrismaClient } from '@prisma/client';
import {
  demoDowntownLocationId,
  demoExpenseAmount,
  demoMainLocationId,
  demoOrganizationId,
  recipeForDemoLocation,
} from './demo-financial-profile';

const prisma = new PrismaClient();
const expectedLocationIds = [demoDowntownLocationId, demoMainLocationId] as const;

const dayKey = (date: Date) => date.toISOString().slice(0, 10);

async function main() {
  if (process.env.APPLY_PUBLIC_DEMO_REBALANCE !== 'true') {
    throw new Error('Refusing to write without APPLY_PUBLIC_DEMO_REBALANCE=true');
  }

  const organization = await prisma.organization.findUnique({
    where: { id: demoOrganizationId },
    select: {
      name: true,
      memberships: { select: { user: { select: { email: true } } } },
      locations: { select: { id: true, name: true } },
      bankConnections: { select: { provider: true } },
    },
  });
  if (!organization || organization.name !== 'FundWell Public Demo') {
    throw new Error('Refusing to rebalance: public demo organization identity mismatch');
  }
  const actualLocations = organization.locations.map(({ id }) => id).sort();
  if (
    actualLocations.length !== expectedLocationIds.length ||
    actualLocations.some((id, index) => id !== [...expectedLocationIds].sort()[index]) ||
    organization.memberships.some(({ user }) => user.email !== 'demo@profitlens.local') ||
    organization.bankConnections.some(({ provider }) => provider !== 'DEMO')
  ) {
    throw new Error('Refusing to rebalance: demo tenant contains unexpected ownership or locations');
  }

  const [categories, revenue, expenses] = await Promise.all([
    prisma.expenseCategory.findMany({
      where: { organizationId: null },
      select: { id: true, slug: true },
    }),
    prisma.revenueEntry.groupBy({
      by: ['restaurantLocationId', 'date'],
      where: { organizationId: demoOrganizationId },
      _sum: { amount: true },
      _count: true,
    }),
    prisma.expense.findMany({
      where: { organizationId: demoOrganizationId },
      select: {
        id: true,
        restaurantLocationId: true,
        expenseCategoryId: true,
        date: true,
        source: true,
        bankTransactions: { select: { id: true, organizationId: true } },
      },
    }),
  ]);

  const categorySlug = new Map(categories.map(({ id, slug }) => [id, slug]));
  const revenueByDay = new Map(
    revenue.map((row) => [
      `${row.restaurantLocationId}:${dayKey(row.date)}`,
      { amount: Number(row._sum.amount), count: row._count },
    ]),
  );
  const expenseDays = new Map<string, number>();
  const updates: { id: string; amount: Prisma.Decimal; bankTransactionIds: string[] }[] = [];

  for (const expense of expenses) {
    if (
      !expectedLocationIds.includes(expense.restaurantLocationId as typeof expectedLocationIds[number]) ||
      expense.source !== ExpenseSource.MANUAL ||
      expense.bankTransactions.some((transaction) => transaction.organizationId !== demoOrganizationId)
    ) {
      throw new Error('Refusing to rebalance: found an unexpected or cross-tenant demo expense');
    }
    const key = `${expense.restaurantLocationId}:${dayKey(expense.date)}`;
    const dailyRevenue = revenueByDay.get(key);
    const slug = categorySlug.get(expense.expenseCategoryId);
    const recipe = recipeForDemoLocation(expense.restaurantLocationId);
    const recipeEntry = recipe.find(([candidate]) => candidate === slug);
    if (!dailyRevenue || dailyRevenue.count !== 2 || !recipeEntry) {
      throw new Error(`Refusing to rebalance: incomplete synthetic day ${key}`);
    }
    expenseDays.set(key, (expenseDays.get(key) ?? 0) + 1);
    updates.push({
      id: expense.id,
      amount: new Prisma.Decimal(
        demoExpenseAmount(dailyRevenue.amount, recipeEntry[1], expense.date, expense.restaurantLocationId),
      ),
      bankTransactionIds: expense.bankTransactions.map(({ id }) => id),
    });
  }

  if (
    revenue.length !== 730 ||
    expenses.length !== 11680 ||
    expenseDays.size !== 730 ||
    [...expenseDays.values()].some((count) => count !== 16)
  ) {
    throw new Error('Refusing to rebalance: demo record counts do not match the guarded synthetic shape');
  }

  await prisma.$transaction(async (tx) => {
    for (const update of updates) {
      await tx.expense.updateMany({
        where: { id: update.id, amount: { not: update.amount } },
        data: { amount: update.amount },
      });
      if (update.bankTransactionIds.length > 0) {
        await tx.bankTransaction.updateMany({
          where: {
            id: { in: update.bankTransactionIds },
            organizationId: demoOrganizationId,
            expenseId: update.id,
            amount: { not: update.amount },
          },
          data: { amount: update.amount },
        });
      }
    }
  }, { maxWait: 10000, timeout: 120000 });

  console.log(`Rebalanced ${updates.length} synthetic demo expenses across ${expenseDays.size} location-days`);
}

main().finally(() => prisma.$disconnect());
