import { ForbiddenException } from '@nestjs/common';
import { OnboardingService } from '../src/onboarding/onboarding.service';

describe('OnboardingService', () => {
  const pending = { id: 'state-1', userId: 'user-1', organizationId: null, restaurantLocationId: null, currentStep: 1, selectedDataSources: [], onboardingCompletedAt: null };

  it('creates and returns a current-user onboarding state', async () => {
    const prisma: any = { onboardingState: { upsert: jest.fn().mockResolvedValue(pending) } };
    await expect(new OnboardingService(prisma).get('user-1')).resolves.toEqual(pending);
    expect(prisma.onboardingState.upsert).toHaveBeenCalledWith(expect.objectContaining({ where: { userId: 'user-1' } }));
  });

  it('persists progress and selected sources for safe resume', async () => {
    const prisma: any = { onboardingState: { upsert: jest.fn().mockResolvedValue(pending), update: jest.fn().mockResolvedValue({ ...pending, currentStep: 4, selectedDataSources: ['INVOICES'] }) } };
    const result = await new OnboardingService(prisma).update('user-1', { currentStep: 4, selectedDataSources: ['INVOICES'] });
    expect(result.currentStep).toBe(4);
    expect(prisma.onboardingState.update).toHaveBeenCalledWith(expect.objectContaining({ where: { userId: 'user-1' }, data: { currentStep: 4, selectedDataSources: ['INVOICES'] } }));
  });

  it('creates organization and location once, then records both atomically', async () => {
    const tx: any = {
      onboardingState: { upsert: jest.fn().mockResolvedValue(pending), update: jest.fn().mockResolvedValue({ ...pending, organizationId: 'org-1', restaurantLocationId: 'loc-1', currentStep: 3 }), findUniqueOrThrow: jest.fn().mockResolvedValue({ organization: { id: 'org-1' }, restaurantLocation: { id: 'loc-1' } }) },
      organization: { create: jest.fn().mockResolvedValue({ id: 'org-1' }) },
      restaurantLocation: { create: jest.fn().mockResolvedValue({ id: 'loc-1' }) },
    };
    const prisma: any = { $transaction: (callback: (client: any) => unknown) => callback(tx) };
    await new OnboardingService(prisma).setup('user-1', { organizationName: 'A Group', locationName: 'A Grill', timezone: 'America/Detroit' });
    expect(tx.organization.create).toHaveBeenCalledTimes(1);
    expect(tx.restaurantLocation.create).toHaveBeenCalledTimes(1);
    expect(tx.onboardingState.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ organizationId: 'org-1', restaurantLocationId: 'loc-1' }) }));
  });

  it('reuses the recorded organization and location on resume without duplicates', async () => {
    const resumed = { ...pending, organizationId: 'org-1', restaurantLocationId: 'loc-1', currentStep: 3 };
    const tx: any = {
      onboardingState: { upsert: jest.fn().mockResolvedValue(resumed), update: jest.fn().mockResolvedValue(resumed), findUniqueOrThrow: jest.fn().mockResolvedValue(resumed) },
      organizationMember: { findUnique: jest.fn().mockResolvedValue({ id: 'member-1' }) },
      organization: { create: jest.fn(), update: jest.fn().mockResolvedValue({ id: 'org-1' }) },
      restaurantLocation: { create: jest.fn(), findFirst: jest.fn().mockResolvedValue({ id: 'loc-1' }), update: jest.fn().mockResolvedValue({ id: 'loc-1' }) },
    };
    await new OnboardingService({ $transaction: (callback: (client: any) => unknown) => callback(tx) } as any).setup('user-1', { organizationName: 'A Group', locationName: 'A Grill', timezone: 'America/Detroit' });
    expect(tx.organization.create).not.toHaveBeenCalled();
    expect(tx.restaurantLocation.create).not.toHaveBeenCalled();
  });

  it('completes only setup owned by the current user', async () => {
    const state = { ...pending, organizationId: 'org-1', restaurantLocationId: 'loc-1' };
    const prisma: any = {
      onboardingState: { upsert: jest.fn().mockResolvedValue(state), update: jest.fn().mockResolvedValue({ ...state, onboardingCompletedAt: new Date() }) },
      organizationMember: { findUnique: jest.fn().mockResolvedValue(null) },
      restaurantLocation: { findFirst: jest.fn().mockResolvedValue({ id: 'loc-1' }) },
    };
    await expect(new OnboardingService(prisma).complete('user-1')).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.onboardingState.update).not.toHaveBeenCalled();
  });

  it('preserves the completed timestamp for existing users', async () => {
    const completedAt = new Date('2026-01-01T00:00:00Z');
    const state = { ...pending, organizationId: 'org-1', restaurantLocationId: 'loc-1', onboardingCompletedAt: completedAt };
    const prisma: any = {
      onboardingState: { upsert: jest.fn().mockResolvedValue(state), update: jest.fn().mockResolvedValue(state) },
      organizationMember: { findUnique: jest.fn().mockResolvedValue({ id: 'member-1' }) },
      restaurantLocation: { findFirst: jest.fn().mockResolvedValue({ id: 'loc-1' }) },
    };
    await new OnboardingService(prisma).complete('user-1');
    expect(prisma.onboardingState.update).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ onboardingCompletedAt: completedAt }) }));
  });
});
