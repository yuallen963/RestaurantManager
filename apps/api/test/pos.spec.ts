import { ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHmac } from 'node:crypto';
import { BankTokenEncryptionService } from '../src/bank/encryption.service';
import { aggregateSquareOrders, businessDate, PosService } from '../src/pos/pos.service';
import { SquareProvider } from '../src/pos/square.provider';

describe('Square POS integration', () => {
  beforeEach(() => { jest.restoreAllMocks(); process.env.SQUARE_ENV = 'sandbox'; });

  it('uses the Square location timezone for the business date', () => {
    expect(businessDate('2026-10-10T03:30:00.000Z', 'America/Detroit')).toBe('2026-10-09');
  });

  it('calculates deterministic net restaurant sales excluding tax and tips', () => {
    const [day] = aggregateSquareOrders([{ state: 'COMPLETED', closed_at: '2026-10-09T18:00:00Z', updated_at: '2026-10-09T18:01:00Z', net_amounts: { total_money: { amount: 12000 }, discount_money: { amount: 500 }, refund_money: { amount: 0 }, tax_money: { amount: 800 }, tip_money: { amount: 1200 } } }], 'America/Detroit');
    expect(day).toMatchObject({ businessDate: '2026-10-09', grossSales: 10500, discounts: 500, refunds: 0, taxes: 800, tips: 1200, netSales: 10000, transactionCount: 1 });
  });

  it('applies partial refunds and excludes voided or incomplete orders', () => {
    const rows = aggregateSquareOrders([
      { state: 'COMPLETED', closed_at: '2026-10-09T18:00:00Z', net_amounts: { total_money: { amount: 10000 }, tax_money: { amount: 600 }, tip_money: { amount: 400 }, refund_money: { amount: 0 } } },
      { state: 'COMPLETED', closed_at: '2026-10-09T20:00:00Z', net_amounts: { total_money: { amount: -3200 }, tax_money: { amount: -200 }, tip_money: { amount: 0 }, refund_money: { amount: 3000 } } },
      { state: 'CANCELED', closed_at: '2026-10-09T20:00:00Z', net_amounts: { total_money: { amount: 99999 } } },
      { state: 'OPEN', closed_at: '2026-10-09T20:00:00Z', net_amounts: { total_money: { amount: 99999 } } },
    ], 'America/Detroit');
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ netSales: 6000, refunds: 3000, transactionCount: 2 });
  });

  it('follows Square order pagination without calling production', async () => {
    const fetchMock = jest.spyOn(global, 'fetch' as any)
      .mockResolvedValueOnce(new Response(JSON.stringify({ orders: [{ id: 'one' }], cursor: 'next' }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ orders: [{ id: 'two' }] }), { status: 200 }));
    const orders = await new SquareProvider().orders('secret-token', 'square-location', new Date('2026-10-01'), new Date('2026-10-02'));
    expect(orders.map((order) => order.id)).toEqual(['one', 'two']);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect((fetchMock.mock.calls[1][1] as RequestInit).body).toContain('"cursor":"next"');
  });

  it('encrypts POS credentials with authenticated encryption', () => {
    process.env.POS_TOKEN_ENCRYPTION_KEY = Buffer.alloc(32, 7).toString('base64');
    const encryption = new BankTokenEncryptionService();
    const stored = encryption.encryptPos('square-access-token');
    expect(stored).not.toContain('square-access-token');
    expect(encryption.decryptPos(stored)).toBe('square-access-token');
  });

  it('authorizes OAuth only after organization membership succeeds', async () => {
    const prisma: any = { posOAuthState: { create: jest.fn() } };
    const access = { requireMember: jest.fn().mockRejectedValue(new ForbiddenException()) };
    const square = { authorizationUrl: jest.fn() };
    const service = new PosService(prisma, access as any, {} as any, {} as any, square as any);
    await expect(service.authorization('other-user', 'org-a')).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.posOAuthState.create).not.toHaveBeenCalled();
  });

  it('never returns encrypted access or refresh tokens from connection APIs', async () => {
    const prisma: any = { posConnection: { findMany: jest.fn().mockResolvedValue([{ id: 'connection', organizationId: 'org-a', encryptedAccessToken: 'cipher-a', encryptedRefreshToken: 'cipher-r', providerMerchantId: 'merchant', status: 'CONNECTED', mappings: [], dailySales: [] }]) } };
    const access = { requireMember: jest.fn().mockResolvedValue({}) };
    const service = new PosService(prisma, access as any, {} as any, {} as any, {} as any);
    const [result] = await service.list('user-a', 'org-a');
    expect(result.encryptedAccessToken).toBeUndefined();
    expect(result.encryptedRefreshToken).toBeUndefined();
  });

  it('persists OAuth credentials only after one-time tenant state validation', async () => {
    const prisma: any = {
      posOAuthState: { findUnique: jest.fn().mockResolvedValue({ id: 'state-id', organizationId: 'org-a', userId: 'user-a', expiresAt: new Date(Date.now() + 60000), usedAt: null }), update: jest.fn().mockResolvedValue({}) },
      posConnection: { findUnique: jest.fn().mockResolvedValue(null), upsert: jest.fn(({ create }) => Promise.resolve({ id: 'connection', ...create })) },
    };
    const audit = { log: jest.fn().mockResolvedValue(undefined) };
    const encryption = { encryptPos: jest.fn((value: string) => `encrypted:${value}`) };
    const square = { exchange: jest.fn().mockResolvedValue({ accessToken: 'access-secret', refreshToken: 'refresh-secret', merchantId: 'merchant-a' }), merchant: jest.fn().mockResolvedValue({ id: 'merchant-a', business_name: 'Sandbox Cafe' }) };
    const service = new PosService(prisma, {} as any, audit as any, encryption as any, square as any);
    const result = await service.callback('authorization-code', 'oauth-state');
    expect(result).toEqual({ connected: true, connectionId: 'connection' });
    expect(prisma.posOAuthState.update).toHaveBeenCalledWith(expect.objectContaining({ where: { id: 'state-id' }, data: { usedAt: expect.any(Date) } }));
    const create = prisma.posConnection.upsert.mock.calls[0][0].create;
    expect(create.encryptedAccessToken).toBe('encrypted:access-secret');
    expect(create.encryptedRefreshToken).toBe('encrypted:refresh-secret');
    expect(JSON.stringify(result)).not.toContain('secret');
  });

  it('rejects cross-tenant restaurant location mapping', async () => {
    const prisma: any = {
      posConnection: { findUnique: jest.fn().mockResolvedValue({ id: 'connection', organizationId: 'org-a', mappings: [] }) },
      restaurantLocation: { findUnique: jest.fn().mockResolvedValue({ id: 'loc-b', organizationId: 'org-b' }) },
    };
    const access = { requireMember: jest.fn().mockResolvedValue({}) };
    const service = new PosService(prisma, access as any, {} as any, {} as any, {} as any);
    await expect(service.map('user-a', 'connection', { restaurantLocationId: 'loc-b', providerLocationId: 'square-a', providerLocationName: 'Square A', providerTimezone: 'UTC' })).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('verifies Square webhooks and makes duplicate events idempotent', async () => {
    process.env.SQUARE_WEBHOOK_SIGNATURE_KEY = 'signature-key';
    process.env.SQUARE_WEBHOOK_NOTIFICATION_URL = 'https://api.example.com/api/v1/pos/square/webhook';
    const body = Buffer.from(JSON.stringify({ event_id: 'event-a', type: 'order.updated', merchant_id: 'merchant-a' }));
    const signature = createHmac('sha256', 'signature-key').update(process.env.SQUARE_WEBHOOK_NOTIFICATION_URL + body.toString('utf8')).digest('base64');
    const duplicate = new Prisma.PrismaClientKnownRequestError('duplicate', { code: 'P2002', clientVersion: '6.19.3' });
    const prisma: any = { posWebhookEvent: { create: jest.fn().mockRejectedValue(duplicate), update: jest.fn() }, posConnection: { findUnique: jest.fn() } };
    const service = new PosService(prisma, {} as any, {} as any, {} as any, {} as any);
    await expect(service.webhook('bad-signature', body, JSON.parse(body.toString()))).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.webhook(signature, body, JSON.parse(body.toString()))).resolves.toEqual({ received: true, duplicate: true });
  });

  it('revokes and disables a Square connection without deleting imported revenue', async () => {
    const connection = { id: 'connection', organizationId: 'org-a', encryptedAccessToken: 'cipher', status: 'CONNECTED', mappings: [] };
    const prisma: any = { posConnection: { findUnique: jest.fn().mockResolvedValue(connection), update: jest.fn().mockResolvedValue({}) } };
    const access = { requireMember: jest.fn().mockResolvedValue({}) };
    const audit = { log: jest.fn().mockResolvedValue(undefined) };
    const encryption = { decryptPos: jest.fn().mockReturnValue('access-token'), encryptPos: jest.fn().mockReturnValue('revoked-cipher') };
    const square = { revoke: jest.fn().mockResolvedValue(undefined) };
    const service = new PosService(prisma, access as any, audit as any, encryption as any, square as any);
    await service.disconnect('user-a', 'connection');
    expect(square.revoke).toHaveBeenCalledWith('access-token');
    expect(prisma.posConnection.update).toHaveBeenCalledWith({ where: { id: 'connection' }, data: { status: 'DISCONNECTED', encryptedAccessToken: 'revoked-cipher', encryptedRefreshToken: null } });
  });

  it('creates POS failure and reauthentication alerts with stable keys', async () => {
    const connection = { id: 'connection-a', organizationId: 'org-a', createdByUserId: 'user-a', encryptedAccessToken: 'cipher', tokenExpiresAt: null, status: 'CONNECTED', mappings: [] };
    const prisma: any = { posConnection: { findUnique: jest.fn().mockResolvedValue(connection), update: jest.fn().mockResolvedValue(connection) } };
    const notifications = { notifyOperational: jest.fn() };
    const service = new PosService(prisma, { requireMember: jest.fn().mockResolvedValue({}) } as any, { log: jest.fn() } as any, { decryptPos: jest.fn(() => { throw new Error('network'); }) } as any, {} as any, notifications as any);
    await expect(service.sync('user-a', 'connection-a')).rejects.toThrow('Unable to sync Square');
    expect(notifications.notifyOperational).toHaveBeenCalledWith(expect.objectContaining({ type: 'POS_SYNC_FAILED', dedupeKey: 'pos-sync-failed:connection-a:Error' }));
    const reauth = new PosService(prisma, { requireMember: jest.fn().mockResolvedValue({}) } as any, { log: jest.fn() } as any, { decryptPos: jest.fn(() => { throw new UnauthorizedException(); }) } as any, {} as any, notifications as any);
    await expect(reauth.sync('user-a', 'connection-a')).rejects.toThrow('Square authorization must be renewed');
    expect(notifications.notifyOperational).toHaveBeenLastCalledWith(expect.objectContaining({ type: 'POS_REAUTH_REQUIRED', dedupeKey: 'pos-reauth:connection-a' }));
  });
});
