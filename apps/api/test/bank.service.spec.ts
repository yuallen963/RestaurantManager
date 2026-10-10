import { ConflictException, ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { BankCategorizationSource, BankConnectionStatus, BankReconciliationStatus, ExpenseSource, InvoiceMatchConfidence, MerchantRuleMatchType, Prisma } from '@prisma/client';
import { BankService, normalizeMerchant } from '../src/bank/bank.service';
import { BankTokenEncryptionService } from '../src/bank/encryption.service';

const connection = { id: 'connection-a', organizationId: 'org-a', provider: 'DEMO', providerItemId: 'item-a', encryptedAccessToken: 'encrypted', status: 'CONNECTED', syncCursor: null, accounts: [{ id: 'account-a', providerAccountId: 'provider-account', restaurantLocationId: 'location-a', active: true }] };
const providerTransaction = { id: 'transaction-a', accountId: 'provider-account', date: '2026-10-08', merchantName: 'SYSCO FOOD SERVICES #1842', description: 'SYSCO ACH', amount: 1446, pending: false, category: 'Food distributor', categoryId: 'FOOD_AND_DRINK' };

function setup(overrides: { rules?: any[]; vendors?: any[]; invoices?: any[] } = {}) {
  const prisma: any = {
    bankConnection: { findUnique: jest.fn().mockResolvedValue(connection), update: jest.fn().mockImplementation(({ data }: any) => Promise.resolve({ ...connection, ...data })), updateMany: jest.fn().mockResolvedValue({ count: 1 }), create: jest.fn(), findMany: jest.fn() },
    bankAccount: { findUnique: jest.fn(), update: jest.fn() },
    bankTransaction: { create: jest.fn().mockResolvedValue({}), updateMany: jest.fn().mockResolvedValue({ count: 0 }), delete: jest.fn().mockResolvedValue({}), findUnique: jest.fn().mockResolvedValue(null), findFirst: jest.fn().mockResolvedValue(null), findMany: jest.fn().mockResolvedValue([]), update: jest.fn().mockResolvedValue({}) },
    merchantRule: { findMany: jest.fn().mockResolvedValue(overrides.rules ?? []), findFirst: jest.fn().mockResolvedValue(null), create: jest.fn(), update: jest.fn() },
    vendor: { findMany: jest.fn().mockResolvedValue(overrides.vendors ?? [{ id: 'sysco', normalizedName: 'sysco' }]), findFirst: jest.fn() },
    expenseCategory: { findFirst: jest.fn().mockResolvedValue({ id: 'category-a' }) },
    invoice: { findMany: jest.fn().mockResolvedValue(overrides.invoices ?? []), findFirst: jest.fn() },
    expense: { findUnique: jest.fn(), findMany: jest.fn().mockResolvedValue([]), create: jest.fn().mockResolvedValue({ id: 'expense-created' }), update: jest.fn() },
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
    expect(prisma.bankConnection.create).not.toHaveBeenCalled();
    expect(prisma.bankConnection.update).toHaveBeenCalledWith(expect.objectContaining({ where: { id: 'connection-a' }, data: expect.objectContaining({ status: BankConnectionStatus.CONNECTED }) }));
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

  it('creates an update-mode link token and preserves the existing connection on reauth', async () => {
    const { service, provider, prisma } = setup();
    provider.createLinkToken.mockResolvedValue('update-link');
    const setupResult = await service.reauthenticationLinkToken('user-a', 'connection-a');
    expect(setupResult).toEqual(expect.objectContaining({ linkToken: 'update-link', updateMode: true }));
    expect(provider.createLinkToken).toHaveBeenCalledWith('user-a', 'provider-token');
    provider.sync.mockResolvedValue({ added: [], modified: [], removed: [], cursor: 'cursor' });
    await service.completeReauthentication('user-a', 'connection-a');
    expect(prisma.bankConnection.create).not.toHaveBeenCalled();
    expect(prisma.bankConnection.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ status: BankConnectionStatus.CONNECTED }) }));
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
