import { ConflictException, ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { BankCategorizationSource, BankConnectionStatus, BankReconciliationStatus, ExpenseSource, InvoiceMatchConfidence, MerchantRuleDecision, MerchantRuleMatchType, Prisma } from '@prisma/client';
import { BankLinkClientPlatform, BankReviewDecision } from '../src/bank/dto';
import { BankService, normalizeMerchant } from '../src/bank/bank.service';
import { BankTokenEncryptionService } from '../src/bank/encryption.service';

const connection = { id: 'connection-a', organizationId: 'org-a', provider: 'DEMO', providerItemId: 'item-a', encryptedAccessToken: 'encrypted', status: 'CONNECTED', syncCursor: null, accounts: [{ id: 'account-a', providerAccountId: 'provider-account', restaurantLocationId: 'location-a', active: true }] };
const providerTransaction = { id: 'transaction-a', accountId: 'provider-account', date: '2026-10-08', merchantName: 'SYSCO FOOD SERVICES #1842', description: 'SYSCO ACH', amount: 1446, pending: false, category: 'Food distributor', categoryId: 'FOOD_AND_DRINK' };

function setup(overrides: { rules?: any[]; vendors?: any[]; invoices?: any[] } = {}) {
  const prisma: any = {
    bankConnection: { findUnique: jest.fn().mockResolvedValue(connection), update: jest.fn().mockImplementation(({ data }: any) => Promise.resolve({ ...connection, ...data })), updateMany: jest.fn().mockResolvedValue({ count: 1 }), create: jest.fn(), findMany: jest.fn() },
    bankAccount: { findUnique: jest.fn(), update: jest.fn() },
    bankTransaction: { create: jest.fn().mockResolvedValue({}), updateMany: jest.fn().mockResolvedValue({ count: 0 }), delete: jest.fn().mockResolvedValue({}), findUnique: jest.fn().mockResolvedValue(null), findFirst: jest.fn().mockResolvedValue(null), findMany: jest.fn().mockResolvedValue([]), count: jest.fn().mockResolvedValue(0), update: jest.fn().mockResolvedValue({}) },
    merchantRule: { findMany: jest.fn().mockResolvedValue(overrides.rules ?? []), findFirst: jest.fn().mockResolvedValue(null), findUnique: jest.fn().mockResolvedValue(null), create: jest.fn(), update: jest.fn() },
    vendor: { findMany: jest.fn().mockResolvedValue(overrides.vendors ?? [{ id: 'sysco', normalizedName: 'sysco' }]), findFirst: jest.fn() },
    expenseCategory: { findFirst: jest.fn().mockResolvedValue({ id: 'category-a' }) },
    invoice: { findMany: jest.fn().mockResolvedValue(overrides.invoices ?? []), findFirst: jest.fn() },
    expense: { findUnique: jest.fn(), findMany: jest.fn().mockResolvedValue([]), create: jest.fn().mockResolvedValue({ id: 'expense-created' }), update: jest.fn(), delete: jest.fn() },
    restaurantLocation: { findFirst: jest.fn().mockResolvedValue({ id: 'location-a', organizationId: 'org-a' }) },
  };
  prisma.$transaction = jest.fn((callback: any) => callback(prisma));
  const access: any = { requireMember: jest.fn().mockResolvedValue({ role: 'OWNER' }) };
  const audit: any = { log: jest.fn().mockResolvedValue({}) };
  const encryption: any = { encrypt: jest.fn((value: string) => `encrypted:${value}`), decrypt: jest.fn().mockReturnValue('provider-token') };
  const provider: any = { name: 'DEMO', sync: jest.fn().mockResolvedValue({ added: [providerTransaction], modified: [], removed: [], cursor: 'cursor-1' }), createLinkToken: jest.fn(), exchange: jest.fn(), disconnect: jest.fn() };
  const providers: any = { get: jest.fn().mockReturnValue(provider) };
  return { prisma, access, audit, encryption, provider, service: new BankService(prisma, access, audit, encryption, providers) };
}

describe('bank transaction foundation', () => {
  it('normalizes common merchant variants conservatively', () => {
    expect(normalizeMerchant('SYSCO FOOD SERVICES #1842')).toBe('Sysco');
    expect(normalizeMerchant('SYSCO DETROIT')).toBe('Sysco');
    expect(normalizeMerchant('DTE ENERGY PAYMENT')).toBe('DTE Energy');
    expect(normalizeMerchant('USFOODS ACH PAYMENT')).toBe('US Foods');
    expect(normalizeMerchant('GFS STORE #0123')).toBe('Gordon Food Service');
    expect(normalizeMerchant('RESTAURANT DEPOT 48310')).toBe('Restaurant Depot');
    expect(normalizeMerchant('ROCHESTER MARKET 7732')).toBe('Rochester Market');
  });

  it('encrypts tokens with authenticated encryption and detects tampering', () => {
    process.env.BANK_TOKEN_ENCRYPTION_KEY = Buffer.alloc(32, 7).toString('base64');
    const encryption = new BankTokenEncryptionService();
    const stored = encryption.encrypt('access-token');
    expect(stored).not.toContain('access-token');
    expect(encryption.decrypt(stored)).toBe('access-token');
    const tampered = stored.split('.');
    tampered[3] = `${tampered[3][0] === 'A' ? 'B' : 'A'}${tampered[3].slice(1)}`;
    expect(() => encryption.decrypt(tampered.join('.'))).toThrow();
  });

  it('ingests positive spending using a provider-id upsert and exact invoice suggestion', async () => {
    const invoice = { id: 'invoice-a', vendorId: 'sysco', extractedVendorName: null, total: new Prisma.Decimal(1446), invoiceDate: new Date('2026-10-05') };
    const { service, prisma } = setup({ invoices: [invoice] });
    await service.sync('user-a', 'connection-a');
    const create = prisma.bankTransaction.create.mock.calls[0][0].data;
    expect(create.amount.toNumber()).toBe(1446);
    expect(create.suggestedInvoiceId).toBe('invoice-a');
    expect(create.matchConfidence).toBe(InvoiceMatchConfidence.EXACT);
    expect(create.reconciliationStatus).toBe(BankReconciliationStatus.NEEDS_REVIEW);
    expect(prisma.expense.create).not.toHaveBeenCalled();
  });

  it('uses merchant rules before known vendors and provider categories', async () => {
    const rule = { matchType: MerchantRuleMatchType.CONTAINS, matchValue: 'SYSCO', vendorId: 'rule-vendor', expenseCategoryId: 'rule-category' };
    const { service, prisma } = setup({ rules: [rule] });
    await service.sync('user-a', 'connection-a');
    const create = prisma.bankTransaction.create.mock.calls[0][0].data;
    expect(create.vendorId).toBe('rule-vendor');
    expect(create.categoryId).toBe('rule-category');
    expect(create.categorizationSource).toBe(BankCategorizationSource.USER_RULE);
  });

  it('keeps automatic confirmation disabled for ordinary saved rules', async () => {
    const rule = { id: 'rule', active: true, autoConfirm: false, matchType: MerchantRuleMatchType.EXACT, matchValue: 'SYSCO', vendorId: 'rule-vendor', expenseCategoryId: 'rule-category', restaurantLocationId: 'location-a' };
    const { service, prisma } = setup({ rules: [rule] });
    await service.sync('user-a', 'connection-a');
    expect(prisma.expense.create).not.toHaveBeenCalled();
  });

  it('auto-confirms a posted transaction only under an explicit location rule', async () => {
    const rule = { id: 'rule', active: true, autoConfirm: true, matchType: MerchantRuleMatchType.EXACT, matchValue: 'SYSCO', vendorId: 'sysco', expenseCategoryId: 'food', restaurantLocationId: 'location-a', minimumAmount: new Prisma.Decimal(1000), maximumAmount: new Prisma.Decimal(2000) };
    const { service, prisma } = setup({ rules: [rule] });
    prisma.bankTransaction.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'bank-row', ...data }));
    prisma.bankTransaction.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ id: 'bank-row', organizationId: 'org-a', restaurantLocationId: 'location-a', pending: false, expenseId: null, suggestedInvoiceId: null, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW, amount: new Prisma.Decimal(1446), postedDate: new Date('2026-10-08'), description: 'SYSCO ACH' });
    await service.sync('user-a', 'connection-a');
    expect(prisma.expense.create).toHaveBeenCalledWith({ data: expect.objectContaining({ vendorId: 'sysco', expenseCategoryId: 'food', source: ExpenseSource.BANK_IMPORT }) });
    expect(prisma.bankTransaction.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ reconciliationStatus: BankReconciliationStatus.MATCHED_EXPENSE, categorizationSource: BankCategorizationSource.USER_RULE }) }));
  });

  it('leaves an unusual amount for review even when an automatic rule matches', async () => {
    const rule = { id: 'rule', active: true, autoConfirm: true, matchType: MerchantRuleMatchType.EXACT, matchValue: 'SYSCO', vendorId: 'sysco', expenseCategoryId: 'food', restaurantLocationId: 'location-a', minimumAmount: new Prisma.Decimal(10), maximumAmount: new Prisma.Decimal(100) };
    const { service, prisma } = setup({ rules: [rule] });
    prisma.bankTransaction.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'bank-row', ...data }));
    await service.sync('user-a', 'connection-a');
    expect(prisma.expense.create).not.toHaveBeenCalled();
  });

  it('maps reliable provider payroll categories when no merchant is known', async () => {
    const { service, prisma, provider } = setup({ vendors: [] });
    provider.sync.mockResolvedValue({ added: [{ ...providerTransaction, merchantName: 'PAYROLL PROCESSOR', categoryId: 'PAYROLL' }], modified: [], removed: [], cursor: 'cursor-1' });
    await service.sync('user-a', 'connection-a');
    expect(prisma.expenseCategory.findFirst).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ slug: 'labor' }) }));
    expect(prisma.bankTransaction.create.mock.calls[0][0].data.categorizationSource).toBe(BankCategorizationSource.PROVIDER);
  });

  it('handles pending-to-posted transitions and removed transactions', async () => {
    const { service, prisma, provider } = setup();
    prisma.bankTransaction.findFirst.mockResolvedValue({ id: 'stable-id', providerTransactionId: 'pending', pending: true, suggestedInvoiceId: null, matchConfidence: InvoiceMatchConfidence.NO_MATCH });
    provider.sync.mockResolvedValue({ added: [{ ...providerTransaction, id: 'posted', pendingTransactionId: 'pending' }], modified: [], removed: ['removed'], cursor: 'cursor-2' });
    await service.sync('user-a', 'connection-a');
    expect(prisma.bankTransaction.update).toHaveBeenCalledWith(expect.objectContaining({ where: { id: 'stable-id' }, data: expect.objectContaining({ providerTransactionId: 'posted', pending: false }) }));
    expect(prisma.bankTransaction.updateMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ providerTransactionId: 'removed' }) }));
  });

  it('uses a small tolerance only for likely invoice matches and rejects mismatches', async () => {
    const likely = { id: 'likely', vendorId: 'sysco', extractedVendorName: null, total: new Prisma.Decimal('1446.30'), invoiceDate: new Date('2026-10-05') };
    const first = setup({ invoices: [likely] });
    await first.service.sync('user-a', 'connection-a');
    expect(first.prisma.bankTransaction.create.mock.calls[0][0].data.matchConfidence).toBe(InvoiceMatchConfidence.LIKELY);
    const mismatch = setup({ invoices: [{ ...likely, total: new Prisma.Decimal('1500') }] });
    await mismatch.service.sync('user-a', 'connection-a');
    expect(mismatch.prisma.bankTransaction.create.mock.calls[0][0].data.matchConfidence).toBe(InvoiceMatchConfidence.NO_MATCH);
  });

  it('enforces tenant membership before connection access', async () => {
    const { service, access } = setup();
    access.requireMember.mockRejectedValue(new ForbiddenException());
    await expect(service.sync('other-user', 'connection-a')).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('reports delayed initial synchronization without claiming completion', async () => {
    const { service, prisma } = setup();
    prisma.bankConnection.findMany.mockResolvedValue([{ id: 'connection-a', status: BankConnectionStatus.SYNCING, lastSyncAt: null, lastError: null }]);
    prisma.bankTransaction.count.mockResolvedValue(0);
    await expect(service.syncStatus('user-a', 'org-a', 'location-a')).resolves.toEqual(expect.objectContaining({ state: 'IMPORTING', transactionCount: 0 }));
  });

  it('reports a partially complete import after location transactions arrive', async () => {
    const { service, prisma } = setup();
    prisma.bankConnection.findMany.mockResolvedValue([{ id: 'connection-a', status: BankConnectionStatus.SYNCING, lastSyncAt: null, lastError: null }]);
    prisma.bankTransaction.count.mockResolvedValue(7);
    await expect(service.syncStatus('user-a', 'org-a', 'location-a')).resolves.toEqual(expect.objectContaining({ state: 'PARTIALLY_COMPLETE', transactionCount: 7 }));
  });

  it('reports actionable synchronization failures', async () => {
    const { service, prisma } = setup();
    prisma.bankConnection.findMany.mockResolvedValue([{ id: 'connection-a', status: BankConnectionStatus.ERROR, lastSyncAt: null, lastError: 'Unable to sync this connection. Try again.' }]);
    await expect(service.syncStatus('user-a', 'org-a', 'location-a')).resolves.toEqual(expect.objectContaining({ state: 'FAILED', canRetry: true, message: 'Unable to sync this connection. Try again.' }));
  });

  it('distinguishes a completed empty history and scopes counts to the requested location', async () => {
    const { service, prisma } = setup();
    const completedAt = new Date('2026-10-12T12:00:00Z');
    prisma.bankConnection.findMany.mockResolvedValue([{ id: 'connection-a', status: BankConnectionStatus.CONNECTED, lastSyncAt: completedAt, lastError: null }]);
    prisma.bankTransaction.count.mockResolvedValue(0);
    await expect(service.syncStatus('user-a', 'org-a', 'location-a')).resolves.toEqual(expect.objectContaining({ state: 'COMPLETE', transactionCount: 0, lastSyncAt: completedAt }));
    expect(prisma.bankConnection.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ organizationId: 'org-a', accounts: { some: { restaurantLocationId: 'location-a', active: true } } }) }));
    expect(prisma.bankTransaction.count).toHaveBeenCalledWith({ where: expect.objectContaining({ organizationId: 'org-a', restaurantLocationId: 'location-a' }) });
  });

  it('requires OWNER or ADMIN to reassign a bank account location', async () => {
    const { service, prisma, access } = setup();
    prisma.bankAccount.findUnique.mockResolvedValue({ id: 'account-a', organizationId: 'org-a' });
    access.requireMember
      .mockResolvedValueOnce({ role: 'MANAGER' })
      .mockRejectedValueOnce(new ForbiddenException());
    await expect(service.assignAccount('manager', 'account-a', { restaurantLocationId: 'location-a' })).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.bankAccount.update).not.toHaveBeenCalled();
  });

  it('prevents concurrent sync but permits an idempotent retry afterward', async () => {
    const { service, prisma } = setup();
    prisma.bankConnection.updateMany.mockResolvedValueOnce({ count: 0 });
    await expect(service.sync('user-a', 'connection-a')).rejects.toBeInstanceOf(ConflictException);
    prisma.bankConnection.updateMany.mockResolvedValueOnce({ count: 1 });
    await service.sync('user-a', 'connection-a');
    expect(prisma.bankTransaction.create).toHaveBeenCalledTimes(1);
  });

  it('updates an already imported provider transaction instead of duplicating it', async () => {
    const { service, prisma } = setup();
    prisma.bankTransaction.findUnique.mockResolvedValue({ id: 'existing-row' });
    await service.sync('user-a', 'connection-a');
    expect(prisma.bankTransaction.create).not.toHaveBeenCalled();
    expect(prisma.bankTransaction.update).toHaveBeenCalledWith(expect.objectContaining({ where: { id: 'existing-row' } }));
  });

  it('updates its own bank-import expense when Plaid corrects the posted amount', async () => {
    const { service, prisma, provider } = setup();
    prisma.bankTransaction.findUnique.mockResolvedValue({ id: 'existing-row', amount: new Prisma.Decimal(20), postedDate: new Date('2026-10-08'), expenseId: 'bank-expense' });
    prisma.expense.findUnique.mockResolvedValue({ id: 'bank-expense', source: ExpenseSource.BANK_IMPORT });
    provider.sync.mockResolvedValue({ added: [], modified: [{ ...providerTransaction, amount: 21 }], removed: [], cursor: 'cursor-2' });
    await service.sync('user-a', 'connection-a');
    expect(prisma.expense.update).toHaveBeenCalledWith(expect.objectContaining({ where: { id: 'bank-expense' }, data: expect.objectContaining({ amount: new Prisma.Decimal(21) }) }));
  });

  it('reuses an existing connection for the same organization without duplicating it', async () => {
    const { service, prisma, provider } = setup();
    provider.exchange.mockResolvedValue({ accessToken: 'new-token', itemId: 'item-a', institutionName: 'Sandbox Bank', accounts: [] });
    prisma.bankConnection.findUnique.mockResolvedValueOnce(connection).mockResolvedValueOnce(connection).mockResolvedValue(connection);
    await service.exchange('user-a', { organizationId: 'org-a', publicToken: 'public', restaurantLocationId: 'location-a' });
    await new Promise<void>((resolve) => setImmediate(resolve));
    expect(prisma.bankConnection.create).not.toHaveBeenCalled();
    expect(prisma.bankConnection.update).toHaveBeenCalledWith(expect.objectContaining({ where: { id: 'connection-a' }, data: expect.objectContaining({ status: BankConnectionStatus.CONNECTED }) }));
    expect(provider.sync).toHaveBeenCalled();
  });

  it('rejects a provider item already attached to another tenant', async () => {
    const { service, prisma, provider } = setup();
    provider.exchange.mockResolvedValue({ accessToken: 'new-token', itemId: 'item-a', accounts: [] });
    prisma.bankConnection.findUnique.mockResolvedValueOnce({ ...connection, organizationId: 'org-b' });
    await expect(service.exchange('user-a', { organizationId: 'org-a', publicToken: 'public' })).rejects.toBeInstanceOf(ConflictException);
  });

  it('creates one bank-import expense when a posted reviewed transaction has no existing expense', async () => {
    const { service, prisma } = setup();
    const transaction = { ...providerTransaction, id: 'bank-row', organizationId: 'org-a', restaurantLocationId: 'location-a', vendorId: 'sysco', categoryId: 'food', suggestedInvoiceId: null, expenseId: null, postedDate: new Date('2026-10-08'), amount: new Prisma.Decimal(1446), pending: false };
    prisma.bankTransaction.findUnique.mockResolvedValue(transaction);
    prisma.vendor.findFirst.mockResolvedValue({ id: 'sysco', organizationId: 'org-a' });
    prisma.expenseCategory.findFirst.mockResolvedValue({ id: 'food' });
    await service.review('user-a', 'bank-row', { vendorId: 'sysco', categoryId: 'food', restaurantLocationId: 'location-a' });
    expect(prisma.expense.create).toHaveBeenCalledWith({ data: expect.objectContaining({ source: ExpenseSource.BANK_IMPORT, amount: transaction.amount }) });
    expect(prisma.bankTransaction.update).toHaveBeenLastCalledWith(expect.objectContaining({ data: expect.objectContaining({ expenseId: 'expense-created', reconciliationStatus: BankReconciliationStatus.MATCHED_EXPENSE }) }));
  });

  it('links a unique existing expense instead of creating a duplicate', async () => {
    const { service, prisma } = setup();
    const transaction = { id: 'bank-row', organizationId: 'org-a', restaurantLocationId: 'location-a', vendorId: 'sysco', categoryId: 'food', suggestedInvoiceId: null, expenseId: null, postedDate: new Date('2026-10-08'), amount: new Prisma.Decimal(1446), pending: false, merchantNameNormalized: 'Sysco' };
    prisma.bankTransaction.findUnique.mockResolvedValue(transaction);
    prisma.vendor.findFirst.mockResolvedValue({ id: 'sysco', organizationId: 'org-a' });
    prisma.expenseCategory.findFirst.mockResolvedValue({ id: 'food' });
    prisma.expense.findMany.mockResolvedValue([{ id: 'existing-expense' }]);
    await service.review('user-a', 'bank-row', { vendorId: 'sysco', categoryId: 'food', restaurantLocationId: 'location-a' });
    expect(prisma.expense.create).not.toHaveBeenCalled();
    expect(prisma.bankTransaction.update).toHaveBeenLastCalledWith(expect.objectContaining({ data: expect.objectContaining({ expenseId: 'existing-expense' }) }));
  });

  it('keeps pending reviews out of Expenses until the transaction posts', async () => {
    const { service, prisma } = setup();
    prisma.bankTransaction.findUnique.mockResolvedValue({ id: 'pending-row', organizationId: 'org-a', restaurantLocationId: 'location-a', vendorId: null, categoryId: null, amount: new Prisma.Decimal(20), pending: true, merchantNameNormalized: 'Market' });
    prisma.expenseCategory.findFirst.mockResolvedValue({ id: 'food' });
    await service.review('user-a', 'pending-row', { categoryId: 'food' });
    expect(prisma.expense.create).not.toHaveBeenCalled();
    expect(prisma.bankTransaction.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW }) }));
  });

  it('finds similar candidates only inside the same safe matching boundary', async () => {
    const { service, prisma } = setup();
    prisma.bankTransaction.findUnique.mockResolvedValue({ id: 'bank-row', organizationId: 'org-a', restaurantLocationId: 'location-a', bankAccountId: 'account-a', merchantNameNormalized: 'Market', providerCategoryId: 'GROCERIES', amount: new Prisma.Decimal(20), pending: false });
    await service.similarTransactions('user-a', 'bank-row');
    expect(prisma.bankTransaction.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ organizationId: 'org-a', restaurantLocationId: 'location-a', bankAccountId: 'account-a', merchantNameNormalized: 'Market', providerCategoryId: 'GROCERIES', pending: false, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW, amount: { gt: 0 }, expenseId: null, invoiceId: null, suggestedInvoiceId: null }) }));
  });

  it('classifies a posted personal transfer without creating an expense', async () => {
    const { service, prisma } = setup();
    prisma.bankTransaction.findUnique.mockResolvedValue({ id: 'bank-row', organizationId: 'org-a', restaurantLocationId: 'location-a', bankAccountId: 'account-a', merchantNameNormalized: 'Owner Transfer', providerCategoryId: 'TRANSFER', vendorId: null, categoryId: null, suggestedInvoiceId: null, invoiceId: null, expenseId: null, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW, amount: new Prisma.Decimal(200), pending: false });
    await service.review('user-a', 'bank-row', { decision: BankReviewDecision.PERSONAL_TRANSFER });
    expect(prisma.expense.create).not.toHaveBeenCalled();
    expect(prisma.bankTransaction.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ reconciliationStatus: BankReconciliationStatus.IGNORED, vendorId: null, categoryId: null }) }));
  });

  it('remembers personal-transfer decisions with account, direction, and type safeguards', async () => {
    const { service, prisma } = setup();
    prisma.bankTransaction.findUnique.mockResolvedValue({ id: 'bank-row', organizationId: 'org-a', restaurantLocationId: 'location-a', bankAccountId: 'account-a', merchantNameNormalized: 'Owner Transfer', providerCategoryId: 'TRANSFER', vendorId: null, categoryId: null, suggestedInvoiceId: null, invoiceId: null, expenseId: null, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW, amount: new Prisma.Decimal(200), pending: false });
    prisma.merchantRule.create.mockResolvedValue({ id: 'rule-a' });
    await service.review('user-a', 'bank-row', { decision: BankReviewDecision.PERSONAL_TRANSFER, createMerchantRule: true });
    expect(prisma.merchantRule.create).toHaveBeenCalledWith({ data: expect.objectContaining({ bankAccountId: 'account-a', providerCategoryId: 'TRANSFER', direction: 'OUTFLOW', decision: MerchantRuleDecision.PERSONAL_TRANSFER, autoConfirm: true, vendorId: null, expenseCategoryId: null }) });
  });

  it('bulk review rejects transactions spanning restaurants', async () => {
    const { service, prisma } = setup();
    prisma.bankTransaction.findMany.mockResolvedValue([
      { id: '00000000-0000-4000-8000-000000000001', organizationId: 'org-a', restaurantLocationId: 'location-a' },
      { id: '00000000-0000-4000-8000-000000000002', organizationId: 'org-a', restaurantLocationId: 'location-b' },
    ]);
    await expect(service.bulkReview('user-a', { ids: ['00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002'] })).rejects.toThrow('one restaurant');
  });

  it('reports partial bulk success so clients can refresh completed rows', async () => {
    const { service, prisma } = setup();
    const firstId = '00000000-0000-4000-8000-000000000001';
    const secondId = '00000000-0000-4000-8000-000000000002';
    prisma.bankTransaction.findMany.mockResolvedValue([
      { id: firstId, organizationId: 'org-a', restaurantLocationId: 'location-a' },
      { id: secondId, organizationId: 'org-a', restaurantLocationId: 'location-a' },
    ]);
    jest
      .spyOn(service, 'review')
      .mockResolvedValueOnce({ id: firstId } as any)
      .mockRejectedValueOnce(new ConflictException('Transaction changed'));

    await expect(
      service.bulkReview('user-a', { ids: [firstId, secondId] }),
    ).resolves.toEqual(
      expect.objectContaining({
        requestedCount: 2,
        count: 1,
        failedCount: 1,
        failures: [{ id: secondId, message: 'Transaction changed' }],
      }),
    );
  });

  it('revalidates explicit grouped ids and never broadens the selection', async () => {
    const { service, prisma } = setup();
    const anchorId = '00000000-0000-4000-8000-000000000001';
    const selectedId = '00000000-0000-4000-8000-000000000002';
    const unselectedId = '00000000-0000-4000-8000-000000000003';
    prisma.bankTransaction.findMany
      .mockResolvedValueOnce([
        { id: anchorId, organizationId: 'org-a', restaurantLocationId: 'location-a' },
        { id: selectedId, organizationId: 'org-a', restaurantLocationId: 'location-a' },
      ])
      .mockResolvedValueOnce([
        { id: anchorId, amount: new Prisma.Decimal(20) },
        { id: selectedId, amount: new Prisma.Decimal(30) },
        { id: unselectedId, amount: new Prisma.Decimal(40) },
      ]);
    prisma.bankTransaction.findUnique.mockResolvedValue({
      id: anchorId,
      organizationId: 'org-a',
      restaurantLocationId: 'location-a',
      bankAccountId: 'account-a',
      merchantNameNormalized: 'Robinhood',
      providerCategoryId: 'TRANSFER',
      providerCategory: 'Transfer',
      amount: new Prisma.Decimal(20),
      pending: false,
    });
    const review = jest.spyOn(service, 'review').mockImplementation(async (_userId, id) => ({ id }) as any);

    await expect(service.bulkReview('user-a', {
      ids: [anchorId, selectedId],
      groupAnchorId: anchorId,
      decision: BankReviewDecision.PERSONAL_TRANSFER,
    })).resolves.toEqual(expect.objectContaining({ requestedCount: 2, count: 2, failedCount: 0 }));
    expect(review.mock.calls.map((call) => call[1])).toEqual([anchorId, selectedId]);
    expect(review.mock.calls.map((call) => call[1])).not.toContain(unselectedId);
  });

  it('reports a transaction that leaves the previewed group before confirmation', async () => {
    const { service, prisma } = setup();
    const anchorId = '00000000-0000-4000-8000-000000000001';
    const staleId = '00000000-0000-4000-8000-000000000002';
    prisma.bankTransaction.findMany
      .mockResolvedValueOnce([
        { id: anchorId, organizationId: 'org-a', restaurantLocationId: 'location-a' },
        { id: staleId, organizationId: 'org-a', restaurantLocationId: 'location-a' },
      ])
      .mockResolvedValueOnce([{ id: anchorId, amount: new Prisma.Decimal(20) }]);
    prisma.bankTransaction.findUnique.mockResolvedValue({
      id: anchorId,
      organizationId: 'org-a',
      restaurantLocationId: 'location-a',
      bankAccountId: 'account-a',
      merchantNameNormalized: 'Robinhood',
      providerCategoryId: 'TRANSFER',
      providerCategory: 'Transfer',
      amount: new Prisma.Decimal(20),
      pending: false,
    });
    jest.spyOn(service, 'review').mockResolvedValue({ id: anchorId } as any);

    await expect(service.bulkReview('user-a', {
      ids: [anchorId, staleId],
      groupAnchorId: anchorId,
      decision: BankReviewDecision.PERSONAL_TRANSFER,
    })).resolves.toEqual(expect.objectContaining({
      requestedCount: 2,
      count: 1,
      failedCount: 1,
      failures: [{ id: staleId, message: 'Transaction is no longer eligible for this group' }],
    }));
  });

  it('reports complete bulk failure without claiming any transaction changed', async () => {
    const { service, prisma } = setup();
    const firstId = '00000000-0000-4000-8000-000000000001';
    const secondId = '00000000-0000-4000-8000-000000000002';
    prisma.bankTransaction.findMany.mockResolvedValue([
      { id: firstId, organizationId: 'org-a', restaurantLocationId: 'location-a' },
      { id: secondId, organizationId: 'org-a', restaurantLocationId: 'location-a' },
    ]);
    jest.spyOn(service, 'review')
      .mockRejectedValueOnce(new ConflictException('First transaction changed'))
      .mockRejectedValueOnce(new ConflictException('Second transaction changed'));

    await expect(service.bulkReview('user-a', { ids: [firstId, secondId] })).resolves.toEqual(expect.objectContaining({
      requestedCount: 2,
      count: 0,
      failedCount: 2,
      failures: [
        { id: firstId, message: 'First transaction changed' },
        { id: secondId, message: 'Second transaction changed' },
      ],
    }));
  });

  it('supports a reviewed similarity group larger than one hundred transactions', async () => {
    const { service, prisma } = setup();
    const ids = Array.from({ length: 101 }, (_, index) =>
      `00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
    );
    prisma.bankTransaction.findMany.mockResolvedValue(ids.map((id) => ({ id, organizationId: 'org-a', restaurantLocationId: 'location-a' })));
    jest.spyOn(service, 'review').mockImplementation(async (_userId, id) => ({ id }) as any);
    await expect(service.bulkReview('user-a', { ids, decision: BankReviewDecision.REVIEW_LATER })).resolves.toEqual(expect.objectContaining({ requestedCount: 101, count: 101, failedCount: 0 }));
  });

  it('reverses only a uniquely linked bank-created expense', async () => {
    const { service, prisma } = setup();
    const row = { id: 'bank-row', organizationId: 'org-a', expenseId: 'expense-created', reconciliationStatus: BankReconciliationStatus.MATCHED_EXPENSE };
    prisma.bankTransaction.findUnique.mockResolvedValue(row);
    prisma.expense.findUnique.mockResolvedValue({ id: 'expense-created', source: ExpenseSource.BANK_IMPORT });
    prisma.bankTransaction.count.mockResolvedValue(1);
    const mutationOrder: string[] = [];
    prisma.bankTransaction.update.mockImplementation(async () => {
      mutationOrder.push('unlink');
      return {};
    });
    prisma.expense.delete.mockImplementation(async () => {
      mutationOrder.push('delete');
      return {};
    });
    await service.reverseReconciliation('user-a', 'bank-row');
    expect(prisma.expense.delete).toHaveBeenCalledWith({ where: { id: 'expense-created' } });
    expect(prisma.bankTransaction.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ expenseId: null, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW }) }));
    expect(mutationOrder).toEqual(['unlink', 'delete']);
  });

  it('returns an ignored personal transfer to review without creating financial records', async () => {
    const { service, prisma, audit } = setup();
    prisma.bankTransaction.findUnique.mockResolvedValue({ id: 'bank-row', organizationId: 'org-a', expenseId: null, invoiceId: null, reconciliationStatus: BankReconciliationStatus.IGNORED });
    prisma.bankTransaction.update.mockResolvedValue({ id: 'bank-row', reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW });
    await expect(service.reverseReconciliation('user-a', 'bank-row')).resolves.toEqual(expect.objectContaining({ reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW }));
    expect(prisma.expense.delete).not.toHaveBeenCalled();
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'bank.transaction_ignore_reversed' }));
  });

  it('creates an update-mode link token and preserves the existing connection on reauth', async () => {
    const { service, provider, prisma } = setup();
    provider.createLinkToken.mockResolvedValue('update-link');
    const setupResult = await service.reauthenticationLinkToken('user-a', 'connection-a');
    expect(setupResult).toEqual(expect.objectContaining({ linkToken: 'update-link', updateMode: true }));
    expect(provider.createLinkToken).toHaveBeenCalledWith('user-a', 'provider-token', undefined);
    provider.sync.mockResolvedValue({ added: [], modified: [], removed: [], cursor: 'cursor' });
    await service.completeReauthentication('user-a', 'connection-a');
    await new Promise<void>((resolve) => setImmediate(resolve));
    expect(prisma.bankConnection.create).not.toHaveBeenCalled();
    expect(prisma.bankConnection.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ status: BankConnectionStatus.CONNECTED }) }));
    expect(provider.sync).toHaveBeenCalled();
  });

  it('uses only the dedicated configured redirect for web Link tokens', async () => {
    const previousEnvironment = process.env.PLAID_ENV;
    const previousWebRedirect = process.env.PLAID_WEB_REDIRECT_URI;
    process.env.PLAID_ENV = 'production';
    process.env.PLAID_WEB_REDIRECT_URI = 'https://app.example.com/banking';
    try {
      const { service, provider } = setup();
      provider.createLinkToken.mockResolvedValue('web-link');
      await service.linkToken('user-a', 'org-a', BankLinkClientPlatform.WEB);
      expect(provider.createLinkToken).toHaveBeenCalledWith(
        'user-a',
        undefined,
        'https://app.example.com/banking',
      );
    } finally {
      if (previousEnvironment == null) delete process.env.PLAID_ENV;
      else process.env.PLAID_ENV = previousEnvironment;
      if (previousWebRedirect == null) delete process.env.PLAID_WEB_REDIRECT_URI;
      else process.env.PLAID_WEB_REDIRECT_URI = previousWebRedirect;
    }
  });

  it('fails web Link safely in production when its HTTPS redirect is absent', async () => {
    const previousEnvironment = process.env.PLAID_ENV;
    const previousWebRedirect = process.env.PLAID_WEB_REDIRECT_URI;
    process.env.PLAID_ENV = 'production';
    delete process.env.PLAID_WEB_REDIRECT_URI;
    try {
      const { service, provider } = setup();
      await expect(
        service.linkToken('user-a', 'org-a', BankLinkClientPlatform.WEB),
      ).rejects.toThrow('Web bank connection is not configured yet.');
      expect(provider.createLinkToken).not.toHaveBeenCalled();
    } finally {
      if (previousEnvironment == null) delete process.env.PLAID_ENV;
      else process.env.PLAID_ENV = previousEnvironment;
      if (previousWebRedirect == null) delete process.env.PLAID_WEB_REDIRECT_URI;
      else process.env.PLAID_WEB_REDIRECT_URI = previousWebRedirect;
    }
  });

  it('rejects an insecure web redirect in production', async () => {
    const previousEnvironment = process.env.PLAID_ENV;
    const previousWebRedirect = process.env.PLAID_WEB_REDIRECT_URI;
    process.env.PLAID_ENV = 'production';
    process.env.PLAID_WEB_REDIRECT_URI = 'http://app.example.com/banking';
    try {
      const { service, provider } = setup();
      await expect(
        service.linkToken('user-a', 'org-a', BankLinkClientPlatform.WEB),
      ).rejects.toThrow('Web bank connection requires a secure HTTPS redirect.');
      expect(provider.createLinkToken).not.toHaveBeenCalled();
    } finally {
      if (previousEnvironment == null) delete process.env.PLAID_ENV;
      else process.env.PLAID_ENV = previousEnvironment;
      if (previousWebRedirect == null) delete process.env.PLAID_WEB_REDIRECT_URI;
      else process.env.PLAID_WEB_REDIRECT_URI = previousWebRedirect;
    }
  });

  it('disconnects remotely, deactivates sync, and does not delete transaction history', async () => {
    const { service, provider, prisma } = setup();
    await service.disconnect('user-a', 'connection-a');
    expect(provider.disconnect).toHaveBeenCalledWith('provider-token');
    expect(prisma.bankConnection.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ status: BankConnectionStatus.DISCONNECTED, syncCursor: null }) }));
    expect(prisma.bankTransaction.delete).not.toHaveBeenCalled();
  });

  it('creates a bank failure or reauthentication alert with stable keys', async () => {
    const { prisma, provider, service } = setup();
    const notifications = { notifyOperational: jest.fn() };
    const alerted = new BankService(prisma, { requireMember: jest.fn().mockResolvedValue({}) } as any, { log: jest.fn() } as any, { decrypt: jest.fn().mockReturnValue('token') } as any, { get: jest.fn().mockReturnValue(provider) } as any, notifications as any);
    provider.sync.mockRejectedValue(new Error('network'));
    await expect(alerted.sync('user-a', 'connection-a')).rejects.toThrow('network');
    expect(notifications.notifyOperational).toHaveBeenCalledWith(expect.objectContaining({ type: 'BANK_SYNC_FAILED', dedupeKey: 'bank-sync-failed:connection-a:Error' }));
    provider.sync.mockRejectedValue(new UnauthorizedException());
    await expect(alerted.sync('user-a', 'connection-a')).rejects.toBeInstanceOf(UnauthorizedException);
    expect(notifications.notifyOperational).toHaveBeenLastCalledWith(expect.objectContaining({ type: 'BANK_REAUTH_REQUIRED', dedupeKey: 'bank-reauth:connection-a' }));
  });
});
