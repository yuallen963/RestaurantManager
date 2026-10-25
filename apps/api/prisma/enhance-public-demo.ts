import { BankProvider, PrismaClient } from '@prisma/client';
import { replaceDemoBankingAndInvoices } from './demo-banking-invoices';
import {
  demoDowntownLocationId,
  demoMainLocationId,
  demoOrganizationId,
} from './demo-financial-profile';

const prisma = new PrismaClient();

async function main() {
  if (process.env.APPLY_PUBLIC_DEMO_ENHANCEMENT !== 'true') {
    throw new Error('Refusing to write without APPLY_PUBLIC_DEMO_ENHANCEMENT=true');
  }
  const organization = await prisma.organization.findUnique({
    where: { id: demoOrganizationId },
    select: {
      name: true,
      memberships: { select: { userId: true, user: { select: { email: true } } } },
      locations: { select: { id: true } },
      bankConnections: {
        select: { provider: true, accounts: { select: { id: true, restaurantLocationId: true } } },
      },
      _count: { select: { bankTransactions: true } },
    },
  });
  if (!organization || organization.name !== 'FundWell Public Demo') {
    throw new Error('Refusing to enhance: public demo organization identity mismatch');
  }
  const expectedLocations = [demoDowntownLocationId, demoMainLocationId].sort();
  const actualLocations = organization.locations.map(({ id }) => id).sort();
  const connection = organization.bankConnections[0];
  if (
    organization.memberships.length !== 1 ||
    organization.memberships[0].user.email !== 'demo@profitlens.local' ||
    actualLocations.length !== 2 ||
    actualLocations.some((id, index) => id !== expectedLocations[index]) ||
    organization.bankConnections.length !== 1 ||
    connection.provider !== BankProvider.DEMO ||
    connection.accounts.length !== 2 ||
    ![48, 120].includes(organization._count.bankTransactions)
  ) {
    throw new Error('Refusing to enhance: demo tenant shape or ownership is unexpected');
  }
  const [invoiceCount, revenueBefore, expenseBefore] = await Promise.all([
    prisma.invoice.count({ where: { organizationId: demoOrganizationId } }),
    prisma.revenueEntry.aggregate({
      where: { organizationId: demoOrganizationId },
      _count: true,
      _sum: { amount: true },
    }),
    prisma.expense.aggregate({
      where: { organizationId: demoOrganizationId },
      _count: true,
      _sum: { amount: true },
    }),
  ]);
  if (
    ![8, 24].includes(invoiceCount) ||
    revenueBefore._count !== 1460 ||
    expenseBefore._count !== 11680
  ) {
    throw new Error('Refusing to enhance: synthetic financial record counts are unexpected');
  }

  const seedToday = new Date();
  seedToday.setUTCHours(12, 0, 0, 0);
  const result = await prisma.$transaction(
    (tx) =>
      replaceDemoBankingAndInvoices(
        tx,
        seedToday,
        organization.memberships[0].userId,
      ),
    { maxWait: 10000, timeout: 120000 },
  );
  const [revenueAfter, expenseAfter] = await Promise.all([
    prisma.revenueEntry.aggregate({
      where: { organizationId: demoOrganizationId },
      _count: true,
      _sum: { amount: true },
    }),
    prisma.expense.aggregate({
      where: { organizationId: demoOrganizationId },
      _count: true,
      _sum: { amount: true },
    }),
  ]);
  if (
    revenueAfter._count !== revenueBefore._count ||
    revenueAfter._sum.amount?.toString() !== revenueBefore._sum.amount?.toString() ||
    expenseAfter._count !== expenseBefore._count ||
    expenseAfter._sum.amount?.toString() !== expenseBefore._sum.amount?.toString()
  ) {
    throw new Error('Financial totals changed unexpectedly during demo enhancement');
  }
  console.log(
    `Enhanced synthetic demo with ${result.bankTransactions} bank transactions and ${result.invoices} invoices`,
  );
}

main().finally(() => prisma.$disconnect());
