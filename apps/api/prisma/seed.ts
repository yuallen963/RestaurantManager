import {
  ExpenseClassification,
  ExpenseSource,
  BankProvider,
  BankConnectionStatus,
  ManualRevenueType,
  MerchantRuleMatchType,
  OrganizationRole,
  Prisma,
  PrismaClient,
  RevenueSource,
} from '@prisma/client';
import * as argon2 from 'argon2';
import { randomBytes } from 'crypto';
import {
  demoExpenseAmount,
  downtownExpenseRecipe,
  mainExpenseRecipe,
} from './demo-financial-profile';
import { replaceDemoBankingAndInvoices } from './demo-banking-invoices';

const prisma = new PrismaClient();

const categories = [
  ['Food', 'food', ExpenseClassification.FOOD],
  ['Beverage', 'beverage', ExpenseClassification.BEVERAGE],
  ['Labor', 'labor', ExpenseClassification.LABOR],
  ['Payroll Taxes', 'payroll-taxes', ExpenseClassification.PAYROLL_TAX],
  ['Rent', 'rent', ExpenseClassification.OCCUPANCY],
  ['Utilities', 'utilities', ExpenseClassification.UTILITIES],
  ['Insurance', 'insurance', ExpenseClassification.OPERATING],
  ['Delivery Fees', 'delivery-fees', ExpenseClassification.DELIVERY],
  ['Merchant Fees', 'merchant-fees', ExpenseClassification.FEES],
  ['Supplies', 'supplies', ExpenseClassification.OPERATING],
  ['Repairs & Maintenance', 'repairs-maintenance', ExpenseClassification.OPERATING],
  ['Marketing', 'marketing', ExpenseClassification.OPERATING],
  ['Software & Subscriptions', 'software-subscriptions', ExpenseClassification.OPERATING],
  ['Equipment', 'equipment', ExpenseClassification.OPERATING],
  ['Professional Services', 'professional-services', ExpenseClassification.OPERATING],
  ['Taxes', 'taxes', ExpenseClassification.OTHER],
  ['Miscellaneous', 'miscellaneous', ExpenseClassification.OTHER],
] as const;

const demoEmail = 'demo@profitlens.local';
const demoOrgId = '00000000-0000-4000-8000-000000000001';
const downtownId = '00000000-0000-4000-8000-000000000002';
const lakesideId = '00000000-0000-4000-8000-000000000003';
const bangkokCuisineId = '00000000-0000-4000-8000-000000000004';
const demoConnectionId = '00000000-0000-4000-8000-000000000005';
const demoMainAccountId = '00000000-0000-4000-8000-000000000006';
const demoDowntownAccountId = '00000000-0000-4000-8000-000000000007';

const vendors = [
  ['Sysco', 'sysco'],
  ['US Foods', 'us foods'],
  ['DTE Energy', 'dte energy'],
  ['DoorDash', 'doordash'],
  ['Uber Eats', 'uber eats'],
  ['Toast', 'toast'],
  ['ADP', 'adp'],
  ['Comcast Business', 'comcast business'],
  ['Restaurant Depot', 'restaurant depot'],
  ['Local Produce Co.', 'local produce co.'],
  ['Main Street Properties', 'main street properties'],
  ['Harbor Insurance', 'harbor insurance'],
  ['Brightline Marketing', 'brightline marketing'],
  ['Gordon Food Service', 'gordon food service'],
  ['Thai Specialty Produce', 'thai specialty produce'],
  ['Metro Asian Foods', 'metro asian foods'],
] as const;

const money = (value: number) => Math.round(value * 100) / 100;

async function main() {
  // Capture the clock once so every generated date in this seed run is based
  // on the same deterministic UTC calendar day.
  const seedNow = new Date();
  const seedToday = new Date(
    Date.UTC(
      seedNow.getUTCFullYear(),
      seedNow.getUTCMonth(),
      seedNow.getUTCDate(),
      12,
    ),
  );

  const existingOrganization = await prisma.organization.findUnique({
    where: { id: demoOrgId },
    include: {
      memberships: { include: { user: { select: { email: true } } } },
      locations: { select: { id: true } },
      bankConnections: { select: { provider: true } },
    },
  });
  if (existingOrganization) {
    const expectedLocationIds = new Set([downtownId, lakesideId, bangkokCuisineId]);
    const unsafe =
      !['Demo Restaurant Group', 'FundWell Public Demo'].includes(existingOrganization.name) ||
      existingOrganization.memberships.some((membership) => membership.user.email !== demoEmail) ||
      existingOrganization.locations.some((location) => !expectedLocationIds.has(location.id)) ||
      existingOrganization.bankConnections.some((connection) => connection.provider !== BankProvider.DEMO);
    if (unsafe) throw new Error('Refusing to seed: the fixed demo organization contains non-demo ownership or data');
  }
  const existingDemoUser = await prisma.user.findUnique({
    where: { email: demoEmail },
    select: { memberships: { select: { organizationId: true } } },
  });
  if (existingDemoUser?.memberships.some((membership) => membership.organizationId !== demoOrgId)) {
    throw new Error('Refusing to seed: the demo user belongs to a non-demo organization');
  }

  for (const [name, slug, classification] of categories) {
    const found = await prisma.expenseCategory.findFirst({
      where: { organizationId: null, slug },
    });
    if (!found) {
      await prisma.expenseCategory.create({
        data: { name, slug, classification, isSystem: true },
      });
    }
  }

  const user = await prisma.user.upsert({
    where: { email: demoEmail },
    update: {
      passwordHash: await argon2.hash(randomBytes(32).toString('base64url')),
      emailVerifiedAt: new Date(),
      disabledAt: null,
      deletedAt: null,
    },
    create: {
      email: demoEmail,
      passwordHash: await argon2.hash(randomBytes(32).toString('base64url')),
      firstName: 'Demo',
      lastName: 'Owner',
      emailVerifiedAt: new Date(),
    },
  });
  await prisma.organization.upsert({
    where: { id: demoOrgId },
    update: { name: 'FundWell Public Demo' },
    create: { id: demoOrgId, name: 'FundWell Public Demo' },
  });
  await prisma.organizationMember.upsert({
    where: {
      userId_organizationId: {
        userId: user.id,
        organizationId: demoOrgId,
      },
    },
    update: { role: OrganizationRole.OWNER },
    create: {
      userId: user.id,
      organizationId: demoOrgId,
      role: OrganizationRole.OWNER,
    },
  });
  for (const [id, name, addressLine1, city, state, postalCode, invoiceEmailToken] of [
    [downtownId, 'Bangkok Cuisine — Downtown', null, 'Rochester', 'MI', null, 'd84f7c9a61e24337b95d5b822e48a3f1'],
    [
      bangkokCuisineId,
      'Bangkok Cuisine',
      '727 N Main St',
      'Rochester',
      'MI',
      '48307',
      'f71b3d9c82a64e09a45c1d37b8e260af',
    ],
  ] as const) {
    await prisma.restaurantLocation.upsert({
      where: { id },
      update: { name, addressLine1, city, state, postalCode, invoiceEmailToken },
      create: {
        id,
        name,
        organizationId: demoOrgId,
        addressLine1,
        city,
        state,
        postalCode,
        invoiceEmailToken,
      },
    });
  }

  const seededVendors = await Promise.all(
    vendors.map(([name, normalizedName]) =>
      prisma.vendor.upsert({
        where: {
          organizationId_normalizedName: {
            organizationId: demoOrgId,
            normalizedName,
          },
        },
        update: { name },
        create: { organizationId: demoOrgId, name, normalizedName },
      }),
    ),
  );
  const categoryRows = await prisma.expenseCategory.findMany({
    where: { organizationId: null },
  });
  const categoryId = (slug: string) =>
    categoryRows.find((category) => category.slug === slug)!.id;
  const vendorId = (normalizedName: string | null) =>
    normalizedName == null
      ? null
      : seededVendors.find(
          (vendor) => vendor.normalizedName === normalizedName,
        )!.id;

  await prisma.merchantRule.deleteMany({ where: { organizationId: demoOrgId } });
  await prisma.merchantRule.createMany({
    data: [
      { organizationId: demoOrgId, matchType: MerchantRuleMatchType.CONTAINS, matchValue: 'SYSCO', normalizedMerchantName: 'Sysco', vendorId: vendorId('sysco'), expenseCategoryId: categoryId('food'), createdByUserId: user.id },
      { organizationId: demoOrgId, matchType: MerchantRuleMatchType.CONTAINS, matchValue: 'ADP', normalizedMerchantName: 'ADP', vendorId: vendorId('adp'), expenseCategoryId: categoryId('labor'), createdByUserId: user.id },
      { organizationId: demoOrgId, matchType: MerchantRuleMatchType.CONTAINS, matchValue: 'DTE', normalizedMerchantName: 'DTE Energy', vendorId: vendorId('dte energy'), expenseCategoryId: categoryId('utilities'), createdByUserId: user.id },
    ],
  });

  const revenueRows: Prisma.RevenueEntryCreateManyInput[] = [];
  const expenseRows: Prisma.ExpenseCreateManyInput[] = [];

  for (const [locationId, baseRevenue] of [
    [downtownId, 2600],
    [bangkokCuisineId, 2250],
  ] as const) {
    for (let index = 0; index < 365; index += 1) {
      const daysAgo = 364 - index;
      const date = new Date(seedToday);
      date.setUTCDate(seedToday.getUTCDate() - daysAgo);
      const dayOfWeek = date.getUTCDay();
      const isWeekendPeak = dayOfWeek === 5 || dayOfWeek === 6;
      const isEarlyWeek = dayOfWeek === 1 || dayOfWeek === 2;
      const isRecent = daysAgo < 30;
      const isPrevious = daysAgo >= 30 && daysAgo < 60;
      const trend = locationId === downtownId
        ? (isRecent ? 1.04 : isPrevious ? 1 : .98)
        : locationId === bangkokCuisineId
        ? (isRecent ? 1.02 : 1)
        : (isRecent ? 1.01 : 1);
      const dailyVariation = (index * 37) % 240;
      const revenue = money(
        (baseRevenue +
          dailyVariation +
          (isWeekendPeak ? (locationId === downtownId ? 850 : 650) : 0) -
          (isEarlyWeek ? (locationId === downtownId ? 260 : 200) : 0)) *
          trend,
      );

      const cashRevenue = money(revenue * (0.24 + ((index % 5) - 2) * 0.01));
      revenueRows.push(
        {
          organizationId: demoOrgId,
          restaurantLocationId: locationId,
          date,
          amount: cashRevenue,
          source: RevenueSource.MANUAL,
          manualType: ManualRevenueType.CASH,
          notes: 'Synthetic daily cash sales excluding tax and tips',
          createdByUserId: user.id,
        },
        {
          organizationId: demoOrgId,
          restaurantLocationId: locationId,
          date,
          amount: money(revenue - cashRevenue),
          source: RevenueSource.MANUAL,
          manualType: ManualRevenueType.CARD,
          notes: 'Synthetic daily card sales excluding tax and tips',
          createdByUserId: user.id,
        },
      );

      const recipe = locationId === bangkokCuisineId
        ? mainExpenseRecipe
        : downtownExpenseRecipe;
      for (const [slug, ratio, normalizedVendor, description] of recipe) {
        expenseRows.push({
          organizationId: demoOrgId,
          restaurantLocationId: locationId,
          expenseCategoryId: categoryId(slug),
          vendorId: vendorId(normalizedVendor),
          date,
          amount: demoExpenseAmount(revenue, ratio, date, locationId),
          description,
          source: ExpenseSource.MANUAL,
          createdByUserId: user.id,
        });
      }
    }
  }

  await prisma.$transaction([
    prisma.bankConnection.deleteMany({ where: { organizationId: demoOrgId } }),
    prisma.revenueEntry.deleteMany({ where: { organizationId: demoOrgId } }),
    prisma.expense.deleteMany({ where: { organizationId: demoOrgId } }),
  ]);
  await prisma.revenueEntry.createMany({ data: revenueRows });
  await prisma.expense.createMany({ data: expenseRows });
  await prisma.restaurantLocation.deleteMany({
    where: { id: lakesideId, organizationId: demoOrgId },
  });

  const connection = await prisma.bankConnection.create({
    data: {
      id: demoConnectionId,
      organizationId: demoOrgId,
      provider: BankProvider.DEMO,
      providerItemId: 'fundwell-public-demo',
      encryptedAccessToken: 'synthetic-demo-no-bank-credential',
      institutionId: 'fundwell-demo-bank',
      institutionName: 'FundWell Demo Bank',
      status: BankConnectionStatus.CONNECTED,
      lastSyncAt: seedToday,
      createdByUserId: user.id,
    },
  });
  await Promise.all([
    prisma.bankAccount.create({
      data: { id: demoMainAccountId, bankConnectionId: connection.id, organizationId: demoOrgId, restaurantLocationId: bangkokCuisineId, providerAccountId: 'bangkok-main-checking', name: 'Bangkok Cuisine Operating', mask: '4242', subtype: 'checking', type: 'depository' },
    }),
    prisma.bankAccount.create({
      data: { id: demoDowntownAccountId, bankConnectionId: connection.id, organizationId: demoOrgId, restaurantLocationId: downtownId, providerAccountId: 'bangkok-downtown-checking', name: 'Downtown Operating', mask: '8181', subtype: 'checking', type: 'depository' },
    }),
  ]);
  await prisma.$transaction(
    (tx) => replaceDemoBankingAndInvoices(tx, seedToday, user.id),
    { maxWait: 10000, timeout: 120000 },
  );

  console.log(
    `Public demo seeded through ${seedToday.toISOString().slice(0, 10)} for ${demoOrgId}`,
  );
}

main().finally(() => prisma.$disconnect());
