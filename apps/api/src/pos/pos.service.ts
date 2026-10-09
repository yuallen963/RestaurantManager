import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { PosConnectionStatus, PosProvider, PosRevenueConflictStatus, Prisma, RevenueSource } from '@prisma/client';
import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { AuditService } from '../audit.service';
import { BankTokenEncryptionService } from '../bank/encryption.service';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PrismaService } from '../prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PosMapLocationDto } from './dto';
import { SquareOrder, SquareProvider } from './square.provider';

const cents = (money: any) => Number(money?.amount ?? 0);
const dollars = (value: number) => new Prisma.Decimal(value).div(100).toDecimalPlaces(2);
export const businessDate = (timestamp: string, timezone: string) => {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date(timestamp));
  const part = (type: string) => parts.find((item) => item.type === type)?.value;
  return `${part('year')}-${part('month')}-${part('day')}`;
};
export type DailySales = { businessDate: string; grossSales: number; discounts: number; refunds: number; taxes: number; tips: number; netSales: number; transactionCount: number; providerUpdatedAt?: Date };
export function aggregateSquareOrders(orders: SquareOrder[], timezone: string): DailySales[] {
  const days = new Map<string, DailySales>();
  for (const order of orders) {
    if (order.state !== 'COMPLETED' || !order.closed_at) continue;
    const key = businessDate(order.closed_at, timezone);
    const amounts = order.net_amounts ?? {};
    const total = cents(amounts.total_money ?? order.total_money);
    const discounts = Math.abs(cents(amounts.discount_money ?? order.total_discount_money));
    const refunds = Math.abs(cents(amounts.refund_money));
    const taxes = cents(amounts.tax_money ?? order.total_tax_money);
    const tips = cents(amounts.tip_money ?? order.total_tip_money);
    const netSales = total - taxes - tips;
    const grossSales = netSales + discounts + refunds;
    const current = days.get(key) ?? { businessDate: key, grossSales: 0, discounts: 0, refunds: 0, taxes: 0, tips: 0, netSales: 0, transactionCount: 0 };
    current.grossSales += grossSales; current.discounts += discounts; current.refunds += refunds; current.taxes += taxes; current.tips += tips; current.netSales += netSales;
    current.transactionCount += netSales !== 0 ? 1 : 0;
    const updated = order.updated_at ? new Date(order.updated_at) : undefined;
    if (updated && (!current.providerUpdatedAt || updated > current.providerUpdatedAt)) current.providerUpdatedAt = updated;
    days.set(key, current);
  }
  return [...days.values()].sort((a, b) => a.businessDate.localeCompare(b.businessDate));
}

@Injectable()
export class PosService {
  constructor(private readonly prisma: PrismaService, private readonly access: OrganizationAccessService, private readonly audit: AuditService, private readonly encryption: BankTokenEncryptionService, private readonly square: SquareProvider, private readonly notifications?: NotificationsService) {}
  private safe(connection: any) { const { encryptedAccessToken: _a, encryptedRefreshToken: _r, ...safe } = connection; return safe; }
  async syncAll() {
    const connections = await this.prisma.posConnection.findMany({ where: { provider: PosProvider.SQUARE, status: { in: [PosConnectionStatus.CONNECTED, PosConnectionStatus.ERROR] } }, select: { id: true, createdByUserId: true } });
    const results = await Promise.allSettled(connections.map((connection) => this.sync(connection.createdByUserId, connection.id)));
    return { attempted: connections.length, completed: results.filter((result) => result.status === 'fulfilled').length };
  }
  private async connection(userId: string, id: string) {
    const row = await this.prisma.posConnection.findUnique({ where: { id }, include: { mappings: true } });
    if (!row) throw new NotFoundException('POS connection not found');
    await this.access.requireMember(userId, row.organizationId);
    return row;
  }
  async authorization(userId: string, organizationId: string) {
    await this.access.requireMember(userId, organizationId);
    const state = randomBytes(32).toString('base64url');
    await this.prisma.posOAuthState.create({ data: { organizationId, userId, stateHash: createHash('sha256').update(state).digest('hex'), expiresAt: new Date(Date.now() + 10 * 60 * 1000) } });
    return { authorizationUrl: this.square.authorizationUrl(state) };
  }
  async callback(code?: string, state?: string, error?: string) {
    if (error) throw new BadRequestException('Square authorization was denied');
    if (!code || !state) throw new BadRequestException('Square authorization response is incomplete');
    const stateHash = createHash('sha256').update(state).digest('hex');
    const saved = await this.prisma.posOAuthState.findUnique({ where: { stateHash } });
    if (!saved || saved.usedAt || saved.expiresAt < new Date()) throw new BadRequestException('Square authorization state is invalid or expired');
    await this.prisma.posOAuthState.update({ where: { id: saved.id }, data: { usedAt: new Date() } });
    const token = await this.square.exchange(code);
    const merchant = await this.square.merchant(token.accessToken, token.merchantId);
    const existing = await this.prisma.posConnection.findUnique({ where: { provider_providerMerchantId: { provider: PosProvider.SQUARE, providerMerchantId: token.merchantId } } });
    if (existing && existing.organizationId !== saved.organizationId) throw new ConflictException('This Square merchant is already connected to another organization');
    const connection = await this.prisma.posConnection.upsert({ where: { provider_providerMerchantId: { provider: PosProvider.SQUARE, providerMerchantId: token.merchantId } }, create: { organizationId: saved.organizationId, createdByUserId: saved.userId, providerMerchantId: token.merchantId, merchantName: merchant.business_name, encryptedAccessToken: this.encryption.encryptPos(token.accessToken), encryptedRefreshToken: token.refreshToken ? this.encryption.encryptPos(token.refreshToken) : null, tokenExpiresAt: token.expiresAt, status: PosConnectionStatus.CONNECTED }, update: { encryptedAccessToken: this.encryption.encryptPos(token.accessToken), encryptedRefreshToken: token.refreshToken ? this.encryption.encryptPos(token.refreshToken) : undefined, tokenExpiresAt: token.expiresAt, merchantName: merchant.business_name, status: PosConnectionStatus.CONNECTED, lastError: null } });
    await this.audit.log({ userId: saved.userId, organizationId: saved.organizationId, action: 'pos.square_connected', entityType: 'PosConnection', entityId: connection.id, metadata: { merchantId: token.merchantId } });
    return { connected: true, connectionId: connection.id };
  }
  async list(userId: string, organizationId: string) {
    await this.access.requireMember(userId, organizationId);
    const rows = await this.prisma.posConnection.findMany({ where: { organizationId, provider: PosProvider.SQUARE, status: { not: PosConnectionStatus.DISCONNECTED } }, include: { mappings: { orderBy: { providerLocationName: 'asc' } }, dailySales: { where: { conflictStatus: PosRevenueConflictStatus.PENDING }, select: { id: true, businessDate: true, netSales: true, restaurantLocationId: true, conflictStatus: true }, orderBy: { businessDate: 'desc' }, take: 25 } }, orderBy: { createdAt: 'desc' } });
    return rows.map((row) => this.safe(row));
  }
  private async token(connection: any) {
    if (connection.tokenExpiresAt && connection.tokenExpiresAt.getTime() < Date.now() + 5 * 60 * 1000) {
      if (!connection.encryptedRefreshToken) throw new UnauthorizedException('Square authorization must be renewed');
      const refreshed = await this.square.refresh(this.encryption.decryptPos(connection.encryptedRefreshToken));
      const saved = await this.prisma.posConnection.update({ where: { id: connection.id }, data: { encryptedAccessToken: this.encryption.encryptPos(refreshed.accessToken), encryptedRefreshToken: refreshed.refreshToken ? this.encryption.encryptPos(refreshed.refreshToken) : undefined, tokenExpiresAt: refreshed.expiresAt, status: PosConnectionStatus.CONNECTED, lastError: null } });
      return { ...connection, ...saved, accessToken: refreshed.accessToken };
    }
    return { ...connection, accessToken: this.encryption.decryptPos(connection.encryptedAccessToken) };
  }
  async providerLocations(userId: string, id: string) {
    const connection = await this.connection(userId, id); const authorized = await this.token(connection);
    return this.square.locations(authorized.accessToken);
  }
  async map(userId: string, id: string, data: PosMapLocationDto) {
    const connection = await this.connection(userId, id);
    const location = await this.prisma.restaurantLocation.findUnique({ where: { id: data.restaurantLocationId } });
    if (!location || location.organizationId !== connection.organizationId) throw new ForbiddenException('Restaurant location is not available');
    const available = await this.providerLocations(userId, id);
    const providerLocation = available.find((item) => item.id === data.providerLocationId);
    if (!providerLocation) throw new BadRequestException('Square location is not available');
    const restaurantMapping = await this.prisma.posLocationMapping.findFirst({ where: { posConnectionId: id, restaurantLocationId: location.id, providerLocationId: { not: data.providerLocationId } } });
    if (restaurantMapping) throw new ConflictException('This restaurant is already mapped to another Square location');
    const mapping = await this.prisma.posLocationMapping.upsert({ where: { posConnectionId_providerLocationId: { posConnectionId: id, providerLocationId: data.providerLocationId } }, create: { posConnectionId: id, organizationId: connection.organizationId, restaurantLocationId: location.id, providerLocationId: providerLocation.id, providerLocationName: providerLocation.name, providerTimezone: providerLocation.timezone, active: data.active ?? true }, update: { restaurantLocationId: location.id, providerLocationName: providerLocation.name, providerTimezone: providerLocation.timezone, active: data.active ?? true } });
    await this.audit.log({ userId, organizationId: connection.organizationId, action: 'pos.location_mapped', entityType: 'PosLocationMapping', entityId: mapping.id, metadata: { providerLocationId: mapping.providerLocationId, restaurantLocationId: mapping.restaurantLocationId } });
    await this.sync(userId, id, true);
    return mapping;
  }
  async sync(userId: string, id: string, initial = false) {
    const connection = await this.connection(userId, id);
    if (connection.status === PosConnectionStatus.DISCONNECTED) throw new BadRequestException('Square is disconnected');
    await this.prisma.posConnection.update({ where: { id }, data: { status: PosConnectionStatus.SYNCING, lastError: null } });
    await this.audit.log({ userId, organizationId: connection.organizationId, action: 'pos.sync_started', entityType: 'PosConnection', entityId: id });
    try {
      const authorized = await this.token(connection); const end = new Date();
      const start = initial || !connection.lastSyncAt ? new Date(end.getTime() - 90 * 86400000) : new Date(connection.lastSyncAt.getTime() - 7 * 86400000);
      let imported = 0; let conflicts = 0;
      for (const mapping of connection.mappings.filter((item: any) => item.active)) {
        const orders = await this.square.orders(authorized.accessToken, mapping.providerLocationId, start, end);
        const aggregates = aggregateSquareOrders(orders, mapping.providerTimezone);
        const existing = await this.prisma.posDailySales.findMany({ where: { posConnectionId: id, providerLocationId: mapping.providerLocationId, businessDate: { gte: new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate())), lte: new Date(Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate())) } } });
        const byDate = new Map(aggregates.map((item) => [item.businessDate, item]));
        for (const row of existing) { const key = row.businessDate.toISOString().slice(0, 10); if (!byDate.has(key)) byDate.set(key, { businessDate: key, grossSales: 0, discounts: 0, refunds: 0, taxes: 0, tips: 0, netSales: 0, transactionCount: 0 }); }
        for (const day of byDate.values()) {
          const date = new Date(`${day.businessDate}T00:00:00.000Z`); const next = new Date(date.getTime() + 86400000);
          const manual = await this.prisma.revenueEntry.findFirst({ where: { organizationId: connection.organizationId, restaurantLocationId: mapping.restaurantLocationId, source: RevenueSource.MANUAL, date: { gte: date, lt: next } } });
          const prior = existing.find((item) => item.businessDate.getTime() === date.getTime());
          const conflictStatus = manual ? prior?.conflictStatus === PosRevenueConflictStatus.USE_MANUAL && prior.netSales.equals(dollars(day.netSales)) ? PosRevenueConflictStatus.USE_MANUAL : PosRevenueConflictStatus.PENDING : PosRevenueConflictStatus.NONE;
          const sales = await this.prisma.posDailySales.upsert({ where: { posConnectionId_providerLocationId_businessDate: { posConnectionId: id, providerLocationId: mapping.providerLocationId, businessDate: date } }, create: { organizationId: connection.organizationId, restaurantLocationId: mapping.restaurantLocationId, posConnectionId: id, posLocationMappingId: mapping.id, providerLocationId: mapping.providerLocationId, businessDate: date, grossSales: dollars(day.grossSales), discounts: dollars(day.discounts), refunds: dollars(day.refunds), taxes: dollars(day.taxes), tips: dollars(day.tips), netSales: dollars(day.netSales), transactionCount: day.transactionCount, providerUpdatedAt: day.providerUpdatedAt, conflictStatus }, update: { grossSales: dollars(day.grossSales), discounts: dollars(day.discounts), refunds: dollars(day.refunds), taxes: dollars(day.taxes), tips: dollars(day.tips), netSales: dollars(day.netSales), transactionCount: day.transactionCount, providerUpdatedAt: day.providerUpdatedAt, conflictStatus } });
          if (manual) { if (conflictStatus === PosRevenueConflictStatus.PENDING) conflicts++; if (prior?.revenueEntryId) { await this.prisma.revenueEntry.delete({ where: { id: prior.revenueEntryId } }); await this.prisma.posDailySales.update({ where: { id: sales.id }, data: { revenueEntryId: null } }); } continue; }
          if (sales.revenueEntryId) await this.prisma.revenueEntry.update({ where: { id: sales.revenueEntryId }, data: { amount: dollars(day.netSales), notes: 'Imported from Square' } });
          else { const revenue = await this.prisma.revenueEntry.create({ data: { organizationId: connection.organizationId, restaurantLocationId: mapping.restaurantLocationId, date, amount: dollars(day.netSales), source: RevenueSource.POS_IMPORT, notes: 'Imported from Square', createdByUserId: connection.createdByUserId } }); await this.prisma.posDailySales.update({ where: { id: sales.id }, data: { revenueEntryId: revenue.id } }); }
          imported++;
        }
      }
      const saved = await this.prisma.posConnection.update({ where: { id }, data: { status: PosConnectionStatus.CONNECTED, lastSyncAt: end, lastError: null } });
      await this.audit.log({ userId, organizationId: connection.organizationId, action: 'pos.sync_completed', entityType: 'PosConnection', entityId: id, metadata: { imported, conflicts, overlapDays: 7 } });
      return { connection: this.safe(saved), imported, conflicts };
    } catch (error) {
      const reauth = error instanceof UnauthorizedException;
      await this.prisma.posConnection.update({ where: { id }, data: { status: reauth ? PosConnectionStatus.REAUTH_REQUIRED : PosConnectionStatus.ERROR, lastError: reauth ? 'Reconnect Square to continue syncing.' : 'Unable to sync Square. Try again.' } });
      await this.audit.log({ userId, organizationId: connection.organizationId, action: 'pos.sync_failed', entityType: 'PosConnection', entityId: id, metadata: { reauthRequired: reauth } });
      await this.notifications?.notifyOperational({ organizationId: connection.organizationId, type: reauth ? 'POS_REAUTH_REQUIRED' : 'POS_SYNC_FAILED', severity: 'HIGH', title: reauth ? 'Reconnect Square' : 'Square sync failed', body: reauth ? 'Reconnect Square to continue syncing sales.' : 'We could not sync Square sales. Try again shortly.', deepLinkType: 'OPEN_POS_INTEGRATIONS', deepLinkId: id, dedupeKey: reauth ? `pos-reauth:${id}` : `pos-sync-failed:${id}:${error instanceof Error ? error.name : 'unknown'}` });
      throw new ServiceUnavailableException(reauth ? 'Square authorization must be renewed' : 'Unable to sync Square');
    }
  }
  async resolveConflict(userId: string, salesId: string, resolution: 'MANUAL' | 'SQUARE') {
    const sales = await this.prisma.posDailySales.findUnique({ where: { id: salesId }, include: { connection: true } });
    if (!sales) throw new NotFoundException('Revenue conflict not found'); await this.access.requireMember(userId, sales.organizationId);
    if (resolution === 'SQUARE') {
      const next = new Date(sales.businessDate.getTime() + 86400000);
      await this.prisma.revenueEntry.deleteMany({ where: { organizationId: sales.organizationId, restaurantLocationId: sales.restaurantLocationId, source: RevenueSource.MANUAL, date: { gte: sales.businessDate, lt: next } } });
      const revenue = sales.revenueEntryId ? await this.prisma.revenueEntry.update({ where: { id: sales.revenueEntryId }, data: { amount: sales.netSales } }) : await this.prisma.revenueEntry.create({ data: { organizationId: sales.organizationId, restaurantLocationId: sales.restaurantLocationId, date: sales.businessDate, amount: sales.netSales, source: RevenueSource.POS_IMPORT, notes: 'Imported from Square', createdByUserId: sales.connection.createdByUserId } });
      await this.prisma.posDailySales.update({ where: { id: sales.id }, data: { conflictStatus: PosRevenueConflictStatus.USE_POS, revenueEntryId: revenue.id } });
    } else { if (sales.revenueEntryId) await this.prisma.revenueEntry.delete({ where: { id: sales.revenueEntryId } }); await this.prisma.posDailySales.update({ where: { id: sales.id }, data: { conflictStatus: PosRevenueConflictStatus.USE_MANUAL, revenueEntryId: null } }); }
    await this.audit.log({ userId, organizationId: sales.organizationId, action: 'pos.revenue_conflict_resolved', entityType: 'PosDailySales', entityId: sales.id, metadata: { resolution } });
    return { resolved: true, resolution };
  }
  async disconnect(userId: string, id: string) {
    const connection = await this.connection(userId, id); try { await this.square.revoke(this.encryption.decryptPos(connection.encryptedAccessToken)); } catch { /* local disconnect still prevents future use */ }
    await this.prisma.posConnection.update({ where: { id }, data: { status: PosConnectionStatus.DISCONNECTED, encryptedAccessToken: this.encryption.encryptPos('revoked'), encryptedRefreshToken: null } });
    await this.audit.log({ userId, organizationId: connection.organizationId, action: 'pos.square_disconnected', entityType: 'PosConnection', entityId: id });
  }
  async webhook(signature: string | undefined, rawBody: Buffer, body: any) {
    const key = process.env.SQUARE_WEBHOOK_SIGNATURE_KEY, url = process.env.SQUARE_WEBHOOK_NOTIFICATION_URL;
    if (!key || !url || !signature) throw new ForbiddenException('Invalid Square webhook signature');
    const digest = createHmac('sha256', key).update(url + rawBody.toString('utf8')).digest('base64');
    if (digest.length !== signature.length || !timingSafeEqual(Buffer.from(digest), Buffer.from(signature))) throw new ForbiddenException('Invalid Square webhook signature');
    const eventId = body?.event_id; if (!eventId) throw new BadRequestException('Square webhook event is invalid');
    try { await this.prisma.posWebhookEvent.create({ data: { providerEventId: eventId, eventType: body.type ?? 'unknown', merchantId: body.merchant_id } }); } catch (error) { if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') return { received: true, duplicate: true }; throw error; }
    const connection = body.merchant_id ? await this.prisma.posConnection.findUnique({ where: { provider_providerMerchantId: { provider: PosProvider.SQUARE, providerMerchantId: body.merchant_id } } }) : null;
    if (connection && connection.status !== PosConnectionStatus.DISCONNECTED) setImmediate(() => void this.sync(connection.createdByUserId, connection.id).catch(() => undefined));
    await this.prisma.posWebhookEvent.update({ where: { provider_providerEventId: { provider: PosProvider.SQUARE, providerEventId: eventId } }, data: { processedAt: new Date() } });
    return { received: true };
  }
}
