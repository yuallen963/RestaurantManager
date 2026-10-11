import { createHash } from 'crypto';
import {
  ExpenseClassification,
  ExpenseSource,
  ExtractionStatus,
  InvoiceStatus,
  Prisma,
  PrismaClient,
  ReviewStatus,
  RevenueSource,
} from '@prisma/client';

/**
 * Explicitly gated synthetic data for the existing FundWell Test Restaurant.
 *
 * Required:
 *   TARGET_LOCATION_ID=<exact location id>
 *   CONFIRM_FUNDWELL_SEED=YES
 * Optional:
 *   DRY_RUN=true
 *
 * This script never creates bank connections or bank transactions.
 */
const prisma = new PrismaClient();
const marker = 'FUNDWELL_TEST_RESTAURANT_SEED_V1';
const targetId = process.env.TARGET_LOCATION_ID?.trim();
const confirmation = process.env.CONFIRM_FUNDWELL_SEED;
const dryRun = process.env.DRY_RUN === 'true';

const stableId = (label: string) => {
  const hex = createHash('sha256').update(`${marker}:${label}`).digest('hex').slice(0, 32);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-8${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
};
const day = (daysAgo: number) => {
  const value = new Date();
  value.setUTCHours(12, 0, 0, 0);
  value.setUTCDate(value.getUTCDate() - daysAgo);
  return value;
};
const money = (value: number) => new Prisma.Decimal(value.toFixed(2));
const normalize = (value: string) => value.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

const vendors = [
  ['Sysco', 'sysco'], ['US Foods', 'us foods'], ['Gordon Food Service', 'gordon food service'],
  ['Thai Specialty Produce', 'thai specialty produce'], ['Metro Asian Foods', 'metro asian foods'],
  ['ADP', 'adp'], ['DTE Energy', 'dte energy'], ['Main Street Properties', 'main street properties'],
  ['Restaurant Depot', 'restaurant depot'], ['Harbor Insurance', 'harbor insurance'],
] as const;

const categoryDefinitions = [
  ['Food', 'food', ExpenseClassification.FOOD],
  ['Labor', 'labor', ExpenseClassification.LABOR],
  ['Utilities', 'utilities', ExpenseClassification.UTILITIES],
  ['Rent', 'rent', ExpenseClassification.OCCUPANCY],
  ['Supplies', 'supplies', ExpenseClassification.OPERATING],
] as const;

async function main() {
  if (!targetId) throw new Error('TARGET_LOCATION_ID is required');
  if (confirmation !== 'YES' && !dryRun) throw new Error('Set CONFIRM_FUNDWELL_SEED=YES to write data');

  const location = await prisma.restaurantLocation.findUnique({ where: { id: targetId } });
  if (!location) throw new Error(`Target location ${targetId} was not found`);
  if (location.name !== 'FundWell Test Restaurant') throw new Error(`Refusing location named ${location.name}`);
  if (location.name === 'Bangkok Cuisine') throw new Error('Refusing Bangkok Cuisine');

  const organizationId = location.organizationId;
  const owner = await prisma.organizationMember.findFirst({ where: { organizationId }, orderBy: { createdAt: 'asc' } });
  if (!owner) throw new Error('Target organization has no member to own seeded records');
  const categoryRows = await Promise.all(categoryDefinitions.map(async ([name, slug, classification]) => {
    const existing = await prisma.expenseCategory.findFirst({ where: { organizationId: null, slug } });
    return existing ?? prisma.expenseCategory.create({ data: { name, slug, classification, isSystem: true } });
  }));
  const categoryId = new Map(categoryRows.map((row) => [row.slug, row.id]));
  const vendorRows = await Promise.all(vendors.map(([name, normalizedName]) => prisma.vendor.upsert({
    where: { organizationId_normalizedName: { organizationId, normalizedName } },
    update: { name },
    create: { organizationId, name, normalizedName },
  })));
  const vendorId = new Map(vendorRows.map((row) => [row.normalizedName, row.id]));

  const existing = await Promise.all([
    prisma.revenueEntry.count({ where: { restaurantLocationId: targetId, notes: marker } }),
    prisma.expense.count({ where: { restaurantLocationId: targetId, notes: marker } }),
    prisma.invoice.count({ where: { restaurantLocationId: targetId, storageKey: { startsWith: `${marker}/` } } }),
  ]);
  const counts = { revenue: 75, expenses: 90 * 3 + 13, invoices: 30, lineItems: 30 * 6, bankTransactions: 0 };
  if (dryRun) {
    console.log(JSON.stringify({ dryRun: true, targetId, organizationId, existing, planned: counts }, null, 2));
    return;
  }

  await prisma.$transaction(async (tx) => {
    await tx.invoice.deleteMany({ where: { restaurantLocationId: targetId, storageKey: { startsWith: `${marker}/` } } });
    await tx.expense.deleteMany({ where: { restaurantLocationId: targetId, notes: marker } });
    await tx.revenueEntry.deleteMany({ where: { restaurantLocationId: targetId, notes: marker } });

    const revenue: Prisma.RevenueEntryCreateManyInput[] = [];
    for (let index = 0; index < 75; index += 1) {
      const daysAgo = 74 - index;
      const weekend = [5, 6].includes(day(daysAgo).getUTCDay());
      revenue.push({
        id: stableId(`revenue:${index}`), organizationId, restaurantLocationId: targetId,
        date: day(daysAgo), amount: money((weekend ? 3850 : 2850) + ((index * 37) % 240)),
        source: RevenueSource.MANUAL, notes: marker,
      });
    }
    await tx.revenueEntry.createMany({ data: revenue });

    const expenses: Prisma.ExpenseCreateManyInput[] = [];
    for (let index = 0; index < 90; index += 1) {
      const recent = index < 30;
      const date = day(index);
      const base = recent ? 1180 : 820;
      expenses.push(
        { id: stableId(`expense:food:${index}`), organizationId, restaurantLocationId: targetId, vendorId: vendorId.get('thai specialty produce'), expenseCategoryId: categoryId.get('food')!, date, amount: money(base + (index * 17) % 120), description: 'Fresh ingredients and produce', notes: marker, source: ExpenseSource.MANUAL },
        { id: stableId(`expense:labor:${index}`), organizationId, restaurantLocationId: targetId, vendorId: vendorId.get('adp'), expenseCategoryId: categoryId.get('labor')!, date, amount: money((recent ? 1080 : 980) + (index * 11) % 80), description: 'Payroll and labor', notes: marker, source: ExpenseSource.MANUAL },
        { id: stableId(`expense:utilities:${index}`), organizationId, restaurantLocationId: targetId, vendorId: vendorId.get('dte energy'), expenseCategoryId: categoryId.get('utilities')!, date, amount: money((recent ? 260 : 190) + (index * 7) % 35), description: 'Electric and gas service', notes: marker, source: ExpenseSource.MANUAL },
      );
      if (index % 7 === 0) expenses.push({ id: stableId(`expense:rent:${index}`), organizationId, restaurantLocationId: targetId, vendorId: vendorId.get('main street properties'), expenseCategoryId: categoryId.get('rent')!, date, amount: money(3200), description: 'Restaurant occupancy', notes: marker, source: ExpenseSource.MANUAL });
    }
    await tx.expense.createMany({ data: expenses });

    for (let index = 0; index < 30; index += 1) {
      const invoiceId = stableId(`invoice:${index}`);
      const invoiceDate = day(5 + index * 3);
      const vendor = vendorRows[index % vendorRows.length];
      const chickenPrice = index < 10 ? 92 : index < 20 ? 101 : 112;
      const lines = [
        ['CHICKEN BREAST BONELESS 4/10 LB', 'CHKN-410', 8, 'CASE', '4 x 10 lb', chickenPrice],
        ['JASMINE RICE 50 LB', 'RICE-50', 4, 'BAG', '50 lb', 34 + (index % 3)],
        ['CANOLA FRYING OIL 35 LB', 'OIL-35', 3, 'JUG', '35 lb', 42],
        ['NITRILE GLOVES LARGE 10/100 CT', 'GLOVE-L', 2, 'CASE', '10 x 100 ct', 64],
        ['COCONUT MILK 12/13.5 OZ', 'COCO-135', 6, 'CASE', '12 x 13.5 oz', 29],
        ['PAPER TAKEOUT CONTAINERS 200 CT', 'PACK-200', 1, 'CASE', '200 ct', 48],
      ] as const;
      const subtotal = lines.reduce((sum, line) => sum + line[2] * line[5], 0);
      const reviewed = index !== 29;
      await tx.invoice.create({ data: {
        id: invoiceId, organizationId, restaurantLocationId: targetId, vendorId: vendor.id,
        fileName: `${marker}/${invoiceId}.pdf`, originalFileName: `${vendor.name} invoice ${index + 1}.pdf`,
        fileType: 'application/pdf', fileSize: 1, storageKey: `${marker}/${invoiceId}.pdf`,
        invoiceNumber: `FW-TEST-${String(index + 1).padStart(3, '0')}`, invoiceDate, dueDate: day(5 + index * 3 - 14),
        subtotal: money(subtotal), tax: money(0), otherFees: money(0), total: money(subtotal), currency: 'USD',
        status: InvoiceStatus.COMPLETED, extractionStatus: ExtractionStatus.COMPLETED,
        extractionProvider: 'synthetic-test-seed', reviewStatus: reviewed ? ReviewStatus.REVIEWED : ReviewStatus.NOT_REVIEWED,
        reviewedAt: reviewed ? invoiceDate : null, createdByUserId: owner.userId,
        lineItems: { create: lines.map((line, lineIndex) => ({
          organizationId, restaurantLocationId: targetId, lineNumber: lineIndex + 1, rawDescription: line[0], normalizedName: normalize(line[0]), sku: line[1], quantity: money(line[2]), unit: line[3], packSize: line[4], unitPrice: money(line[5]), extendedPrice: money(line[2] * line[5]), confidence: money(1),
        })) },
      } });
    }
  });
  console.log(JSON.stringify({ dryRun: false, targetId, organizationId, created: counts, bankTransactions: '0 (requires real bank connection)' }, null, 2));
}

main().catch((error) => { console.error(error instanceof Error ? error.message : error); process.exitCode = 1; }).finally(() => prisma.$disconnect());
