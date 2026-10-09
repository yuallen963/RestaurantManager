import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { NotificationSeverity, NotificationType } from '@prisma/client';
import { DashboardService } from '../dashboard/dashboard.service';
import { NeedsAttentionService } from '../needs-attention/needs-attention.service';
import { PrismaService } from '../prisma.service';
import { SavingsIntelligenceService } from '../savings-intelligence/savings-intelligence.service';
import { NotificationsService } from './notifications.service';

const typeFor: Record<string, NotificationType> = { ITEM_PRICE_INCREASE: NotificationType.PRICE_INCREASE, REPEATED_ITEM_PRICE_INCREASE: NotificationType.PRICE_INCREASE, FOOD_COST_DETERIORATION: NotificationType.FOOD_COST_DETERIORATION, LABOR_COST_DETERIORATION: NotificationType.LABOR_COST_DETERIORATION, VENDOR_SPEND_INCREASE: NotificationType.VENDOR_SPEND_INCREASE, CATEGORY_SPEND_INCREASE: NotificationType.CATEGORY_SPEND_INCREASE };
const severity = (value: string) => value as NotificationSeverity;
const local = (date: Date, zone: string) => new Intl.DateTimeFormat('en-GB', { timeZone: zone, weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(date).reduce<Record<string,string>>((all, part) => ({ ...all, [part.type]: part.value }), {});
@Injectable()
export class NotificationEvaluator implements OnModuleInit, OnModuleDestroy {
  private timer?: NodeJS.Timeout;
  constructor(private readonly prisma: PrismaService, private readonly notifications: NotificationsService, private readonly needs: NeedsAttentionService, private readonly savings: SavingsIntelligenceService, private readonly dashboard: DashboardService) {}
  onModuleInit() { this.timer = setInterval(() => void this.run().catch(() => undefined), 60 * 60 * 1000); this.timer.unref(); }
  onModuleDestroy() { if (this.timer) clearInterval(this.timer); }
  async run(now = new Date()) { const locations = await this.prisma.restaurantLocation.findMany({ select: { id: true, organizationId: true, name: true } }); for (const location of locations) await this.evaluateLocation(location, now); }
  async evaluateLocation(location: { id: string; organizationId: string; name: string }, now = new Date()) {
    const owners = await this.prisma.organizationMember.findMany({ where: { organizationId: location.organizationId, role: { in: ['OWNER', 'ADMIN'] } }, select: { userId: true } });
    for (const owner of owners) {
      const attention = await this.needs.get(owner.userId, { restaurantLocationId: location.id });
      for (const item of attention.items) {
        const type = typeFor[item.type]; if (!type) continue;
        const channel = type === NotificationType.PRICE_INCREASE ? 'price' : 'cost';
        if (!await this.notifications.allowed(owner.userId, location.organizationId, channel)) continue;
        await this.notifications.create({ organizationId: location.organizationId, restaurantLocationId: location.id, userId: owner.userId, type, severity: severity(item.severity), title: item.title, body: item.message, deepLinkType: item.action.type, deepLinkId: item.action.targetId, dedupeKey: `attention:${location.id}:${item.id}:${item.occurredAt}` });
      }
      const opportunities = await this.savings.get(owner.userId, { restaurantLocationId: location.id, lookbackDays: 90 });
      for (const item of opportunities.items) {
        if (!await this.notifications.allowed(owner.userId, location.organizationId, 'savings')) continue;
        await this.notifications.create({ organizationId: location.organizationId, restaurantLocationId: location.id, userId: owner.userId, type: NotificationType.SAVINGS_OPPORTUNITY, severity: NotificationSeverity.MEDIUM, title: `${item.productName} has a lower-cost option`, body: `Potential savings: $${item.estimatedMonthlySavings.toFixed(0)}/month.`, deepLinkType: 'OPEN_SAVINGS_OPPORTUNITY', deepLinkId: item.productGroupId, dedupeKey: `savings:${location.id}:${item.productGroupId}:${item.latestHigherPriceDate}` });
      }
      await this.digest(owner.userId, location, attention, opportunities, now);
    }
  }
  private async digest(userId: string, location: { id: string; organizationId: string; name: string }, attention: any, opportunities: any, now: Date) {
    const preference = await this.notifications.preference(userId, location.organizationId, location.id); const clock = local(now, preference.timezone); if (clock.weekday !== 'Mon' || clock.hour !== '08') return; if (!await this.notifications.allowed(userId, location.organizationId, 'digest')) return;
    const end = new Date(now); const start = new Date(now.getTime() - 7 * 86400000); const dashboard = await this.dashboard.get(userId, { restaurantLocationId: location.id, startDate: start.toISOString(), endDate: end.toISOString() });
    const top = attention.items.slice(0, 3).map((item: any) => `• ${item.title}`).join('\n'); const savings = opportunities.summary.estimatedMonthlySavings;
    const body = `Revenue: $${dashboard.summary.revenue.toFixed(0)}\nExpenses: $${dashboard.summary.expenses.toFixed(0)}\nEstimated profit: $${dashboard.summary.estimatedProfit.toFixed(0)}\nProfit margin: ${dashboard.summary.profitMargin.toFixed(1)}%\nFood cost: ${dashboard.summary.foodCostPercentage.toFixed(1)}%\nLabor cost: ${dashboard.summary.laborCostPercentage.toFixed(1)}%\n${attention.items.length} items need attention${top ? `\n${top}` : ''}${savings ? `\nPotential savings: $${savings.toFixed(0)}/month` : ''}`;
    const week = start.toISOString().slice(0, 10); await this.notifications.create({ organizationId: location.organizationId, restaurantLocationId: location.id, userId, type: NotificationType.WEEKLY_DIGEST, title: `Weekly Summary — ${location.name}`, body, deepLinkType: 'OPEN_DASHBOARD', dedupeKey: `weekly-digest:${userId}:${location.id}:${week}` });
  }
}
