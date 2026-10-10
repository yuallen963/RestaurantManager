import { BadRequestException, ForbiddenException, Injectable } from '@nestjs/common';
import { OrganizationRole, Prisma } from '@prisma/client';
import { randomBytes } from 'crypto';
import { PrismaService } from '../prisma.service';
import { SetupRestaurantDto, UpdateOnboardingDto } from './dto';

const includeSetup = {
  organization: { select: { id: true, name: true } },
  restaurantLocation: { select: { id: true, name: true, timezone: true } },
} satisfies Prisma.OnboardingStateInclude;

@Injectable()
export class OnboardingService {
  constructor(private readonly prisma: PrismaService) {}

  private state(userId: string) {
    return this.prisma.onboardingState.upsert({
      where: { userId },
      create: { userId },
      update: {},
      include: includeSetup,
    });
  }

  get(userId: string) { return this.state(userId); }

  async update(userId: string, dto: UpdateOnboardingDto) {
    await this.state(userId);
    return this.prisma.onboardingState.update({
      where: { userId },
      data: {
        currentStep: dto.currentStep,
        ...(dto.selectedDataSources ? { selectedDataSources: dto.selectedDataSources } : {}),
      },
      include: includeSetup,
    });
  }

  async setup(userId: string, dto: SetupRestaurantDto) {
    return this.prisma.$transaction(async (tx) => {
      let state = await tx.onboardingState.upsert({ where: { userId }, create: { userId }, update: {} });
      if (state.onboardingCompletedAt) throw new BadRequestException('Onboarding is already complete');

      let organizationId = state.organizationId;
      if (organizationId) {
        const member = await tx.organizationMember.findUnique({ where: { userId_organizationId: { userId, organizationId } } });
        if (!member) throw new ForbiddenException('Onboarding organization is not accessible');
        await tx.organization.update({ where: { id: organizationId }, data: { name: dto.organizationName } });
      } else {
        const organization = await tx.organization.create({
          data: { name: dto.organizationName, memberships: { create: { userId, role: OrganizationRole.OWNER } } },
        });
        organizationId = organization.id;
      }

      let restaurantLocationId = state.restaurantLocationId;
      const locationData = {
        name: dto.locationName,
        addressLine1: dto.addressLine1,
        city: dto.city,
        state: dto.state,
        postalCode: dto.postalCode,
        timezone: dto.timezone,
      };
      if (restaurantLocationId) {
        const location = await tx.restaurantLocation.findFirst({ where: { id: restaurantLocationId, organizationId } });
        if (!location) throw new ForbiddenException('Onboarding location is not accessible');
        await tx.restaurantLocation.update({ where: { id: restaurantLocationId }, data: locationData });
      } else {
        const location = await tx.restaurantLocation.create({
          data: { organizationId, invoiceEmailToken: randomBytes(16).toString('hex'), ...locationData },
        });
        restaurantLocationId = location.id;
      }

      state = await tx.onboardingState.update({
        where: { userId },
        data: { organizationId, restaurantLocationId, currentStep: Math.max(state.currentStep, 3) },
      });
      return tx.onboardingState.findUniqueOrThrow({ where: { id: state.id }, include: includeSetup });
    });
  }

  async complete(userId: string) {
    const state = await this.state(userId);
    if (!state.organizationId || !state.restaurantLocationId) throw new BadRequestException('Restaurant setup is incomplete');
    const membership = await this.prisma.organizationMember.findUnique({
      where: { userId_organizationId: { userId, organizationId: state.organizationId } },
    });
    const location = await this.prisma.restaurantLocation.findFirst({
      where: { id: state.restaurantLocationId, organizationId: state.organizationId },
    });
    if (!membership || !location) throw new ForbiddenException('Onboarding setup is not accessible');
    return this.prisma.onboardingState.update({
      where: { userId },
      data: { currentStep: 6, onboardingCompletedAt: state.onboardingCompletedAt ?? new Date() },
      include: includeSetup,
    });
  }
}
