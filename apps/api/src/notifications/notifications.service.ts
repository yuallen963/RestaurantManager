import { Injectable, NotFoundException } from '@nestjs/common';
import { NotificationSeverity, NotificationType, Prisma } from '@prisma/client';
import { AuditService } from '../audit.service';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PrismaService } from '../prisma.service';
import { FcmService } from './fcm.service';

export type CreateNotification = { organizationId: string; restaurantLocationId?: string; userId: string; type: NotificationType; severity?: NotificationSeverity; title: string; body: string; deepLinkType?: string; deepLinkId?: string; dedupeKey: string };
const quiet = (time: string, start?: string | null, end?: string | null) => { if (!start || !end) return false; if (start === end) return false; return start < end ? time >= start && time < end : time >= start || time < end; };
@Injectable()
export class NotificationsService {
  constructor(private readonly prisma: PrismaService, private readonly access: OrganizationAccessService, private readonly audit: AuditService, private readonly fcm?: FcmService) {}
  async create(data: CreateNotification) {
    try { const notification = await this.prisma.notification.create({ data: { ...data, deliveredAt: new Date() } }); await this.audit.log({ userId: data.userId, organizationId: data.organizationId, action: 'notification.created', entityType: 'Notification', entityId: notification.id, metadata: { type: data.type, severity: data.severity } }); void this.push(notification); return notification; }
    catch (error) { if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') return null; throw error; }
  }
  async notifyOrganization(data: Omit<CreateNotification, 'userId'>) {
    const members = await this.prisma.organizationMember.findMany({ where: { organizationId: data.organizationId, role: { in: ['OWNER', 'ADMIN'] } }, select: { userId: true } });
    return Promise.all(members.map((member) => this.create({ ...data, userId: member.userId, dedupeKey: `${data.dedupeKey}:${member.userId}` })));
  }
  async notifyOperational(data: Omit<CreateNotification, 'userId'>) { const members = await this.prisma.organizationMember.findMany({ where: { organizationId: data.organizationId, role: { in: ['OWNER', 'ADMIN'] } }, select: { userId: true } }); return Promise.all(members.map(async ({ userId }) => (await this.allowed(userId, data.organizationId, 'sync')) ? this.create({ ...data, userId, dedupeKey: `${data.dedupeKey}:${userId}` }) : null)); }
  async allowed(userId: string, organizationId: string, channel: 'price' | 'savings' | 'cost' | 'sync' | 'digest') {
    const preference = await this.preference(userId, organizationId);
    return channel === 'price' ? preference.priceAlertsEnabled : channel === 'savings' ? preference.savingsAlertsEnabled : channel === 'cost' ? preference.costAlertsEnabled : channel === 'sync' ? preference.syncAlertsEnabled : preference.weeklyDigestEnabled;
  }
  async list(userId: string, unreadOnly = false) { const items = await this.prisma.notification.findMany({ where: { userId, readAt: unreadOnly ? null : undefined }, orderBy: { createdAt: 'desc' }, take: 100 }); const unreadCount = await this.prisma.notification.count({ where: { userId, readAt: null } }); return { items, unreadCount }; }
  async markRead(userId: string, id: string) { const row = await this.prisma.notification.findFirst({ where: { id, userId } }); if (!row) throw new NotFoundException('Notification not found'); return this.prisma.notification.update({ where: { id }, data: { readAt: new Date() } }); }
  async markAllRead(userId: string) { await this.prisma.notification.updateMany({ where: { userId, readAt: null }, data: { readAt: new Date() } }); return { updated: true }; }
  async preference(userId: string, organizationId: string, restaurantLocationId?: string) { await this.access.requireMember(userId, organizationId); return this.prisma.notificationPreference.upsert({ where: { userId_organizationId: { userId, organizationId } }, create: { userId, organizationId, restaurantLocationId, timezone: 'America/Detroit' }, update: {} }); }
  async updatePreference(userId: string, dto: any) { await this.access.requireMember(userId, dto.organizationId); const { organizationId, restaurantLocationId, ...data } = dto; return this.prisma.notificationPreference.upsert({ where: { userId_organizationId: { userId, organizationId } }, create: { userId, organizationId, restaurantLocationId, timezone: data.timezone ?? 'America/Detroit', ...data }, update: data }); }
  async registerToken(userId: string, data: any) { return this.prisma.devicePushToken.upsert({ where: { token: data.token }, create: { userId, token: data.token, platform: data.platform }, update: { userId, platform: data.platform, active: true, lastSeenAt: new Date() } }); }
  async deactivateToken(userId: string, token: string) { await this.prisma.devicePushToken.updateMany({ where: { userId, token }, data: { active: false } }); }
  private async push(notification: any) { if (!this.fcm || notification.pushSentAt) return; const preference = await this.preference(notification.userId, notification.organizationId); if (!this.shouldPush(preference, notification.severity)) return; const claimed = await this.prisma.notification.updateMany({ where: { id: notification.id, pushSentAt: null }, data: { pushSentAt: new Date() } }); if (!claimed.count) return; const rows = await this.prisma.devicePushToken.findMany({ where: { userId: notification.userId, active: true }, select: { token: true } }); const result = await this.fcm.send(rows.map((row: any) => row.token), { title: notification.title, body: notification.body, data: { notificationId: notification.id, type: notification.type, ...(notification.deepLinkType ? { deepLinkType: notification.deepLinkType } : {}), ...(notification.deepLinkId ? { deepLinkId: notification.deepLinkId } : {}), ...(notification.restaurantLocationId ? { restaurantLocationId: notification.restaurantLocationId } : {}) } }); if (result.invalid.length) await this.prisma.devicePushToken.updateMany({ where: { token: { in: result.invalid } }, data: { active: false } }); }
  shouldPush(preference: any, severity?: NotificationSeverity, now = new Date()) { if (!preference?.pushEnabled) return false; if (severity === NotificationSeverity.CRITICAL || severity === NotificationSeverity.HIGH) return true; const parts = new Intl.DateTimeFormat('en-GB', { timeZone: preference.timezone || 'UTC', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(now); const value = `${parts.find((p) => p.type === 'hour')?.value}:${parts.find((p) => p.type === 'minute')?.value}`; return !quiet(value, preference.quietHoursStart, preference.quietHoursEnd); }
}
