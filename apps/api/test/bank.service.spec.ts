import { ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { BankCategorizationSource, BankReconciliationStatus, InvoiceMatchConfidence, MerchantRuleMatchType, Prisma } from '@prisma/client';
import { BankService, normalizeMerchant } from '../src/bank/bank.service';
import { BankTokenEncryptionService } from '../src/bank/encryption.service';

const connection = { id: 'connection-a', organizationId: 'org-a', provider: 'DEMO', providerItemId: 'item-a', encryptedAccessToken: 'encrypted', status: 'CONNECTED', syncCursor: null, accounts: [{ id: 'account-a', providerAccountId: 'provider-account', restaurantLocationId: 'location-a' }] };
const providerTransaction = { id: 'transaction-a', accountId: 'provider-account', date: '2026-10-08', merchantName: 'SYSCO FOOD SERVICES #1842', description: 'SYSCO ACH', amount: 1446, pending: false, category: 'Food distributor', categoryId: 'FOOD_AND_DRINK' };

function setup(overrides: { rules?: any[]; vendors?: any[]; invoices?: any[] } = {}) {
  const prisma: any = {
    bankConnection: { findUnique: jest.fn().mockResolvedValue(connection), update: jest.fn().mockImplementation(({ data }: any) => Promise.resolve({ ...connection, ...data })), create: jest.fn(), findMany: jest.fn() },
    bankAccount: { findUnique: jest.fn(), update: jest.fn() },
    bankTransaction: { upsert: jest.fn().mockResolvedValue({}), updateMany: jest.fn().mockResolvedValue({ count: 0 }), deleteMany: jest.fn().mockResolvedValue({ count: 0 }), findUnique: jest.fn(), findFirst: jest.fn().mockResolvedValue(null), findMany: jest.fn().mockResolvedValue([]), update: jest.fn() },
    merchantRule: { findMany: jest.fn().mockResolvedValue(overrides.rules ?? []), findFirst: jest.fn().mockResolvedValue(null), create: jest.fn(), update: jest.fn() },
    vendor: { findMany: jest.fn().mockResolvedValue(overrides.vendors ?? [{ id: 'sysco', normalizedName: 'sysco' }]), findFirst: jest.fn() },
    expenseCategory: { findFirst: jest.fn().mockResolvedValue({ id: 'category-a' }) },
    invoice: { findMany: jest.fn().mockResolvedValue(overrides.invoices ?? []), findFirst: jest.fn() },
    restaurantLocation: { findFirst: jest.fn().mockResolvedValue({ id: 'location-a', organizationId: 'org-a' }) },
  };
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
    const create = prisma.bankTransaction.upsert.mock.calls[0][0].create;
    expect(create.amount.toNumber()).toBe(1446);
    expect(create.suggestedInvoiceId).toBe('invoice-a');
    expect(create.matchConfidence).toBe(InvoiceMatchConfidence.EXACT);
    expect(create.reconciliationStatus).toBe(BankReconciliationStatus.NEEDS_REVIEW);
    expect(prisma.expense?.create).toBeUndefined();
  });

  it('uses merchant rules before known vendors and provider categories', async () => {
    const rule = { matchType: MerchantRuleMatchType.CONTAINS, matchValue: 'SYSCO', vendorId: 'rule-vendor', expenseCategoryId: 'rule-category' };
    const { service, prisma } = setup({ rules: [rule] });
    await service.sync('user-a', 'connection-a');
    const create = prisma.bankTransaction.upsert.mock.calls[0][0].create;
    expect(create.vendorId).toBe('rule-vendor');
    expect(create.categoryId).toBe('rule-category');
    expect(create.categorizationSource).toBe(BankCategorizationSource.USER_RULE);
  });

  it('maps reliable provider payroll categories when no merchant is known', async () => {
    const { service, prisma, provider } = setup({ vendors: [] });
    provider.sync.mockResolvedValue({ added: [{ ...providerTransaction, merchantName: 'PAYROLL PROCESSOR', categoryId: 'PAYROLL' }], modified: [], removed: [], cursor: 'cursor-1' });
    await service.sync('user-a', 'connection-a');
    expect(prisma.expenseCategory.findFirst).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ slug: 'labor' }) }));
    expect(prisma.bankTransaction.upsert.mock.calls[0][0].create.categorizationSource).toBe(BankCategorizationSource.PROVIDER);
  });

  it('handles pending-to-posted transitions and removed transactions', async () => {
    const { service, prisma, provider } = setup();
    provider.sync.mockResolvedValue({ added: [{ ...providerTransaction, id: 'posted', pendingTransactionId: 'pending' }], modified: [], removed: ['removed'], cursor: 'cursor-2' });
    await service.sync('user-a', 'connection-a');
    expect(prisma.bankTransaction.deleteMany).toHaveBeenCalledWith({ where: { bankAccountId: 'account-a', providerTransactionId: 'pending', pending: true } });
    expect(prisma.bankTransaction.updateMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ providerTransactionId: 'removed' }) }));
  });

  it('uses a small tolerance only for likely invoice matches and rejects mismatches', async () => {
    const likely = { id: 'likely', vendorId: 'sysco', extractedVendorName: null, total: new Prisma.Decimal('1446.30'), invoiceDate: new Date('2026-10-05') };
    const first = setup({ invoices: [likely] });
    await first.service.sync('user-a', 'connection-a');
    expect(first.prisma.bankTransaction.upsert.mock.calls[0][0].create.matchConfidence).toBe(InvoiceMatchConfidence.LIKELY);
    const mismatch = setup({ invoices: [{ ...likely, total: new Prisma.Decimal('1500') }] });
    await mismatch.service.sync('user-a', 'connection-a');
    expect(mismatch.prisma.bankTransaction.upsert.mock.calls[0][0].create.matchConfidence).toBe(InvoiceMatchConfidence.NO_MATCH);
  });

  it('enforces tenant membership before connection access', async () => {
    const { service, access } = setup();
    access.requireMember.mockRejectedValue(new ForbiddenException());
    await expect(service.sync('other-user', 'connection-a')).rejects.toBeInstanceOf(ForbiddenException);
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
