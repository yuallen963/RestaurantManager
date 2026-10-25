import {
  BankCategorizationSource,
  BankReconciliationStatus,
  ExtractionStatus,
  InvoiceStatus,
  ProductMatchConfidence,
  ProductMatchStatus,
  Prisma,
  ReviewStatus,
} from '@prisma/client';
import {
  demoDowntownLocationId,
  demoMainLocationId,
  demoOrganizationId,
} from './demo-financial-profile';

const mainAccountId = '00000000-0000-4000-8000-000000000006';
const downtownAccountId = '00000000-0000-4000-8000-000000000007';

type Line = {
  description: string;
  sku: string;
  quantity: number;
  unit: string;
  packSize: string;
  unitPrice: number;
};

type InvoiceSpec = {
  id: string;
  locationId: string;
  vendor: string;
  daysAgo: number;
  taxRate: number;
  paid: boolean;
  lines: Line[];
};

const money = (value: number) => Math.round(value * 100) / 100;
const invoiceId = (index: number) =>
  `10000000-0000-4000-8000-${index.toString().padStart(12, '0')}`;
const lineId = (invoiceIndex: number, lineIndex: number) =>
  `30000000-0000-4000-8000-${invoiceIndex
    .toString()
    .padStart(6, '0')}${lineIndex.toString().padStart(6, '0')}`;
const transactionId = (locationIndex: number, type: number, index: number) =>
  `40000000-0000-4000-8000-${locationIndex}${type}${index
    .toString()
    .padStart(10, '0')}`;

const lineSets: Record<string, Line[][]> = {
  sysco: [
    [
      { description: 'CHKN BRST BNLS SKLS 4/10 LB', sku: '384920', quantity: 12, unit: 'CASE', packSize: '4 x 10 lb', unitPrice: 106.5 },
      { description: 'FRY OIL CANOLA 35 LB', sku: '220410', quantity: 4, unit: 'JUG', packSize: '35 lb', unitPrice: 42 },
      { description: 'JASMINE RICE 25 LB', sku: 'RICE-25', quantity: 6, unit: 'BAG', packSize: '25 lb', unitPrice: 31.5 },
    ],
    [
      { description: 'CHKN BRST BNLS SKLS 4/10 LB', sku: '384920', quantity: 10, unit: 'CASE', packSize: '4 x 10 lb', unitPrice: 102 },
      { description: 'COCONUT MILK 6/10 CAN', sku: 'COCO-610', quantity: 5, unit: 'CASE', packSize: '6 x 10 can', unitPrice: 38 },
    ],
  ],
  'us foods': [
    [
      { description: 'CHICKEN BREAST B/S 40LB', sku: 'USF-CHKN-40', quantity: 12, unit: 'CASE', packSize: '40 lb', unitPrice: 94.2 },
      { description: 'FROZEN CHICKEN THIGH 40LB', sku: 'USF-THIGH-40', quantity: 4, unit: 'CASE', packSize: '40 lb', unitPrice: 72 },
    ],
    [
      { description: 'COLA SYRUP 5 GAL BIB', sku: 'COLA-5', quantity: 9, unit: 'BIB', packSize: '5 gal', unitPrice: 49 },
      { description: 'SPARKLING WATER 24/12 OZ', sku: 'WATER-24', quantity: 8, unit: 'CASE', packSize: '24 x 12 oz', unitPrice: 21 },
    ],
  ],
  'restaurant depot': [
    [
      { description: 'NITRILE GLOVES LARGE', sku: 'GLOVE-L', quantity: 4, unit: 'CASE', packSize: '10 x 100', unitPrice: 64 },
      { description: 'TAKEOUT CONTAINER 200 CT', sku: 'TOGO-200', quantity: 6, unit: 'CASE', packSize: '200 count', unitPrice: 43 },
    ],
  ],
  'thai specialty produce': [
    [
      { description: 'THAI BASIL 5 LB', sku: 'BASIL-5', quantity: 8, unit: 'CASE', packSize: '5 lb', unitPrice: 34 },
      { description: 'GALANGAL ROOT 10 LB', sku: 'GAL-10', quantity: 4, unit: 'CASE', packSize: '10 lb', unitPrice: 47 },
      { description: 'MAKRUT LIME LEAVES 2 LB', sku: 'LIME-2', quantity: 5, unit: 'CASE', packSize: '2 lb', unitPrice: 29 },
    ],
  ],
  'metro asian foods': [
    [
      { description: 'RICE NOODLES 30/14 OZ', sku: 'NOODLE-30', quantity: 7, unit: 'CASE', packSize: '30 x 14 oz', unitPrice: 52 },
      { description: 'FISH SAUCE 12/24 OZ', sku: 'FISH-12', quantity: 5, unit: 'CASE', packSize: '12 x 24 oz', unitPrice: 44 },
    ],
  ],
  'gordon food service': [
    [
      { description: 'COCONUT MILK 6/10 CAN', sku: 'GFS-COCO', quantity: 8, unit: 'CASE', packSize: '6 x 10 can', unitPrice: 36 },
      { description: 'PAPER NAPKINS 4000 CT', sku: 'NAPKIN-4K', quantity: 3, unit: 'CASE', packSize: '4000 count', unitPrice: 48 },
    ],
  ],
};

export const demoInvoiceSpecs = (): InvoiceSpec[] => {
  const locations = [demoMainLocationId, demoDowntownLocationId];
  const vendorCycles = [
    ['thai specialty produce', 'metro asian foods', 'gordon food service', 'sysco'],
    ['sysco', 'us foods', 'restaurant depot', 'gordon food service'],
  ];
  const specs: InvoiceSpec[] = [];
  for (let locationIndex = 0; locationIndex < locations.length; locationIndex += 1) {
    for (let month = 0; month < 12; month += 1) {
      const index = locationIndex * 12 + month + 1;
      const vendor = vendorCycles[locationIndex][month % 4];
      const templates = lineSets[vendor];
      specs.push({
        id: invoiceId(index),
        locationId: locations[locationIndex],
        vendor,
        daysAgo: 8 + month * 28 + locationIndex * 3,
        taxRate: vendor === 'restaurant depot' ? .06 : 0,
        paid: month >= 1 && month <= 4,
        lines: templates[Math.floor(month / 4) % templates.length],
      });
    }
  }
  return specs;
};

export async function replaceDemoBankingAndInvoices(
  tx: Prisma.TransactionClient,
  seedToday: Date,
  userId: string,
) {
  const [vendors, categories, accounts] = await Promise.all([
    tx.vendor.findMany({
      where: { organizationId: demoOrganizationId },
      select: { id: true, name: true, normalizedName: true },
    }),
    tx.expenseCategory.findMany({
      where: { organizationId: null },
      select: { id: true, slug: true },
    }),
    tx.bankAccount.findMany({
      where: { organizationId: demoOrganizationId },
      select: { id: true, restaurantLocationId: true },
    }),
  ]);
  const vendorId = (name: string) => {
    const value = vendors.find((vendor) => vendor.normalizedName === name)?.id;
    if (!value) throw new Error(`Missing synthetic demo vendor: ${name}`);
    return value;
  };
  const categoryId = (slug: string) => {
    const value = categories.find((category) => category.slug === slug)?.id;
    if (!value) throw new Error(`Missing synthetic demo category: ${slug}`);
    return value;
  };
  const vendorName = (id: string | null) =>
    id ? vendors.find((vendor) => vendor.id === id)?.name ?? null : null;
  const expectedAccounts = new Map([
    [demoMainLocationId, mainAccountId],
    [demoDowntownLocationId, downtownAccountId],
  ]);
  if (
    accounts.length !== 2 ||
    accounts.some(
      (account) => expectedAccounts.get(account.restaurantLocationId ?? '') !== account.id,
    )
  ) {
    throw new Error('Refusing to enhance: unexpected demo bank accounts');
  }

  await tx.productMatchDecision.deleteMany({ where: { organizationId: demoOrganizationId } });
  await tx.productGroup.deleteMany({ where: { organizationId: demoOrganizationId } });
  await tx.bankTransaction.deleteMany({ where: { organizationId: demoOrganizationId } });
  await tx.invoice.deleteMany({ where: { organizationId: demoOrganizationId } });

  const specs = demoInvoiceSpecs();
  for (let specIndex = 0; specIndex < specs.length; specIndex += 1) {
    const spec = specs[specIndex];
    const date = new Date(seedToday);
    date.setUTCDate(seedToday.getUTCDate() - spec.daysAgo);
    const dueDate = new Date(date);
    dueDate.setUTCDate(date.getUTCDate() + 30);
    const subtotal = money(
      spec.lines.reduce((sum, line) => sum + line.quantity * line.unitPrice, 0),
    );
    const tax = money(subtotal * spec.taxRate);
    await tx.invoice.create({
      data: {
        id: spec.id,
        organizationId: demoOrganizationId,
        restaurantLocationId: spec.locationId,
        vendorId: vendorId(spec.vendor),
        fileName: 'synthetic-demo-record',
        originalFileName: 'Synthetic demo invoice — no uploaded document',
        fileType: 'application/x-fundwell-demo',
        fileSize: 0,
        storageKey: `synthetic-demo/no-document/${spec.id}`,
        invoiceDate: date,
        dueDate,
        invoiceNumber: `FW-${date.toISOString().slice(0, 7).replace('-', '')}-${
          specIndex + 101
        }`,
        subtotal: new Prisma.Decimal(subtotal),
        tax: new Prisma.Decimal(tax),
        total: new Prisma.Decimal(money(subtotal + tax)),
        currency: 'USD',
        notes: spec.paid
          ? 'Synthetic demo invoice with a matched bank payment'
          : 'Synthetic demo invoice awaiting payment',
        status: InvoiceStatus.COMPLETED,
        extractionStatus: ExtractionStatus.COMPLETED,
        extractionProvider: 'synthetic-demo-generator',
        extractionModel: 'none',
        extractionConfidence: new Prisma.Decimal(1),
        reviewStatus: ReviewStatus.REVIEWED,
        reviewedAt: date,
        reviewedByUserId: userId,
        createdByUserId: userId,
        lineItems: {
          create: spec.lines.map((line, lineIndex) => ({
            id: lineId(specIndex + 1, lineIndex + 1),
            organizationId: demoOrganizationId,
            restaurantLocationId: spec.locationId,
            lineNumber: lineIndex + 1,
            rawDescription: line.description,
            normalizedName: line.description.toLowerCase(),
            sku: line.sku,
            quantity: new Prisma.Decimal(line.quantity),
            unit: line.unit,
            packSize: line.packSize,
            unitPrice: new Prisma.Decimal(line.unitPrice),
            extendedPrice: new Prisma.Decimal(money(line.quantity * line.unitPrice)),
            confidence: new Prisma.Decimal(1),
          })),
        },
      },
    });
  }

  const accountPlans = [
    { locationId: demoMainLocationId, accountId: mainAccountId, locationIndex: 1 },
    { locationId: demoDowntownLocationId, accountId: downtownAccountId, locationIndex: 2 },
  ];
  const expenseDescriptions = [
    'Thai ingredients and fresh produce',
    'Food inventory',
    'Front and back of house labor',
    'Hourly and salaried labor',
    'Restaurant occupancy',
    'Electric and gas service',
  ];
  for (const plan of accountPlans) {
    const locationSpecs = specs.filter((spec) => spec.locationId === plan.locationId);
    const matchedInvoices = locationSpecs.filter((spec) => spec.paid);
    const expenses = await tx.expense.findMany({
      where: {
        organizationId: demoOrganizationId,
        restaurantLocationId: plan.locationId,
        description: { in: expenseDescriptions },
      },
      orderBy: { date: 'desc' },
    });
    const selectedExpenses = ['food', 'labor', 'rent', 'utilities'].flatMap((slug) => {
      const id = categoryId(slug);
      return expenses.filter((expense) => expense.expenseCategoryId === id).slice(0, 12);
    });
    if (selectedExpenses.length !== 48 || matchedInvoices.length !== 4) {
      throw new Error('Refusing to enhance: incomplete synthetic expense or invoice history');
    }
    const skippedExpenseIds = new Set(selectedExpenses.slice(0, 4).map(({ id }) => id));
    const payableExpenses = selectedExpenses.filter(({ id }) => !skippedExpenseIds.has(id));
    await tx.bankTransaction.createMany({
      data: [
        ...payableExpenses.map((expense, index) => ({
          id: transactionId(plan.locationIndex, 1, index),
          organizationId: demoOrganizationId,
          restaurantLocationId: plan.locationId,
          bankAccountId: plan.accountId,
          providerTransactionId: `demo-operating-${plan.locationIndex}-${index}`,
          postedDate: expense.date,
          merchantNameRaw: vendorName(expense.vendorId) ?? expense.description,
          merchantNameNormalized: vendorName(expense.vendorId) ?? expense.description,
          description: `Synthetic ACH — ${expense.description}`,
          amount: expense.amount,
          expenseId: expense.id,
          categoryId: expense.expenseCategoryId,
          vendorId: expense.vendorId,
          providerCategory: 'Operating expense',
          reconciliationStatus: BankReconciliationStatus.MATCHED_EXPENSE,
          categorizationSource: BankCategorizationSource.MANUAL,
        })),
        ...matchedInvoices.map((spec, index) => {
          const invoiceDate = new Date(seedToday);
          invoiceDate.setUTCDate(seedToday.getUTCDate() - spec.daysAgo);
          const postedDate = new Date(invoiceDate);
          postedDate.setUTCDate(invoiceDate.getUTCDate() + 12);
          const subtotal = money(
            spec.lines.reduce((sum, line) => sum + line.quantity * line.unitPrice, 0),
          );
          const total = money(subtotal + money(subtotal * spec.taxRate));
          return {
            id: transactionId(plan.locationIndex, 2, index),
            organizationId: demoOrganizationId,
            restaurantLocationId: plan.locationId,
            bankAccountId: plan.accountId,
            providerTransactionId: `demo-invoice-${plan.locationIndex}-${index}`,
            postedDate,
            merchantNameRaw: spec.vendor.toUpperCase(),
            merchantNameNormalized: spec.vendor,
            description: 'Synthetic vendor invoice payment',
            amount: new Prisma.Decimal(total),
            invoiceId: spec.id,
            vendorId: vendorId(spec.vendor),
            providerCategory: 'Supplier payment',
            reconciliationStatus: BankReconciliationStatus.MATCHED_INVOICE,
            categorizationSource: BankCategorizationSource.INVOICE_MATCH,
          };
        }),
        ...Array.from({ length: 12 }, (_, index) => {
          const postedDate = new Date(seedToday);
          postedDate.setUTCMonth(seedToday.getUTCMonth() - index);
          postedDate.setUTCDate(5);
          return {
            id: transactionId(plan.locationIndex, 3, index),
            organizationId: demoOrganizationId,
            restaurantLocationId: plan.locationId,
            bankAccountId: plan.accountId,
            providerTransactionId: `demo-deposit-${plan.locationIndex}-${index}`,
            postedDate,
            merchantNameRaw: 'TOAST CARD SALES DEPOSIT',
            merchantNameNormalized: 'Toast Card Sales Deposit',
            description: 'Synthetic restaurant card sales deposit',
            amount: new Prisma.Decimal(-money(18000 + ((index * 977) % 6000))),
            providerCategory: 'Restaurant sales deposit',
            providerCategoryId: 'DEPOSIT',
            reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW,
            categorizationSource: BankCategorizationSource.PROVIDER,
          };
        }),
      ],
    });
  }

  const chickenLines = await tx.invoiceLineItem.findMany({
    where: {
      organizationId: demoOrganizationId,
      restaurantLocationId: demoDowntownLocationId,
      sku: { in: ['384920', 'USF-CHKN-40'] },
    },
    orderBy: { createdAt: 'desc' },
  });
  const syscoChicken = chickenLines.find((line) => line.sku === '384920');
  const usFoodsChicken = chickenLines.find((line) => line.sku === 'USF-CHKN-40');
  if (syscoChicken && usFoodsChicken) {
    const group = await tx.productGroup.create({
      data: {
        id: '20000000-0000-4000-8000-000000000001',
        organizationId: demoOrganizationId,
        restaurantLocationId: demoDowntownLocationId,
        displayName: 'Boneless Skinless Chicken Breast',
        members: {
          create: [
            { invoiceLineItemId: syscoChicken.id, vendorId: vendorId('sysco'), confirmed: true },
            { invoiceLineItemId: usFoodsChicken.id, vendorId: vendorId('us foods'), confirmed: true },
          ],
        },
      },
    });
    await tx.productMatchDecision.create({
      data: {
        organizationId: demoOrganizationId,
        restaurantLocationId: demoDowntownLocationId,
        candidateLineItemAId: [syscoChicken.id, usFoodsChicken.id].sort()[0],
        candidateLineItemBId: [syscoChicken.id, usFoodsChicken.id].sort()[1],
        status: ProductMatchStatus.CONFIRMED,
        confidence: ProductMatchConfidence.HIGH,
        reason: 'Synthetic demo confirmation: compatible case unit and 40 lb total weight',
        productGroupId: group.id,
        reviewedByUserId: userId,
        reviewedAt: seedToday,
      },
    });
  }

  return { bankTransactions: 120, invoices: specs.length };
}
