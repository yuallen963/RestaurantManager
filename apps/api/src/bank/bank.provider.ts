import { Injectable, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { createHash } from 'node:crypto';

export type ProviderAccount = { id: string; name: string; mask?: string; subtype?: string; type?: string };
export type ProviderTransaction = { id: string; accountId: string; date: string; authorizedDate?: string; merchantName?: string; description: string; amount: number; pending: boolean; category?: string; categoryId?: string; pendingTransactionId?: string };
export type ProviderSync = { added: ProviderTransaction[]; modified: ProviderTransaction[]; removed: string[]; cursor: string };
export type ProviderExchange = { accessToken: string; itemId: string; institutionId?: string; institutionName?: string; accounts: ProviderAccount[] };

export interface BankProviderClient {
  readonly name: 'PLAID' | 'DEMO';
  createLinkToken(userId: string, accessToken?: string): Promise<string>;
  exchange(publicToken: string): Promise<ProviderExchange>;
  sync(accessToken: string, cursor?: string | null): Promise<ProviderSync>;
  disconnect(accessToken: string): Promise<void>;
}

class BankSyncMutationException extends Error {}

class DemoBankProvider implements BankProviderClient {
  readonly name = 'DEMO' as const;
  async createLinkToken(userId: string) { return `demo-link-${userId}`; }
  async exchange(publicToken: string): Promise<ProviderExchange> {
    const identity = createHash('sha256').update(publicToken).digest('hex').slice(0, 16);
    return { accessToken: `demo-access-${identity}`, itemId: `demo-item-${identity}`, institutionId: 'demo-bank', institutionName: 'Profit Lens Sandbox Bank', accounts: [{ id: `demo-checking-${identity}`, name: 'Business Checking', mask: '4242', subtype: 'checking', type: 'depository' }] };
  }
  async sync(accessToken: string, cursor?: string | null): Promise<ProviderSync> {
    const identity = accessToken.replace(/^demo-access-/, '');
    const accountId = `demo-checking-${identity}`;
    const today = new Date();
    const day = (offset: number) => { const date = new Date(today); date.setUTCDate(date.getUTCDate() + offset); return date.toISOString().slice(0, 10); };
    if (cursor === 'demo-cursor-1') return { added: [{ id: 'demo-rochester-repeat', accountId, date: day(0), merchantName: 'ROCHESTER MARKET 8841', description: 'ROCHESTER MARKET 8841', amount: 42.1, pending: false, category: 'General Merchandise', categoryId: 'GENERAL_MERCHANDISE' }], modified: [], removed: [], cursor: 'demo-cursor-2' };
    if (cursor) return { added: [], modified: [], removed: [], cursor };
    return { cursor: 'demo-cursor-1', modified: [], removed: [], added: [
      { id: 'demo-sysco-invoice', accountId, date: day(-3), merchantName: 'SYSCO FOOD SERVICES #1842', description: 'SYSCO ACH PAYMENT', amount: 1446, pending: false, category: 'Food and Drink', categoryId: 'FOOD_AND_DRINK' },
      { id: 'demo-adp-payroll', accountId, date: day(-2), merchantName: 'ADP PAYROLL', description: 'ADP PAYROLL', amount: 3810.25, pending: false, category: 'Payroll', categoryId: 'PAYROLL' },
      { id: 'demo-dte-utility', accountId, date: day(-1), merchantName: 'DTE ENERGY PAYMENT', description: 'DTE ENERGY PAYMENT', amount: 612.44, pending: false, category: 'Utilities', categoryId: 'UTILITIES' },
      { id: 'demo-unknown', accountId, date: day(0), merchantName: 'ROCHESTER MARKET 7732', description: 'ROCHESTER MARKET 7732', amount: 84.19, pending: false, category: 'General Merchandise', categoryId: 'GENERAL_MERCHANDISE' },
      { id: 'demo-credit', accountId, date: day(-4), merchantName: 'CARD REWARD', description: 'CASH BACK REWARD', amount: -12.5, pending: false, category: 'Transfer', categoryId: 'TRANSFER_IN' },
    ] };
  }
  async disconnect(_accessToken: string) {}
}

class PlaidBankProvider implements BankProviderClient {
  readonly name = 'PLAID' as const;
  private baseUrl = process.env.PLAID_ENV === 'production' ? 'https://production.plaid.com' : process.env.PLAID_ENV === 'development' ? 'https://development.plaid.com' : 'https://sandbox.plaid.com';
  private async post(path: string, body: Record<string, unknown>) {
    const response = await fetch(`${this.baseUrl}${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'PLAID-CLIENT-ID': process.env.PLAID_CLIENT_ID!, 'PLAID-SECRET': process.env.PLAID_SECRET! }, body: JSON.stringify(body) });
    const data = await response.json() as any;
    if (!response.ok) {
      if (data.error_code === 'ITEM_LOGIN_REQUIRED') throw new UnauthorizedException('Reconnect your bank to continue syncing.');
      if (data.error_code === 'TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION') throw new BankSyncMutationException();
      throw new ServiceUnavailableException('The bank provider is temporarily unavailable.');
    }
    return data;
  }
  async createLinkToken(userId: string, accessToken?: string) {
    const redirectUri = process.env.PLAID_REDIRECT_URI?.trim();
    if (process.env.PLAID_ENV === 'production' && !redirectUri) throw new ServiceUnavailableException('Plaid OAuth redirect is not configured');
    const data = await this.post('/link/token/create', { client_name: 'Profit Lens', language: 'en', country_codes: (process.env.PLAID_COUNTRY_CODES ?? 'US').split(','), products: accessToken ? undefined : (process.env.PLAID_PRODUCTS ?? 'transactions').split(','), user: { client_user_id: userId }, access_token: accessToken, redirect_uri: redirectUri || undefined, webhook: process.env.PLAID_WEBHOOK_URL || undefined, transactions: accessToken ? undefined : { days_requested: 90 } });
    return data.link_token as string;
  }
  async exchange(publicToken: string): Promise<ProviderExchange> {
    const exchanged = await this.post('/item/public_token/exchange', { public_token: publicToken });
    const accountData = await this.post('/accounts/get', { access_token: exchanged.access_token });
    const institutionId = accountData.item?.institution_id;
    let institutionName: string | undefined;
    if (institutionId) {
      const institution = await this.post('/institutions/get_by_id', { institution_id: institutionId, country_codes: (process.env.PLAID_COUNTRY_CODES ?? 'US').split(',') });
      institutionName = institution.institution?.name;
    }
    return { accessToken: exchanged.access_token, itemId: exchanged.item_id, institutionId, institutionName, accounts: accountData.accounts.map((a: any) => ({ id: a.account_id, name: a.name, mask: a.mask, subtype: a.subtype, type: a.type })) };
  }
  async sync(accessToken: string, cursor?: string | null): Promise<ProviderSync> {
    for (let attempt = 0; attempt < 2; attempt++) {
      let next = cursor ?? undefined; const added: ProviderTransaction[] = []; const modified: ProviderTransaction[] = []; const removed: string[] = [];
      try {
        do {
          const data = await this.post('/transactions/sync', { access_token: accessToken, cursor: next, count: 500 });
          const map = (t: any): ProviderTransaction => ({ id: t.transaction_id, accountId: t.account_id, date: t.date, authorizedDate: t.authorized_date ?? undefined, merchantName: t.merchant_name ?? undefined, description: t.name, amount: Number(t.amount), pending: Boolean(t.pending), category: t.personal_finance_category?.primary ?? t.category?.[0], categoryId: t.personal_finance_category?.primary ?? t.category_id, pendingTransactionId: t.pending_transaction_id ?? undefined });
          added.push(...data.added.map(map)); modified.push(...data.modified.map(map)); removed.push(...data.removed.map((r: any) => r.transaction_id)); next = data.next_cursor;
          if (!data.has_more) break;
        } while (true);
        return { added, modified, removed, cursor: next! };
      } catch (error) {
        if (!(error instanceof BankSyncMutationException) || attempt === 1) throw error;
      }
    }
    throw new ServiceUnavailableException('The bank provider is temporarily unavailable.');
  }
  async disconnect(accessToken: string) { await this.post('/item/remove', { access_token: accessToken }); }
}

@Injectable()
export class BankProviderFactory {
  get(provider?: 'PLAID' | 'DEMO'): BankProviderClient {
    if (provider === 'DEMO') return new DemoBankProvider();
    if (provider === 'PLAID') {
      if (!process.env.PLAID_CLIENT_ID || !process.env.PLAID_SECRET) throw new ServiceUnavailableException('Bank connections are not configured');
      return new PlaidBankProvider();
    }
    const configured = process.env.BANK_PROVIDER?.toLowerCase();
    if (configured === 'demo') return new DemoBankProvider();
    if (!process.env.PLAID_CLIENT_ID || !process.env.PLAID_SECRET) throw new ServiceUnavailableException('Bank connections are not configured');
    return new PlaidBankProvider();
  }
}
