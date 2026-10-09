import { NotificationSeverity, NotificationType, Prisma } from '@prisma/client';
import { NotificationEvaluator } from '../src/notifications/notification-evaluator.service';
import { NotificationsService } from '../src/notifications/notifications.service';

describe('notification backend', () => {
  const preference = { pushEnabled: true, quietHoursStart: '22:00', quietHoursEnd: '07:00', timezone: 'America/Detroit', priceAlertsEnabled: true, savingsAlertsEnabled: true, costAlertsEnabled: true, syncAlertsEnabled: true, weeklyDigestEnabled: true };

  it('uses timezone-aware quiet hours and lets high severity operational alerts through', () => {
    const service = new NotificationsService({} as any, {} as any, {} as any);
    expect(service.shouldPush(preference, NotificationSeverity.MEDIUM, new Date('2026-10-13T04:00:00.000Z'))).toBe(false); // midnight Detroit
    expect(service.shouldPush(preference, NotificationSeverity.MEDIUM, new Date('2026-10-13T16:00:00.000Z'))).toBe(true); // noon Detroit
    expect(service.shouldPush(preference, NotificationSeverity.HIGH, new Date('2026-10-13T04:00:00.000Z'))).toBe(true);
  });

  it('suppresses an operational alert when sync alerts are disabled and persists it once when enabled', async () => {
    const prisma: any = { organizationMember: { findMany: jest.fn().mockResolvedValue([{ userId: 'owner-a' }]) }, notification: { create: jest.fn().mockResolvedValue({ id: 'notice-a' }) } };
    const service = new NotificationsService(prisma, { requireMember: jest.fn() } as any, { log: jest.fn() } as any);
    jest.spyOn(service, 'allowed').mockResolvedValueOnce(false);
    await service.notifyOperational({ organizationId: 'org-a', type: NotificationType.BANK_SYNC_FAILED, severity: NotificationSeverity.HIGH, title: 'Bank sync failed', body: 'Retry later', dedupeKey: 'bank-sync-failed:connection-a:Error' });
    expect(prisma.notification.create).not.toHaveBeenCalled();
    jest.spyOn(service, 'allowed').mockResolvedValueOnce(true);
    await service.notifyOperational({ organizationId: 'org-a', type: NotificationType.POS_REAUTH_REQUIRED, severity: NotificationSeverity.HIGH, title: 'Reconnect Square', body: 'Reconnect', dedupeKey: 'pos-reauth:connection-a' });
    expect(prisma.notification.create).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ userId: 'owner-a', dedupeKey: 'pos-reauth:connection-a:owner-a' }) }));
  });

  it('treats the unique dedupe key as idempotent', async () => {
    const duplicate = new Prisma.PrismaClientKnownRequestError('duplicate', { code: 'P2002', clientVersion: '6.0.0' });
    const service = new NotificationsService({ notification: { create: jest.fn().mockRejectedValue(duplicate) } } as any, {} as any, {} as any);
    await expect(service.create({ organizationId: 'org-a', userId: 'owner-a', type: NotificationType.INVOICE_EXTRACTION_FAILED, title: 'Failed', body: 'Failed', dedupeKey: 'invoice-extraction-failed:invoice-a:Error' })).resolves.toBeNull();
  });

  it('creates only enabled analytical notifications and an idempotent Monday digest', async () => {
    const prisma: any = { restaurantLocation: { findMany: jest.fn().mockResolvedValue([{ id: 'location-a', organizationId: 'org-a', name: 'Downtown Grill' }]) }, organizationMember: { findMany: jest.fn().mockResolvedValue([{ userId: 'owner-a' }]) } };
    const notifications: any = { allowed: jest.fn().mockResolvedValue(true), preference: jest.fn().mockResolvedValue(preference), create: jest.fn().mockResolvedValue({ id: 'notice' }) };
    const needs: any = { get: jest.fn().mockResolvedValue({ items: [{ id: 'price-chicken', type: 'ITEM_PRICE_INCREASE', severity: 'HIGH', title: 'Chicken cost increased', message: 'Up 20%', occurredAt: '2026-10-11T00:00:00.000Z', action: { type: 'OPEN_PRICE_HISTORY', targetId: 'chicken' } }] }) };
    const savings: any = { get: jest.fn().mockResolvedValue({ summary: { estimatedMonthlySavings: 120 }, items: [{ productGroupId: 'group-a', productName: 'Chicken', estimatedMonthlySavings: 120, latestHigherPriceDate: '2026-10-11T00:00:00.000Z' }] }) };
    const dashboard: any = { get: jest.fn().mockResolvedValue({ summary: { revenue: 10000, expenses: 7200, estimatedProfit: 2800, profitMargin: 28, foodCostPercentage: 31, laborCostPercentage: 25 } }) };
    const evaluator = new NotificationEvaluator(prisma, notifications, needs, savings, dashboard);
    await evaluator.run(new Date('2026-10-12T12:00:00.000Z')); // Monday 08:00 Detroit
    expect(notifications.create).toHaveBeenCalledWith(expect.objectContaining({ type: NotificationType.PRICE_INCREASE, restaurantLocationId: 'location-a', dedupeKey: 'attention:location-a:price-chicken:2026-10-11T00:00:00.000Z' }));
    expect(notifications.create).toHaveBeenCalledWith(expect.objectContaining({ type: NotificationType.SAVINGS_OPPORTUNITY, dedupeKey: 'savings:location-a:group-a:2026-10-11T00:00:00.000Z' }));
    expect(notifications.create).toHaveBeenCalledWith(expect.objectContaining({ type: NotificationType.WEEKLY_DIGEST, dedupeKey: expect.stringMatching(/^weekly-digest:owner-a:location-a:/), body: expect.stringContaining('Revenue: $10000') }));
    await evaluator.run(new Date('2026-10-12T12:30:00.000Z'));
    const digests = notifications.create.mock.calls.map(([value]: any[]) => value).filter((value: any) => value.type === NotificationType.WEEKLY_DIGEST);
    expect(digests).toHaveLength(2);
    expect(digests[0].dedupeKey).toBe(digests[1].dedupeKey);
  });

  it('keeps evaluator reads scoped to each organization location and respects preferences', async () => {
    const prisma: any = { restaurantLocation: { findMany: jest.fn().mockResolvedValue([{ id: 'location-a', organizationId: 'org-a', name: 'A' }, { id: 'location-b', organizationId: 'org-b', name: 'B' }]) }, organizationMember: { findMany: jest.fn().mockImplementation(({ where }: any) => Promise.resolve([{ userId: `${where.organizationId}-owner` }])) } };
    const notifications: any = { allowed: jest.fn().mockResolvedValue(false), preference: jest.fn().mockResolvedValue(preference), create: jest.fn() };
    const evaluator = new NotificationEvaluator(prisma, notifications, { get: jest.fn().mockResolvedValue({ items: [{ id: 'cost', type: 'FOOD_COST_DETERIORATION', severity: 'MEDIUM', title: 'Food', message: 'Food', occurredAt: 'x', action: { type: 'OPEN_DASHBOARD_COST', targetId: 'food' } }] }) } as any, { get: jest.fn().mockResolvedValue({ summary: { estimatedMonthlySavings: 0 }, items: [] }) } as any, {} as any);
    await evaluator.run(new Date('2026-10-10T12:00:00.000Z'));
    expect(notifications.create).not.toHaveBeenCalled();
    expect(notifications.allowed).toHaveBeenCalledWith('org-a-owner', 'org-a', 'cost');
    expect(notifications.allowed).toHaveBeenCalledWith('org-b-owner', 'org-b', 'cost');
  });
});
