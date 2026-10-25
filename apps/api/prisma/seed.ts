import {
  ExpenseClassification,
  ExpenseSource,
  ExtractionStatus,
  InvoiceStatus,
  BankCategorizationSource,
  BankProvider,
  BankReconciliationStatus,
  BankConnectionStatus,
  ManualRevenueType,
  MerchantRuleMatchType,
  OrganizationRole,
  Prisma,
  PrismaClient,
  ProductMatchConfidence,
  ProductMatchStatus,
  ReviewStatus,
  RevenueSource,
} from '@prisma/client';
import * as argon2 from 'argon2';
import { randomBytes } from 'crypto';

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

type ExpenseRecipe = readonly [
  slug: string,
  ratio: number,
  vendorName: string | null,
  description: string,
];

const downtownPrevious: readonly ExpenseRecipe[] = [
  ['food', .27, 'sysco', 'Food inventory'],
  ['labor', .29, 'adp', 'Hourly and salaried labor'],
  ['beverage', .035, 'us foods', 'Beverage inventory'],
  ['payroll-taxes', .03, 'adp', 'Payroll taxes'],
  ['rent', .085, 'main street properties', 'Restaurant occupancy'],
  ['utilities', .025, 'dte energy', 'Electric and gas service'],
  ['delivery-fees', .04, 'doordash', 'Delivery marketplace fees'],
  ['merchant-fees', .028, 'toast', 'Card processing'],
  ['supplies', .015, 'restaurant depot', 'Operating supplies'],
  ['insurance', .008, 'harbor insurance', 'Business insurance'],
  ['repairs-maintenance', .008, null, 'Repairs and maintenance'],
  ['marketing', .012, 'brightline marketing', 'Local marketing'],
  ['software-subscriptions', .004, 'toast', 'Restaurant software'],
  ['taxes', .015, null, 'Local business taxes'],
  ['professional-services', .005, null, 'Professional services'],
  ['equipment', .01, 'restaurant depot', 'Small equipment'],
];

const downtownRecent: readonly ExpenseRecipe[] = [
  ['food', .305, 'sysco', 'Food inventory'],
  ['labor', .34, 'adp', 'Hourly and salaried labor'],
  ['beverage', .03, 'us foods', 'Beverage inventory'],
  ['payroll-taxes', .032, 'adp', 'Payroll taxes'],
  ['rent', .06, 'main street properties', 'Restaurant occupancy'],
  ['utilities', .022, 'dte energy', 'Electric and gas service'],
  ['delivery-fees', .05, 'doordash', 'Delivery marketplace fees'],
  ['merchant-fees', .028, 'toast', 'Card processing'],
  ['supplies', .012, 'restaurant depot', 'Operating supplies'],
  ['insurance', .007, 'harbor insurance', 'Business insurance'],
  ['repairs-maintenance', .006, null, 'Repairs and maintenance'],
  ['marketing', .004, 'brightline marketing', 'Local marketing'],
  ['software-subscriptions', .004, 'toast', 'Restaurant software'],
  ['taxes', .009, null, 'Local business taxes'],
  ['professional-services', .003, null, 'Professional services'],
  ['equipment', .003, 'restaurant depot', 'Small equipment'],
];

// Current-month demo pressure creates deterministic Needs Attention signals
// without changing any non-demo organization data.
const downtownCurrent: readonly ExpenseRecipe[] = downtownRecent.map(
  ([slug, ratio, vendor, description]) => [
    slug,
    slug === 'food'
      ? .37
      : slug === 'labor'
      ? .40
      : slug === 'utilities'
      ? .033
      : ratio,
    vendor,
    description,
  ],
);

const lakesideStable: readonly ExpenseRecipe[] = [
  ['food', .26, 'local produce co.', 'Food inventory'],
  ['labor', .27, 'adp', 'Hourly and salaried labor'],
  ['beverage', .03, 'us foods', 'Beverage inventory'],
  ['payroll-taxes', .028, 'adp', 'Payroll taxes'],
  ['rent', .09, 'main street properties', 'Restaurant occupancy'],
  ['utilities', .025, 'dte energy', 'Electric and gas service'],
  ['delivery-fees', .02, 'uber eats', 'Delivery marketplace fees'],
  ['merchant-fees', .028, 'toast', 'Card processing'],
  ['supplies', .015, 'restaurant depot', 'Operating supplies'],
  ['insurance', .008, 'harbor insurance', 'Business insurance'],
  ['repairs-maintenance', .008, null, 'Repairs and maintenance'],
  ['marketing', .008, 'brightline marketing', 'Local marketing'],
  ['software-subscriptions', .004, 'toast', 'Restaurant software'],
  ['taxes', .012, null, 'Local business taxes'],
  ['professional-services', .004, null, 'Professional services'],
  ['equipment', .006, 'restaurant depot', 'Small equipment'],
];

// Synthetic Thai-restaurant operating mix for the Rochester demo location.
// It is inspired by the restaurant's public menu categories, not actual sales,
// purchases, vendors, or financial performance.
const bangkokCuisineStable: readonly ExpenseRecipe[] = [
  ['food', .31, 'thai specialty produce', 'Thai ingredients and fresh produce'],
  ['labor', .31, 'adp', 'Front and back of house labor'],
  ['beverage', .035, 'gordon food service', 'Beverage inventory'],
  ['payroll-taxes', .03, 'adp', 'Payroll taxes'],
  ['rent', .075, 'main street properties', 'Restaurant occupancy'],
  ['utilities', .026, 'dte energy', 'Electric and gas service'],
  ['delivery-fees', .045, 'doordash', 'Delivery marketplace fees'],
  ['merchant-fees', .029, 'toast', 'Card processing'],
  ['supplies', .014, 'gordon food service', 'Operating supplies'],
  ['insurance', .008, 'harbor insurance', 'Business insurance'],
  ['repairs-maintenance', .007, null, 'Repairs and maintenance'],
  ['marketing', .006, 'brightline marketing', 'Local marketing'],
  ['software-subscriptions', .004, 'toast', 'Restaurant software'],
  ['taxes', .011, null, 'Local business taxes'],
  ['professional-services', .004, null, 'Professional services'],
  ['equipment', .006, 'metro asian foods', 'Kitchen equipment and smallwares'],
];

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
        ? bangkokCuisineStable
        : date.getUTCFullYear() === seedToday.getUTCFullYear() &&
          date.getUTCMonth() === seedToday.getUTCMonth()
        ? downtownCurrent
        : isRecent
        ? downtownRecent
        : downtownPrevious;
      for (const [slug, ratio, normalizedVendor, description] of recipe) {
        expenseRows.push({
          organizationId: demoOrgId,
          restaurantLocationId: locationId,
          expenseCategoryId: categoryId(slug),
          vendorId: vendorId(normalizedVendor),
          date,
          amount: money(revenue * ratio),
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
  const demoAccounts = await Promise.all([
    prisma.bankAccount.create({
      data: { id: demoMainAccountId, bankConnectionId: connection.id, organizationId: demoOrgId, restaurantLocationId: bangkokCuisineId, providerAccountId: 'bangkok-main-checking', name: 'Bangkok Cuisine Operating', mask: '4242', subtype: 'checking', type: 'depository' },
    }),
    prisma.bankAccount.create({
      data: { id: demoDowntownAccountId, bankConnectionId: connection.id, organizationId: demoOrgId, restaurantLocationId: downtownId, providerAccountId: 'bangkok-downtown-checking', name: 'Downtown Operating', mask: '8181', subtype: 'checking', type: 'depository' },
    }),
  ]);
  for (const account of demoAccounts) {
    const expenses = await prisma.expense.findMany({
      where: { organizationId: demoOrgId, restaurantLocationId: account.restaurantLocationId!, description: { in: ['Electric and gas service', 'Restaurant occupancy'] } },
      orderBy: { date: 'desc' },
      take: 12,
    });
    await prisma.bankTransaction.createMany({
      data: [
        ...expenses.map((expense, index) => ({
          organizationId: demoOrgId,
          restaurantLocationId: account.restaurantLocationId,
          bankAccountId: account.id,
          providerTransactionId: `demo-expense-${account.id}-${index}`,
          postedDate: expense.date,
          merchantNameRaw: expense.description,
          merchantNameNormalized: expense.description,
          description: expense.description ?? 'Operating expense',
          amount: expense.amount,
          expenseId: expense.id,
          categoryId: expense.expenseCategoryId,
          vendorId: expense.vendorId,
          reconciliationStatus: BankReconciliationStatus.MATCHED_EXPENSE,
          categorizationSource: BankCategorizationSource.MANUAL,
        })),
        ...Array.from({ length: 12 }, (_, index) => {
          const postedDate = new Date(seedToday);
          postedDate.setUTCMonth(seedToday.getUTCMonth() - index);
          postedDate.setUTCDate(5);
          return {
            organizationId: demoOrgId,
            restaurantLocationId: account.restaurantLocationId,
            bankAccountId: account.id,
            providerTransactionId: `demo-deposit-${account.id}-${index}`,
            postedDate,
            merchantNameRaw: 'CARD SALES DEPOSIT',
            merchantNameNormalized: 'Card Sales Deposit',
            description: 'Synthetic merchant processor deposit',
            amount: new Prisma.Decimal(-money(18000 + ((index * 977) % 6000))),
            providerCategory: 'Deposit',
            providerCategoryId: 'DEPOSIT',
            reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW,
            categorizationSource: BankCategorizationSource.PROVIDER,
          };
        }),
      ],
    });
  }

  // Deterministic, reviewed invoice history for the demo organization only.
  // These records are synthetic and are never mixed with another tenant.
  const syntheticInvoices = [
    {
      id: '10000000-0000-4000-8000-000000000001',
      vendor: 'sysco',
      daysAgo: 80,
      lines: [
        { rawDescription: 'CHKN BRST BNLS SKLS 4/10 LB', sku: '384920', quantity: 12, unit: 'CASE', packSize: '4 x 10 lb', unitPrice: 91 },
        { rawDescription: 'FRY OIL CANOLA 35 LB', sku: '220410', quantity: 4, unit: 'JUG', packSize: '35 lb', unitPrice: 42 },
      ],
    },
    {
      id: '10000000-0000-4000-8000-000000000002',
      vendor: 'sysco',
      daysAgo: 40,
      lines: [
        { rawDescription: 'CHKN BRST BNLS  SKLS 4/10 LB', sku: '384920', quantity: 12, unit: 'CASE', packSize: '4 x 10 lb', unitPrice: 98 },
        { rawDescription: 'FRY OIL CANOLA 35 LB', sku: '220410', quantity: 4, unit: 'JUG', packSize: '35 lb', unitPrice: 42 },
      ],
    },
    {
      id: '10000000-0000-4000-8000-000000000003',
      vendor: 'sysco',
      daysAgo: 5,
      lines: [
        { rawDescription: 'CHKN BRST BNLS SKLS 4/10 LB', sku: '384920', quantity: 12, unit: 'CASE', packSize: '4 x 10 lb', unitPrice: 106.5 },
        { rawDescription: 'FRY OIL CANOLA 35 LB', sku: '220410', quantity: 4, unit: 'JUG', packSize: '35 lb', unitPrice: 42 },
      ],
    },
    {
      id: '10000000-0000-4000-8000-000000000004',
      vendor: 'us foods',
      daysAgo: 60,
      lines: [{ rawDescription: 'COLA SYRUP 5 GAL BIB', sku: 'COLA-5', quantity: 9, unit: 'BIB', packSize: '5 gal', unitPrice: 55 }],
    },
    {
      id: '10000000-0000-4000-8000-000000000005',
      vendor: 'us foods',
      daysAgo: 10,
      lines: [{ rawDescription: 'COLA SYRUP 5 GAL BIB', sku: 'COLA-5', quantity: 9, unit: 'BIB', packSize: '5 gal', unitPrice: 49 }],
    },
    {
      id: '10000000-0000-4000-8000-000000000006',
      vendor: 'restaurant depot',
      daysAgo: 50,
      lines: [{ rawDescription: 'NITRILE GLOVES LARGE', sku: 'GLOVE-L', quantity: 2, unit: 'CASE', packSize: '10 x 100', unitPrice: 64 }],
    },
    {
      id: '10000000-0000-4000-8000-000000000007',
      vendor: 'restaurant depot',
      daysAgo: 5,
      lines: [{ rawDescription: 'NITRILE GLOVES LARGE', sku: 'GLOVE-L', quantity: 2, unit: 'CASE', packSize: '5 x 100', unitPrice: 38 }],
    },
    {
      id: '10000000-0000-4000-8000-000000000008',
      vendor: 'us foods',
      daysAgo: 10,
      lines: [
        { rawDescription: 'CHICKEN BREAST B/S 40LB', sku: 'USF-CHKN-40', quantity: 12, unit: 'CASE', packSize: '40 lb', unitPrice: 94.2 },
        { rawDescription: 'CHICKEN BREAST B/S 20LB', sku: 'USF-CHKN-20', quantity: 5, unit: 'CASE', packSize: '20 lb', unitPrice: 54 },
        { rawDescription: 'FROZEN CHICKEN THIGH 40LB', sku: 'USF-THIGH-40', quantity: 4, unit: 'CASE', packSize: '40 lb', unitPrice: 72 },
      ],
    },
  ] as const;

  await prisma.productMatchDecision.deleteMany({ where: { organizationId: demoOrgId } });
  await prisma.productGroup.deleteMany({ where: { organizationId: demoOrgId } });

  for (const seeded of syntheticInvoices) {
    const invoiceDate = new Date(seedToday);
    invoiceDate.setUTCDate(seedToday.getUTCDate() - seeded.daysAgo);
    const selectedVendorId = vendorId(seeded.vendor)!;
    const invoiceTotal = seeded.lines.reduce((sum, line) => sum + line.quantity * line.unitPrice, 0);
    const invoiceLocationId = seeded.id.endsWith('0001') || seeded.id.endsWith('0002')
      ? bangkokCuisineId
      : downtownId;
    await prisma.invoice.upsert({
      where: { id: seeded.id },
      update: {
        restaurantLocationId: invoiceLocationId,
        vendorId: selectedVendorId,
        invoiceDate,
        invoiceNumber: `DEMO-${seeded.id.slice(-4)}`,
        total: new Prisma.Decimal(invoiceTotal),
        status: InvoiceStatus.COMPLETED,
        extractionStatus: ExtractionStatus.COMPLETED,
        reviewStatus: ReviewStatus.REVIEWED,
        reviewedAt: invoiceDate,
        reviewedByUserId: user.id,
      },
      create: {
        id: seeded.id,
        organizationId: demoOrgId,
        restaurantLocationId: invoiceLocationId,
        vendorId: selectedVendorId,
        fileName: `synthetic-${seeded.id}.pdf`,
        originalFileName: 'Synthetic demo invoice.pdf',
        fileType: 'application/pdf',
        fileSize: 1,
        storageKey: `synthetic-price-history/${seeded.id}.pdf`,
        invoiceDate,
        invoiceNumber: `DEMO-${seeded.id.slice(-4)}`,
        total: new Prisma.Decimal(invoiceTotal),
        status: InvoiceStatus.COMPLETED,
        extractionStatus: ExtractionStatus.COMPLETED,
        reviewStatus: ReviewStatus.REVIEWED,
        reviewedAt: invoiceDate,
        reviewedByUserId: user.id,
        createdByUserId: user.id,
      },
    });
    await prisma.invoiceLineItem.deleteMany({ where: { invoiceId: seeded.id } });
    await prisma.invoiceLineItem.createMany({
      data: seeded.lines.map((line, index) => ({
        invoiceId: seeded.id,
        organizationId: demoOrgId,
        restaurantLocationId: invoiceLocationId,
        lineNumber: index + 1,
        rawDescription: line.rawDescription,
        sku: line.sku,
        quantity: new Prisma.Decimal(line.quantity),
        unit: line.unit,
        packSize: line.packSize,
        unitPrice: new Prisma.Decimal(line.unitPrice),
        extendedPrice: new Prisma.Decimal(line.quantity * line.unitPrice),
        confidence: new Prisma.Decimal(1),
      })),
    });
  }

  const [syscoChicken, usFoodsChicken] = await Promise.all([
    prisma.invoiceLineItem.findFirstOrThrow({ where: { invoiceId: '10000000-0000-4000-8000-000000000003', sku: '384920' } }),
    prisma.invoiceLineItem.findFirstOrThrow({ where: { invoiceId: '10000000-0000-4000-8000-000000000008', sku: 'USF-CHKN-40' } }),
  ]);
  const chickenGroup = await prisma.productGroup.create({
    data: {
      id: '20000000-0000-4000-8000-000000000001',
      organizationId: demoOrgId,
      restaurantLocationId: downtownId,
      displayName: 'Boneless Skinless Chicken Breast',
      members: {
        create: [
          { invoiceLineItemId: syscoChicken.id, vendorId: vendorId('sysco')!, confirmed: true },
          { invoiceLineItemId: usFoodsChicken.id, vendorId: vendorId('us foods')!, confirmed: true },
        ],
      },
    },
  });
  await prisma.productMatchDecision.create({
    data: {
      organizationId: demoOrgId,
      restaurantLocationId: downtownId,
      candidateLineItemAId: [syscoChicken.id, usFoodsChicken.id].sort()[0],
      candidateLineItemBId: [syscoChicken.id, usFoodsChicken.id].sort()[1],
      status: ProductMatchStatus.CONFIRMED,
      confidence: ProductMatchConfidence.HIGH,
      reason: 'Synthetic demo confirmation: compatible case unit and 40 lb total weight',
      productGroupId: chickenGroup.id,
      reviewedByUserId: user.id,
      reviewedAt: seedToday,
    },
  });

  console.log(
    `Public demo seeded through ${seedToday.toISOString().slice(0, 10)} for ${demoOrgId}`,
  );
}

main().finally(() => prisma.$disconnect());
