import { Injectable, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';

export type SquareLocation = { id: string; name: string; timezone: string; status?: string };
export type SquareOrder = Record<string, any>;
export type SquareToken = { accessToken: string; refreshToken?: string; merchantId: string; expiresAt?: Date };

@Injectable()
export class SquareProvider {
  private get sandbox() { return (process.env.SQUARE_ENV ?? 'sandbox').toLowerCase() !== 'production'; }
  private get apiBase() { return this.sandbox ? 'https://connect.squareupsandbox.com' : 'https://connect.squareup.com'; }
  private get authorizeBase() { return this.sandbox ? 'https://connect.squareupsandbox.com' : 'https://connect.squareup.com'; }
  private configured() {
    if (!process.env.SQUARE_APPLICATION_ID || !process.env.SQUARE_APPLICATION_SECRET || !process.env.SQUARE_REDIRECT_URI) throw new ServiceUnavailableException('Square integration is not configured');
  }
  authorizationUrl(state: string) {
    this.configured();
    const query = new URLSearchParams({ client_id: process.env.SQUARE_APPLICATION_ID!, scope: 'MERCHANT_PROFILE_READ ORDERS_READ PAYMENTS_READ', session: 'false', state, redirect_uri: process.env.SQUARE_REDIRECT_URI! });
    return `${this.authorizeBase}/oauth2/authorize?${query}`;
  }
  private async json(response: Response) {
    const data = await response.json().catch(() => ({})) as any;
    if (!response.ok) {
      if (response.status === 401) throw new UnauthorizedException('Square authorization must be renewed');
      throw new ServiceUnavailableException(`Square request failed (${response.status})`);
    }
    return data;
  }
  async exchange(code: string): Promise<SquareToken> {
    this.configured();
    const response = await fetch(`${this.apiBase}/oauth2/token`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ client_id: process.env.SQUARE_APPLICATION_ID, client_secret: process.env.SQUARE_APPLICATION_SECRET, code, grant_type: 'authorization_code', redirect_uri: process.env.SQUARE_REDIRECT_URI, short_lived: false }) });
    const data = await this.json(response);
    return { accessToken: data.access_token, refreshToken: data.refresh_token, merchantId: data.merchant_id, expiresAt: data.expires_at ? new Date(data.expires_at) : undefined };
  }
  async refresh(refreshToken: string): Promise<SquareToken> {
    this.configured();
    const response = await fetch(`${this.apiBase}/oauth2/token`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ client_id: process.env.SQUARE_APPLICATION_ID, client_secret: process.env.SQUARE_APPLICATION_SECRET, refresh_token: refreshToken, grant_type: 'refresh_token' }) });
    const data = await this.json(response);
    return { accessToken: data.access_token, refreshToken: data.refresh_token ?? refreshToken, merchantId: data.merchant_id, expiresAt: data.expires_at ? new Date(data.expires_at) : undefined };
  }
  private headers(accessToken: string) { return { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json', 'Square-Version': process.env.SQUARE_API_VERSION ?? '2026-09-16' }; }
  async merchant(accessToken: string, merchantId: string) {
    const data = await this.json(await fetch(`${this.apiBase}/v2/merchants/${encodeURIComponent(merchantId)}`, { headers: this.headers(accessToken) }));
    return data.merchant as { id: string; business_name?: string };
  }
  async locations(accessToken: string): Promise<SquareLocation[]> {
    const data = await this.json(await fetch(`${this.apiBase}/v2/locations`, { headers: this.headers(accessToken) }));
    return (data.locations ?? []).filter((item: any) => item.status !== 'INACTIVE').map((item: any) => ({ id: item.id, name: item.name ?? 'Square location', timezone: item.timezone ?? 'UTC', status: item.status }));
  }
  async orders(accessToken: string, locationId: string, beginTime: Date, endTime: Date): Promise<SquareOrder[]> {
    const orders: SquareOrder[] = []; let cursor: string | undefined;
    do {
      const response = await fetch(`${this.apiBase}/v2/orders/search`, { method: 'POST', headers: this.headers(accessToken), body: JSON.stringify({ location_ids: [locationId], cursor, limit: 500, query: { filter: { date_time_filter: { updated_at: { start_at: beginTime.toISOString(), end_at: endTime.toISOString() } }, state_filter: { states: ['COMPLETED'] } }, sort: { sort_field: 'UPDATED_AT', sort_order: 'ASC' } } }) });
      const data = await this.json(response); orders.push(...(data.orders ?? [])); cursor = data.cursor;
    } while (cursor);
    return orders;
  }
  async revoke(accessToken: string) {
    this.configured();
    const response = await fetch(`${this.apiBase}/oauth2/revoke`, { method: 'POST', headers: { Authorization: `Client ${process.env.SQUARE_APPLICATION_SECRET}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ client_id: process.env.SQUARE_APPLICATION_ID, access_token: accessToken }) });
    if (!response.ok && response.status !== 404) throw new ServiceUnavailableException('Unable to disconnect Square');
  }
}
