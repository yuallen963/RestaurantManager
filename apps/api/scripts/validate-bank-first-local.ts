import {
  BankConnectionStatus,
  BankProvider,
  BankReconciliationStatus,
  ExpenseClassification,
  MerchantRuleMatchType,
  PrismaClient,
  ReviewStatus,
} from '@prisma/client';
import { AuditService } from '../src/audit.service';
import { BankService } from '../src/bank/bank.service';
import { DashboardService } from '../src/dashboard/dashboard.service';
import { OrganizationAccessService } from '../src/organizations/organization-access.service';

const databaseUrl = process.env.DATABASE_URL ?? '';
if (!databaseUrl.includes('fundwell_bank_validation_')) {
  throw new Error('Refusing to run outside a FundWell isolated validation database');
}

const prisma = new PrismaClient();
const userId = '71000000-0000-4000-8000-000000000001';
const organizationId = '72000000-0000-4000-8000-000000000001';
const locationId = '73000000-0000-4000-8000-000000000001';
const otherLocationId = '73000000-0000-4000-8000-000000000002';
const connectionId = '74000000-0000-4000-8000-000000000001';
const accountId = '75000000-0000-4000-8000-000000000001';
const otherAccountId = '75000000-0000-4000-8000-000000000002';
const vendorId = '76000000-0000-4000-8000-000000000001';
const categoryId = '77000000-0000-4000-8000-000000000001';

const day = (offset: number) => {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + offset);
  return date.toISOString().slice(0, 10);
};

const initial = Array.from({ length: 100 }, (_, index) => ({
  id: `initial-${index}`,
  accountId: 'provider-main',
  date: day(-(index % 28)),
  merchantName: index < 10 ? 'CUSTOMER DEPOSIT' : index % 5 === 0 ? 'SYSCO FOOD SERVICES' : `LOCAL MERCHANT ${index}`,
  description: index < 10 ? 'CUSTOMER DEPOSIT' : index % 5 === 0 ? 'SYSCO FOOD SERVICES' : `LOCAL MERCHANT ${index}`,
  amount: index < 10 ? -(100 + index) : 20 + index,
  pending: index >= 90 && index < 95,
  category: index < 10 ? 'Deposit' : 'Restaurant supplies',
  categoryId: index < 10 ? 'TRANSFER_IN' : 'GENERAL_MERCHANDISE',
}));

const pages: any[] = [
  { added: initial, modified: [], removed: [], cursor: 'cursor-100' },
  { added: [{ id: 'auto-eligible', accountId: 'provider-main', date: day(0), merchantName: 'SYSCO FOOD SERVICES', description: 'SYSCO FOOD SERVICES', amount: 120, pending: false, category: 'Food', categoryId: 'FOOD_AND_DRINK' }], modified: [], removed: [], cursor: 'cursor-101' },
  { added: [{ id: 'auto-eligible', accountId: 'provider-main', date: day(0), merchantName: 'SYSCO FOOD SERVICES', description: 'SYSCO FOOD SERVICES', amount: 120, pending: false, category: 'Food', categoryId: 'FOOD_AND_DRINK' }], modified: [], removed: [], cursor: 'cursor-101-repeat' },
  { added: [
    { id: 'pending', accountId: 'provider-main', date: day(0), merchantName: 'SYSCO FOOD SERVICES', description: 'SYSCO FOOD SERVICES', amount: 80, pending: true, category: 'Food', categoryId: 'FOOD_AND_DRINK' },
    { id: 'transfer', accountId: 'provider-main', date: day(0), merchantName: 'SYSCO FOOD SERVICES', description: 'TRANSFER SYSCO', amount: 80, pending: false, category: 'Transfer', categoryId: 'TRANSFER_OUT' },
    { id: 'refund', accountId: 'provider-main', date: day(0), merchantName: 'SYSCO FOOD SERVICES', description: 'REFUND SYSCO', amount: 80, pending: false, category: 'Refund', categoryId: 'REFUND' },
    { id: 'unusual', accountId: 'provider-main', date: day(0), merchantName: 'SYSCO FOOD SERVICES', description: 'SYSCO FOOD SERVICES', amount: 10000, pending: false, category: 'Food', categoryId: 'FOOD_AND_DRINK' },
    { id: 'unknown', accountId: 'provider-main', date: day(0), merchantName: 'UNKNOWN SHOP', description: 'UNKNOWN SHOP', amount: 55, pending: false, category: 'Other', categoryId: 'OTHER' },
    { id: 'deposit', accountId: 'provider-main', date: day(0), merchantName: 'BANK DEPOSIT', description: 'BANK DEPOSIT', amount: -500, pending: false, category: 'Deposit', categoryId: 'TRANSFER_IN' },
    { id: 'other-location', accountId: 'provider-other', date: day(0), merchantName: 'SYSCO FOOD SERVICES', description: 'SYSCO FOOD SERVICES', amount: 90, pending: false, category: 'Food', categoryId: 'FOOD_AND_DRINK' },
    { id: 'invoice-match', accountId: 'provider-main', date: day(0), merchantName: 'SYSCO FOOD SERVICES', description: 'SYSCO FOOD SERVICES', amount: 500, pending: false, category: 'Food', categoryId: 'FOOD_AND_DRINK' },
  ], modified: [], removed: [], cursor: 'cursor-exceptions' },
];

async function main() {
  await prisma.auditLog.deleteMany({ where: { organizationId } });
  await prisma.bankTransaction.deleteMany({ where: { organizationId } });
  await prisma.expense.deleteMany({ where: { organizationId } });
  await prisma.merchantRule.deleteMany({ where: { organizationId } });
  await prisma.bankAccount.deleteMany({ where: { organizationId } });
  await prisma.bankConnection.deleteMany({ where: { organizationId } });
  await prisma.invoice.deleteMany({ where: { organizationId } });
  await prisma.vendor.deleteMany({ where: { organizationId } });
  await prisma.expenseCategory.deleteMany({ where: { organizationId } });
  await prisma.organizationMember.deleteMany({ where: { organizationId } });
  await prisma.restaurantLocation.deleteMany({ where: { organizationId } });
  await prisma.organization.deleteMany({ where: { id: organizationId } });
  await prisma.user.deleteMany({ where: { id: userId } });

  await prisma.user.create({ data: { id: userId, email: 'bank-first-validation@test.invalid', passwordHash: 'synthetic' } });
  await prisma.organization.create({ data: { id: organizationId, name: 'Bank First Validation' } });
  await prisma.organizationMember.create({ data: { userId, organizationId, role: 'OWNER' } });
  await prisma.restaurantLocation.createMany({ data: [
    { id: locationId, organizationId, name: 'Primary Test Restaurant', invoiceEmailToken: 'bank-first-primary' },
    { id: otherLocationId, organizationId, name: 'Other Test Restaurant', invoiceEmailToken: 'bank-first-other' },
  ] });
  await prisma.vendor.create({ data: { id: vendorId, organizationId, name: 'Sysco', normalizedName: 'sysco' } });
  await prisma.expenseCategory.create({ data: { id: categoryId, organizationId, name: 'Food & Beverage', slug: 'food-beverage-validation', classification: ExpenseClassification.FOOD } });
  await prisma.bankConnection.create({ data: { id: connectionId, organizationId, provider: BankProvider.DEMO, providerItemId: 'validation-item', encryptedAccessToken: 'synthetic-token', status: BankConnectionStatus.CONNECTED, createdByUserId: userId, accounts: { create: [
    { id: accountId, organizationId, restaurantLocationId: locationId, providerAccountId: 'provider-main', name: 'Validation Checking' },
    { id: otherAccountId, organizationId, restaurantLocationId: otherLocationId, providerAccountId: 'provider-other', name: 'Other Checking' },
  ] } } });

  const access = new OrganizationAccessService(prisma as any);
  const audit = new AuditService(prisma as any);
  const provider = { name: 'DEMO', sync: async () => pages.shift() ?? { added: [], modified: [], removed: [], cursor: 'done' } };
  const service = new BankService(prisma as any, access, audit, { decrypt: () => 'synthetic-token' } as any, { get: () => provider } as any);
  const dashboard = new DashboardService(prisma as any, access);

  await service.sync(userId, connectionId);
  const initialCount = await prisma.bankTransaction.count({ where: { organizationId } });
  const initialExpenses = await prisma.expense.count({ where: { organizationId } });
  if (initialCount !== 100 || initialExpenses !== 0) throw new Error(`Initial import mismatch: ${initialCount} transactions, ${initialExpenses} expenses`);

  const reviewTarget = await prisma.bankTransaction.findFirstOrThrow({ where: { organizationId, restaurantLocationId: locationId, providerTransactionId: 'initial-10' } });
  await service.review(userId, reviewTarget.id, { restaurantLocationId: locationId, vendorId, categoryId, createMerchantRule: true, ruleMatchType: MerchantRuleMatchType.EXACT, autoConfirmFuture: true, minimumAmount: 10, maximumAmount: 2000 });
  const manualExpense = await prisma.expense.count({ where: { organizationId } });
  if (manualExpense !== 1) throw new Error('Manual reconciliation did not create exactly one expense');

  await service.sync(userId, connectionId);
  const afterAuto = await prisma.expense.count({ where: { organizationId } });
  const automatic = await prisma.bankTransaction.findFirstOrThrow({ where: { organizationId, providerTransactionId: 'auto-eligible' } });
  if (afterAuto !== 2 || automatic.reconciliationStatus !== BankReconciliationStatus.MATCHED_EXPENSE) throw new Error('Explicit automatic rule did not create one expense');
  const autoAudit = await prisma.auditLog.count({ where: { organizationId, action: 'bank.transaction_auto_reconciled', entityId: automatic.id } });
  if (autoAudit !== 1) throw new Error('Automatic decision audit log missing');

  await service.sync(userId, connectionId);
  if (await prisma.expense.count({ where: { organizationId } }) !== 2) throw new Error('Repeated sync duplicated an expense');

  await prisma.invoice.create({ data: { organizationId, restaurantLocationId: locationId, vendorId, extractedVendorName: 'Sysco', fileName: 'synthetic.pdf', originalFileName: 'synthetic.pdf', fileType: 'application/pdf', fileSize: 1, storageKey: 'synthetic-only', invoiceDate: new Date(`${day(-1)}T12:00:00.000Z`), total: 500, createdByUserId: userId, status: 'COMPLETED', extractionStatus: 'COMPLETED', reviewStatus: ReviewStatus.REVIEWED } });
  await service.sync(userId, connectionId);
  const exceptionIds = ['pending', 'transfer', 'refund', 'unusual', 'unknown', 'deposit', 'other-location', 'invoice-match'];
  const exceptions = await prisma.bankTransaction.findMany({ where: { organizationId, providerTransactionId: { in: exceptionIds } }, orderBy: { providerTransactionId: 'asc' } });
  if (exceptions.some((row) => row.expenseId != null)) throw new Error('An ineligible exception was silently reconciled');
  const invoiceMatch = exceptions.find((row) => row.providerTransactionId === 'invoice-match');
  if (!invoiceMatch?.suggestedInvoiceId) throw new Error('Reviewed invoice match was not preserved for review');

  const locationCount = await prisma.bankTransaction.count({ where: { organizationId, restaurantLocationId: locationId } });
  const otherCount = await prisma.bankTransaction.count({ where: { organizationId, restaurantLocationId: otherLocationId } });
  if (otherCount !== 1) throw new Error('Location isolation failed');
  const deposits = await prisma.bankTransaction.count({ where: { organizationId, restaurantLocationId: locationId, amount: { lt: 0 } } });
  const revenues = await prisma.revenueEntry.count({ where: { organizationId } });
  if (deposits !== 11 || revenues !== 0) throw new Error('Bank deposits were incorrectly treated as verified revenue');

  const result = await dashboard.get(userId, { restaurantLocationId: locationId, startDate: `${day(-31)}T00:00:00.000Z`, endDate: `${day(1)}T00:00:00.000Z` });
  if ((result as any).bank?.trackedOutflows == null) throw new Error('Dashboard banking summary is unavailable');

  await service.reverseReconciliation(userId, automatic.id);
  const reversed = await prisma.bankTransaction.findUniqueOrThrow({ where: { id: automatic.id } });
  if (reversed.expenseId || reversed.reconciliationStatus !== BankReconciliationStatus.NEEDS_REVIEW) throw new Error('Automatic decision reversal failed');

  console.log(JSON.stringify({
    initialTransactions: initialCount,
    initialExpenses,
    importedTransactions: await prisma.bankTransaction.count({ where: { organizationId } }),
    primaryLocationTransactions: locationCount,
    otherLocationTransactions: otherCount,
    unverifiedDeposits: deposits,
    verifiedRevenue: revenues,
    manualExpenseCreated: manualExpense,
    automaticExpenseCreated: afterAuto,
    automaticAuditRecords: autoAudit,
    exceptionTransactionsLeftForReview: exceptions.length,
    invoiceMatchSuggested: Boolean(invoiceMatch?.suggestedInvoiceId),
    reversalStatus: reversed.reconciliationStatus,
    dashboardBankingState: (result as any).bank,
  }, null, 2));
}

main().finally(() => prisma.$disconnect());
