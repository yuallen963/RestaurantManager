import { ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { BankProviderFactory } from '../src/bank/bank.provider';

const response = (body: unknown, ok = true, status = 200) => ({
  ok,
  status,
  json: jest.fn().mockResolvedValue(body),
}) as any;

describe('Plaid bank provider', () => {
  const original = { ...process.env };

  beforeEach(() => {
    process.env.PLAID_CLIENT_ID = 'configured-client';
    process.env.PLAID_SECRET = 'configured-secret';
    process.env.PLAID_ENV = 'sandbox';
    process.env.PLAID_PRODUCTS = 'transactions';
    process.env.PLAID_REDIRECT_URI = 'https://example.com/plaid/oauth';
    global.fetch = jest.fn();
  });

  afterEach(() => {
    process.env = { ...original };
    jest.restoreAllMocks();
  });

  it('fails safely when Plaid credentials are missing', () => {
    delete process.env.PLAID_CLIENT_ID;
    delete process.env.PLAID_SECRET;
    expect(() => new BankProviderFactory().get('PLAID')).toThrow(ServiceUnavailableException);
  });

  it('creates normal and update-mode Link tokens without returning access credentials', async () => {
    (global.fetch as jest.Mock).mockResolvedValue(response({ link_token: 'link-token' }));
    const provider = new BankProviderFactory().get('PLAID');
    await expect(provider.createLinkToken('user-a')).resolves.toBe('link-token');
    await expect(provider.createLinkToken('user-a', 'access-token')).resolves.toBe('link-token');
    const normal = JSON.parse((global.fetch as jest.Mock).mock.calls[0][1].body);
    const update = JSON.parse((global.fetch as jest.Mock).mock.calls[1][1].body);
    expect(normal).toEqual(expect.objectContaining({ products: ['transactions'], user: { client_user_id: 'user-a' } }));
    expect(update).toEqual(expect.objectContaining({ access_token: 'access-token', user: { client_user_id: 'user-a' } }));
    expect(normal.redirect_uri).toBe('https://example.com/plaid/oauth');
    expect(update.redirect_uri).toBe('https://example.com/plaid/oauth');
    expect(update.products).toBeUndefined();
  });

  it('requires an explicit redirect URI in production', async () => {
    process.env.PLAID_ENV = 'production';
    delete process.env.PLAID_REDIRECT_URI;
    await expect(new BankProviderFactory().get('PLAID').createLinkToken('user-a')).rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('exchanges a token, imports accounts, and resolves institution metadata', async () => {
    (global.fetch as jest.Mock)
      .mockResolvedValueOnce(response({ access_token: 'access', item_id: 'item' }))
      .mockResolvedValueOnce(response({ item: { institution_id: 'ins' }, accounts: [{ account_id: 'account', name: 'Checking', mask: '1234', subtype: 'checking', type: 'depository' }] }))
      .mockResolvedValueOnce(response({ institution: { name: 'Sandbox Bank' } }));
    const result = await new BankProviderFactory().get('PLAID').exchange('public');
    expect(result).toEqual(expect.objectContaining({ accessToken: 'access', itemId: 'item', institutionId: 'ins', institutionName: 'Sandbox Bank' }));
    expect(result.accounts).toEqual([expect.objectContaining({ id: 'account', mask: '1234' })]);
  });

  it('paginates transaction sync and preserves pending transition metadata', async () => {
    (global.fetch as jest.Mock)
      .mockResolvedValueOnce(response({ added: [{ transaction_id: 'pending', account_id: 'account', date: '2026-10-01', name: 'STORE', amount: 20, pending: true }], modified: [], removed: [], next_cursor: 'one', has_more: true }))
      .mockResolvedValueOnce(response({ added: [{ transaction_id: 'posted', pending_transaction_id: 'pending', account_id: 'account', date: '2026-10-02', name: 'STORE', amount: 20, pending: false }], modified: [], removed: [{ transaction_id: 'removed' }], next_cursor: 'two', has_more: false }));
    const result = await new BankProviderFactory().get('PLAID').sync('access');
    expect(result.cursor).toBe('two');
    expect(result.added).toHaveLength(2);
    expect(result.added[1]).toEqual(expect.objectContaining({ id: 'posted', pendingTransactionId: 'pending' }));
    expect(result.removed).toEqual(['removed']);
  });

  it('maps ITEM_LOGIN_REQUIRED to a safe reauthentication error', async () => {
    (global.fetch as jest.Mock).mockResolvedValue(response({ error_code: 'ITEM_LOGIN_REQUIRED' }, false, 400));
    await expect(new BankProviderFactory().get('PLAID').sync('access')).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('restarts pagination once when Plaid reports a sync mutation', async () => {
    (global.fetch as jest.Mock)
      .mockResolvedValueOnce(response({ added: [], modified: [], removed: [], next_cursor: 'page-two', has_more: true }))
      .mockResolvedValueOnce(response({ error_code: 'TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION' }, false, 400))
      .mockResolvedValueOnce(response({ added: [{ transaction_id: 'stable', account_id: 'account', date: '2026-10-02', name: 'STORE', amount: 20, pending: false }], modified: [], removed: [], next_cursor: 'stable-cursor', has_more: false }));
    const result = await new BankProviderFactory().get('PLAID').sync('access', 'original-cursor');
    expect(result.added.map((item) => item.id)).toEqual(['stable']);
    expect(result.cursor).toBe('stable-cursor');
    expect(JSON.parse((global.fetch as jest.Mock).mock.calls[2][1].body).cursor).toBe('original-cursor');
  });
});

describe('demo bank provider tenancy', () => {
  it('derives stable, distinct item/account identities per organization token', async () => {
    const provider = new BankProviderFactory().get('DEMO');
    const first = await provider.exchange('demo-public-org-a');
    const retry = await provider.exchange('demo-public-org-a');
    const second = await provider.exchange('demo-public-org-b');
    expect(first.itemId).toBe(retry.itemId);
    expect(first.itemId).not.toBe(second.itemId);
    const synced = await provider.sync(first.accessToken);
    expect(synced.added.every((item) => item.accountId === first.accounts[0].id)).toBe(true);
  });
});
