import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { BetaInvitationType, OrganizationRole } from '@prisma/client';
import { InvitationService } from '../src/auth/invitation.service';

describe('beta invitation management', () => {
  const originalAdmins = process.env.BETA_INVITE_ADMIN_EMAILS;
  afterEach(() => {
    if (originalAdmins === undefined) delete process.env.BETA_INVITE_ADMIN_EMAILS;
    else process.env.BETA_INVITE_ADMIN_EMAILS = originalAdmins;
  });

  it('stores only a token hash and sends the raw token through email', async () => {
    process.env.BETA_INVITE_ADMIN_EMAILS = 'admin@example.com';
    const prisma: any = {
      user: { findFirst: jest.fn().mockResolvedValue({ id: 'admin', email: 'admin@example.com' }) },
      betaInvitation: { create: jest.fn(({ data }) => ({ id: 'invite', ...data })) },
    };
    const email: any = { assertConfigured: jest.fn(), sendBetaInvitation: jest.fn(), developmentMode: false };
    const service = new InvitationService(prisma, email, { log: jest.fn() } as any);
    await service.create('admin', {
      email: ' Owner@Example.com ', type: BetaInvitationType.NEW_ORGANIZATION,
      organizationName: 'New Restaurant',
    });
    const stored = prisma.betaInvitation.create.mock.calls[0][0].data.tokenHash;
    const delivered = email.sendBetaInvitation.mock.calls[0][1];
    expect(stored).toHaveLength(64);
    expect(stored).not.toBe(delivered);
    expect(delivered.length).toBeGreaterThanOrEqual(32);
  });

  it('allows only owners and admins to invite existing organization members', async () => {
    const prisma: any = {
      user: { findFirst: jest.fn().mockResolvedValue({ id: 'manager', email: 'manager@example.com' }) },
      organizationMember: { findUnique: jest.fn().mockResolvedValue({ role: OrganizationRole.MANAGER }) },
    };
    const service = new InvitationService(prisma, { assertConfigured: jest.fn() } as any, {} as any);
    await expect(service.create('manager', {
      email: 'viewer@example.com', type: BetaInvitationType.JOIN_ORGANIZATION,
      organizationId: 'organization-1', role: OrganizationRole.VIEWER,
    })).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('does not permit invitation-based ownership transfer', async () => {
    const prisma: any = {
      user: { findFirst: jest.fn().mockResolvedValue({ id: 'owner', email: 'owner@example.com' }) },
      organizationMember: { findUnique: jest.fn().mockResolvedValue({ role: OrganizationRole.OWNER }) },
      organization: { findFirst: jest.fn().mockResolvedValue({ id: 'organization-1' }) },
    };
    const service = new InvitationService(prisma, { assertConfigured: jest.fn() } as any, {} as any);
    await expect(service.create('owner', {
      email: 'other@example.com', type: BetaInvitationType.JOIN_ORGANIZATION,
      organizationId: 'organization-1', role: OrganizationRole.OWNER,
    })).rejects.toBeInstanceOf(BadRequestException);
  });
});
