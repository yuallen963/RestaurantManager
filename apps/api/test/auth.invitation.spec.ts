import { ConflictException, ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { BetaInvitationType, OrganizationRole } from '@prisma/client';
import { AuthService } from '../src/auth/auth.service';

const rawToken = 'a'.repeat(43);
const password = 'a-secure-password';
const invitation = (overrides: Record<string, unknown> = {}) => ({
  id: 'invite-1',
  email: 'owner@example.com',
  type: BetaInvitationType.NEW_ORGANIZATION,
  organizationId: null,
  organizationName: 'Owner Restaurant',
  role: OrganizationRole.OWNER,
  expiresAt: new Date(Date.now() + 60_000),
  revokedAt: null,
  redeemedAt: null,
  ...overrides,
});

const setup = (record: any, claimCount = 1) => {
  const tx: any = {
    betaInvitation: {
      findUnique: jest.fn().mockResolvedValue(record),
      updateMany: jest.fn().mockResolvedValue({ count: claimCount }),
    },
    user: {
      findUnique: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockResolvedValue({ id: 'user-1', email: 'owner@example.com' }),
    },
    organization: {
      create: jest.fn().mockResolvedValue({ id: 'organization-1' }),
      findFirst: jest.fn(),
    },
    organizationMember: { create: jest.fn() },
    onboardingState: { create: jest.fn() },
    emailVerificationToken: { create: jest.fn() },
  };
  const prisma: any = {
    betaInvitation: { findUnique: jest.fn() },
    $transaction: jest.fn((callback) => callback(tx)),
  };
  const email: any = {
    developmentMode: false,
    assertConfigured: jest.fn(),
    sendVerification: jest.fn(),
  };
  const audit: any = { log: jest.fn() };
  return { service: new AuthService(prisma, {} as any, email, audit), prisma, tx, email };
};

describe('invitation-only registration', () => {
  it('previews an active invitation without exposing its token', async () => {
    const { service, prisma } = setup(invitation());
    prisma.betaInvitation.findUnique.mockResolvedValue(invitation({
      type: BetaInvitationType.JOIN_ORGANIZATION,
      organizationId: 'invited-organization',
      organizationName: null,
      role: OrganizationRole.ADMIN,
      organization: { name: 'Private Account', archivedAt: null },
    }));

    await expect(service.invitationPreview(rawToken)).resolves.toEqual({
      email: 'owner@example.com',
      type: BetaInvitationType.JOIN_ORGANIZATION,
      organizationName: 'Private Account',
      role: OrganizationRole.ADMIN,
      expiresAt: expect.any(Date),
    });
    expect(prisma.betaInvitation.findUnique).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { tokenHash: expect.stringMatching(/^[a-f0-9]{64}$/) },
      }),
    );
  });

  it('identifies a new-organization invitation for owner onboarding', async () => {
    const { service, prisma } = setup(invitation());
    prisma.betaInvitation.findUnique.mockResolvedValue(invitation({
      organization: null,
    }));

    await expect(service.invitationPreview(rawToken)).resolves.toEqual({
      email: 'owner@example.com',
      type: BetaInvitationType.NEW_ORGANIZATION,
      organizationName: 'Owner Restaurant',
      role: OrganizationRole.OWNER,
      expiresAt: expect.any(Date),
    });
  });

  it.each([
    null,
    invitation({ expiresAt: new Date(0) }),
    invitation({ revokedAt: new Date() }),
    invitation({ redeemedAt: new Date() }),
  ])('rejects an unavailable invitation preview', async (record) => {
    const { service, prisma } = setup(invitation());
    prisma.betaInvitation.findUnique.mockResolvedValue(record);
    await expect(service.invitationPreview(rawToken)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('rejects registration without a matching invitation', async () => {
    const { service } = setup(null);
    await expect(service.register({ email: 'owner@example.com', password, invitationToken: rawToken }))
      .rejects.toBeInstanceOf(UnauthorizedException);
  });

  it.each([
    [invitation({ expiresAt: new Date(0) }), UnauthorizedException],
    [invitation({ revokedAt: new Date() }), ForbiddenException],
    [invitation({ redeemedAt: new Date() }), ConflictException],
    [invitation({ email: 'another@example.com' }), ForbiddenException],
  ])('rejects an unusable invitation', async (record, errorType) => {
    const { service } = setup(record);
    await expect(service.register({ email: 'owner@example.com', password, invitationToken: rawToken }))
      .rejects.toBeInstanceOf(errorType as any);
  });

  it('atomically creates an isolated owner organization and claims the invitation', async () => {
    const { service, tx, email } = setup(invitation());
    await expect(service.register({ email: ' Owner@Example.com ', password, invitationToken: rawToken }))
      .resolves.toEqual({ verificationRequired: true, email: 'owner@example.com' });
    expect(tx.betaInvitation.updateMany).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ id: 'invite-1', redeemedAt: null, revokedAt: null }),
      data: { redeemedAt: expect.any(Date), redeemedByUserId: 'user-1' },
    }));
    expect(tx.organization.create).toHaveBeenCalledWith({ data: {
      name: 'Owner Restaurant',
      memberships: { create: { userId: 'user-1', role: OrganizationRole.OWNER } },
    } });
    expect(tx.onboardingState.create).toHaveBeenCalledWith({
      data: { userId: 'user-1', organizationId: 'organization-1' },
    });
    expect(tx.emailVerificationToken.create.mock.calls[0][0].data.tokenHash)
      .not.toBe(email.sendVerification.mock.calls[0][1]);
  });

  it('fails a concurrent redemption when the atomic claim loses the race', async () => {
    const { service } = setup(invitation(), 0);
    await expect(service.register({ email: 'owner@example.com', password, invitationToken: rawToken }))
      .rejects.toBeInstanceOf(ConflictException);
  });

  it('does not create another user or membership for an existing email', async () => {
    const { service, tx } = setup(invitation());
    tx.user.findUnique.mockResolvedValue({ id: 'existing-user' });
    await expect(
      service.register({
        email: 'owner@example.com',
        password,
        invitationToken: rawToken,
      }),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(tx.user.create).not.toHaveBeenCalled();
    expect(tx.organizationMember.create).not.toHaveBeenCalled();
  });

  it('joins only the organization stored on the invitation', async () => {
    const { service, tx } = setup(invitation({
      type: BetaInvitationType.JOIN_ORGANIZATION,
      organizationId: 'invited-organization',
      organizationName: null,
      role: OrganizationRole.VIEWER,
    }));
    tx.organization.findFirst.mockResolvedValue({
      id: 'invited-organization',
      locations: [{ id: 'invited-location' }],
    });
    await service.register({ email: 'owner@example.com', password, invitationToken: rawToken });
    expect(tx.organizationMember.create).toHaveBeenCalledWith({ data: {
      userId: 'user-1', organizationId: 'invited-organization', role: OrganizationRole.VIEWER,
    } });
  });
});
