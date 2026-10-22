import { ConflictException, ForbiddenException, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { OrganizationRole } from '@prisma/client';
import * as argon2 from 'argon2';
import { AuthService } from '../src/auth/auth.service';

const password = 'long-enough-password';
const audit = { log: jest.fn().mockResolvedValue(undefined) };
const mail = () => ({ developmentMode: false, assertConfigured: jest.fn(), sendVerification: jest.fn(), sendPasswordReset: jest.fn() });

describe('auth service', () => {
  const originalSharedMode = process.env.SHARED_TEST_USER_MODE;
  const originalSharedEmail = process.env.SHARED_TEST_USER_EMAIL;
  const originalSharedClientToken = process.env.SHARED_TEST_CLIENT_TOKEN;
  const originalPrivateEmail = process.env.PRIVATE_BETA_USER_EMAIL;
  const originalPrivateHash = process.env.PRIVATE_BETA_ACCESS_CODE_HASH;
  beforeEach(() => jest.clearAllMocks());
  afterEach(() => {
    if (originalSharedMode === undefined) delete process.env.SHARED_TEST_USER_MODE;
    else process.env.SHARED_TEST_USER_MODE = originalSharedMode;
    if (originalSharedEmail === undefined) delete process.env.SHARED_TEST_USER_EMAIL;
    else process.env.SHARED_TEST_USER_EMAIL = originalSharedEmail;
    if (originalSharedClientToken === undefined) delete process.env.SHARED_TEST_CLIENT_TOKEN;
    else process.env.SHARED_TEST_CLIENT_TOKEN = originalSharedClientToken;
    if (originalPrivateEmail === undefined) delete process.env.PRIVATE_BETA_USER_EMAIL;
    else process.env.PRIVATE_BETA_USER_EMAIL = originalPrivateEmail;
    if (originalPrivateHash === undefined) delete process.env.PRIVATE_BETA_ACCESS_CODE_HASH;
    else process.env.PRIVATE_BETA_ACCESS_CODE_HASH = originalPrivateHash;
  });

  it('issues a session only for the configured shared test owner when enabled', async () => {
    process.env.SHARED_TEST_USER_MODE = 'true';
    process.env.SHARED_TEST_USER_EMAIL = 'test@profitlens.local';
    process.env.SHARED_TEST_CLIENT_TOKEN = 'internal-client-token';
    const prisma: any = {
      user: { findFirst: jest.fn().mockResolvedValue({ id: 'shared-user', email: 'test@profitlens.local' }) },
      refreshToken: { create: jest.fn() },
    };
    const jwt = { signAsync: jest.fn().mockResolvedValueOnce('access').mockResolvedValueOnce('refresh') };
    const service = new AuthService(prisma, jwt as any, mail() as any, audit as any);
    await expect(service.sharedTestSession('internal-client-token')).resolves.toMatchObject({ accessToken: 'access', refreshToken: 'refresh' });
    expect(prisma.user.findFirst).toHaveBeenCalledWith(expect.objectContaining({
      where: expect.objectContaining({ email: 'test@profitlens.local', memberships: { some: { role: OrganizationRole.OWNER } } }),
    }));
  });

  it('does not expose the shared test session endpoint when the flag is disabled or account is invalid', async () => {
    const prisma: any = { user: { findFirst: jest.fn() } };
    const service = new AuthService(prisma, {} as any, mail() as any, audit as any);
    delete process.env.SHARED_TEST_USER_MODE;
    await expect(service.sharedTestSession()).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.user.findFirst).not.toHaveBeenCalled();
    process.env.SHARED_TEST_USER_MODE = 'true';
    process.env.SHARED_TEST_CLIENT_TOKEN = 'internal-client-token';
    prisma.user.findFirst.mockResolvedValue(null);
    await expect(service.sharedTestSession('internal-client-token')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('fails closed before account lookup when the internal client token is absent or incorrect', async () => {
    process.env.SHARED_TEST_USER_MODE = 'true';
    process.env.SHARED_TEST_CLIENT_TOKEN = 'internal-client-token';
    const prisma: any = { user: { findFirst: jest.fn() } };
    const service = new AuthService(prisma, {} as any, mail() as any, audit as any);
    await expect(service.sharedTestSession()).rejects.toBeInstanceOf(NotFoundException);
    await expect(service.sharedTestSession('wrong-client-token')).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.user.findFirst).not.toHaveBeenCalled();
  });

  it.each(['false', 'TRUE', '1', 'yes', ' true '])('does not enable shared mode for invalid value %s', async (value) => {
    process.env.SHARED_TEST_USER_MODE = value;
    const prisma: any = { user: { findFirst: jest.fn() } };
    const service = new AuthService(prisma, {} as any, mail() as any, audit as any);
    await expect(service.sharedTestSession()).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.user.findFirst).not.toHaveBeenCalled();
  });

  it('fails closed when private account configuration is missing', async () => {
    delete process.env.PRIVATE_BETA_USER_EMAIL;
    delete process.env.PRIVATE_BETA_ACCESS_CODE_HASH;
    const service = new AuthService({} as any, {} as any, mail() as any, audit as any);
    await expect(service.privateSession('anything')).rejects.toThrow('not configured');
  });

  it('verifies the private code server-side and issues a normal user-bound session', async () => {
    process.env.PRIVATE_BETA_USER_EMAIL = 'private@profitlens.local';
    process.env.PRIVATE_BETA_ACCESS_CODE_HASH = await argon2.hash('configured-secret');
    const user = {
      id: 'private-user', email: 'private@profitlens.local', emailVerifiedAt: new Date(), disabledAt: null, deletedAt: null,
      memberships: [{ role: OrganizationRole.OWNER, organization: { locations: [{ id: 'private-location' }] } }],
    };
    const prisma: any = { user: { findFirst: jest.fn().mockResolvedValue(user) }, refreshToken: { create: jest.fn() } };
    const jwt = { signAsync: jest.fn().mockResolvedValueOnce('private-access').mockResolvedValueOnce('private-refresh') };
    const service = new AuthService(prisma, jwt as any, mail() as any, audit as any);
    await expect(service.privateSession('wrong')).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(service.privateSession('configured-secret')).resolves.toMatchObject({ accessToken: 'private-access', refreshToken: 'private-refresh', accountMode: 'private' });
    expect(prisma.user.findFirst).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ email: 'private@profitlens.local' }) }));
  });

  it('does not let private-account access bypass an enabled MFA challenge', async () => {
    process.env.PRIVATE_BETA_USER_EMAIL = 'private@profitlens.local';
    process.env.PRIVATE_BETA_ACCESS_CODE_HASH = await argon2.hash('configured-secret');
    const user = {
      id: 'private-user', email: 'private@profitlens.local', emailVerifiedAt: new Date(), disabledAt: null, deletedAt: null,
      mfaEnabled: true,
      memberships: [{ role: OrganizationRole.OWNER, organization: { locations: [{ id: 'private-location' }] } }],
    };
    const prisma: any = { user: { findFirst: jest.fn().mockResolvedValue(user) }, refreshToken: { create: jest.fn() } };
    const security = { beginLogin: jest.fn().mockResolvedValue({ challengeRequired: true, challengeId: 'challenge', method: 'AUTHENTICATOR' }) };
    const jwt = { signAsync: jest.fn() };
    const service = new AuthService(prisma, jwt as any, mail() as any, audit as any, security as any);

    await expect(service.privateSession('configured-secret')).resolves.toEqual(expect.objectContaining({ challengeRequired: true, accountMode: 'private' }));
    expect(jwt.signAsync).not.toHaveBeenCalled();
    expect(prisma.refreshToken.create).not.toHaveBeenCalled();
  });

  it('refuses a private identity without exactly one owned organization and location', async () => {
    process.env.PRIVATE_BETA_USER_EMAIL = 'private@profitlens.local';
    process.env.PRIVATE_BETA_ACCESS_CODE_HASH = await argon2.hash('configured-secret');
    const prisma: any = { user: { findFirst: jest.fn().mockResolvedValue({ id: 'private-user', memberships: [] }) } };
    const service = new AuthService(prisma, {} as any, mail() as any, audit as any);
    await expect(service.privateSession('configured-secret')).rejects.toThrow('not provisioned correctly');
  });

  it('registers a normalized account and stores a hash of the verification token', async () => {
    const invitation = { id: 'invite-a', email: 'owner@example.com', type: 'NEW_ORGANIZATION', organizationName: 'Restaurant', organizationId: null, role: 'OWNER', expiresAt: new Date(Date.now() + 60_000), revokedAt: null, redeemedAt: null };
    const tx: any = { betaInvitation: { findUnique: jest.fn().mockResolvedValue(invitation), updateMany: jest.fn().mockResolvedValue({ count: 1 }) }, user: { findUnique: jest.fn().mockResolvedValue(null), create: jest.fn(({ data }) => Promise.resolve({ id: 'user-a', ...data })) }, organization: { create: jest.fn().mockResolvedValue({ id: 'org-a' }) }, onboardingState: { create: jest.fn() }, emailVerificationToken: { create: jest.fn() } };
    const prisma: any = { $transaction: jest.fn((callback) => callback(tx)) };
    const email = mail(); const service = new AuthService(prisma, {} as any, email as any, audit as any);
    await expect(service.register({ email: ' Owner@Example.COM ', password, invitationToken: 'x'.repeat(32) })).resolves.toEqual({ verificationRequired: true, email: 'owner@example.com' });
    expect(tx.user.create).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ email: 'owner@example.com' }) }));
    expect(tx.emailVerificationToken.create.mock.calls[0][0].data.tokenHash).not.toBe(email.sendVerification.mock.calls[0][1]);
  });

  it('rejects duplicate normalized registration', async () => {
    const tx: any = { betaInvitation: { findUnique: jest.fn().mockResolvedValue({ id: 'invite-a', email: 'owner@example.com', expiresAt: new Date(Date.now() + 60_000), revokedAt: null, redeemedAt: null }) }, user: { findUnique: jest.fn().mockResolvedValue({ id: 'existing' }) } };
    const service = new AuthService({ $transaction: jest.fn((callback) => callback(tx)) } as any, {} as any, mail() as any, audit as any);
    await expect(service.register({ email: 'OWNER@example.com', password, invitationToken: 'x'.repeat(32) })).rejects.toBeInstanceOf(ConflictException);
  });

  it('verifies a token exactly once', async () => {
    const prisma: any = { emailVerificationToken: { findUnique: jest.fn().mockResolvedValue({ id: 'token-a', userId: 'user-a' }), updateMany: jest.fn().mockResolvedValueOnce({ count: 1 }).mockResolvedValueOnce({ count: 0 }) }, user: { update: jest.fn() } };
    const service = new AuthService(prisma, {} as any, mail() as any, audit as any);
    await expect(service.verifyEmail('x'.repeat(32))).resolves.toEqual({ verified: true });
    await expect(service.verifyEmail('x'.repeat(32))).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects invalid and expired verification tokens', async () => {
    const prisma: any = {
      emailVerificationToken: {
        findUnique: jest.fn().mockResolvedValueOnce(null).mockResolvedValueOnce({ id: 'expired', userId: 'user-a' }),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
    };
    const service = new AuthService(prisma, {} as any, mail() as any, audit as any);
    await expect(service.verifyEmail('x'.repeat(32))).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(service.verifyEmail('y'.repeat(32))).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('throttles resend and skips verified users', async () => {
    const email = mail();
    const prisma: any = { user: { findUnique: jest.fn().mockResolvedValue({ id: 'user-a', email: 'a@example.com', emailVerifiedAt: null }) }, emailVerificationToken: { findFirst: jest.fn().mockResolvedValue({ id: 'recent' }) } };
    const service = new AuthService(prisma, {} as any, email as any, audit as any);
    await service.resendVerification('A@example.com');
    prisma.user.findUnique.mockResolvedValue({ id: 'user-a', email: 'a@example.com', emailVerifiedAt: new Date() });
    await service.resendVerification('a@example.com');
    expect(email.sendVerification).not.toHaveBeenCalled();
  });

  it('blocks unverified users and permits verified users', async () => {
    const hash = await argon2.hash(password);
    const user: any = { id: 'user-a', email: 'a@example.com', passwordHash: hash, emailVerifiedAt: null, deletedAt: null, disabledAt: null };
    const prisma: any = { user: { findUnique: jest.fn().mockResolvedValue(user) }, refreshToken: { create: jest.fn() } };
    const jwt = { signAsync: jest.fn().mockResolvedValueOnce('access').mockResolvedValueOnce('refresh') };
    const service = new AuthService(prisma, jwt as any, mail() as any, audit as any);
    await expect(service.login('A@example.com', password)).rejects.toBeInstanceOf(ForbiddenException);
    user.emailVerifiedAt = new Date();
    await expect(service.login('a@example.com', password)).resolves.toMatchObject({ accessToken: 'access', refreshToken: 'refresh' });
  });

  it('rejects bad credentials and disabled users', async () => {
    const hash = await argon2.hash(password);
    const prisma: any = { user: { findUnique: jest.fn().mockResolvedValue({ passwordHash: hash, disabledAt: new Date() }) } };
    const service = new AuthService(prisma, {} as any, mail() as any, audit as any);
    await expect(service.login('a@example.com', password)).rejects.toBeInstanceOf(UnauthorizedException);
    prisma.user.findUnique.mockResolvedValue(null);
    await expect(service.login('missing@example.com', 'wrong')).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('sends a deduplicated suspicious-login signal without changing the neutral error', async () => {
    const hash = await argon2.hash(password);
    const user = { id: 'user-a', email: 'a@example.com', passwordHash: hash, disabledAt: null, deletedAt: null };
    const security = { notifySuspiciousLogin: jest.fn().mockRejectedValue(new Error('email unavailable')) };
    const service = new AuthService({ user: { findUnique: jest.fn().mockResolvedValue(user) } } as any, {} as any, mail() as any, audit as any, security as any);
    await expect(service.login(user.email, 'wrong-password')).rejects.toThrow('Invalid email or password');
    expect(security.notifySuspiciousLogin).toHaveBeenCalledWith(user);
  });

  it('atomically rotates refresh tokens and rejects replay', async () => {
    const raw = 'refresh-token';
    const stored = { id: 'session-a', userId: 'user-a', tokenHash: await argon2.hash(raw), expiresAt: new Date(Date.now() + 60_000), revokedAt: null };
    const prisma: any = { user: { findUnique: jest.fn().mockResolvedValue({ id: 'user-a', email: 'a@example.com', emailVerifiedAt: new Date() }) }, refreshToken: { findUnique: jest.fn().mockResolvedValue(stored), updateMany: jest.fn().mockResolvedValueOnce({ count: 1 }).mockResolvedValueOnce({ count: 0 }), create: jest.fn(), update: jest.fn() } };
    const jwt = { verifyAsync: jest.fn().mockResolvedValue({ sub: 'user-a', type: 'refresh', sid: 'session-a' }), signAsync: jest.fn().mockResolvedValueOnce('access').mockResolvedValueOnce('next-refresh') };
    const service = new AuthService(prisma, jwt as any, mail() as any, audit as any);
    await expect(service.refresh(raw)).resolves.toMatchObject({ refreshToken: 'next-refresh' });
    await expect(service.refresh(raw)).rejects.toThrow('Refresh token revoked');
  });

  it('revokes a replacement session when a rotated refresh token is replayed', async () => {
    const raw = 'replayed-refresh-token';
    const stored = { id: 'session-a', userId: 'user-a', tokenHash: await argon2.hash(raw), expiresAt: new Date(Date.now() + 60_000), revokedAt: new Date(), replacedByTokenId: 'session-b' };
    const replacement = { id: 'session-b', userId: 'user-a', revokedAt: null, replacedByTokenId: null };
    const prisma: any = {
      user: { findUnique: jest.fn().mockResolvedValue({ id: 'user-a', email: 'a@example.com', emailVerifiedAt: new Date() }) },
      refreshToken: {
        findUnique: jest.fn().mockResolvedValueOnce(stored).mockResolvedValueOnce(replacement),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
    const jwt = { verifyAsync: jest.fn().mockResolvedValue({ sub: 'user-a', type: 'refresh', sid: 'session-a' }) };
    const service = new AuthService(prisma, jwt as any, mail() as any, audit as any);
    await expect(service.refresh(raw)).rejects.toThrow('Refresh token revoked');
    expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith(expect.objectContaining({ where: { id: 'session-b', userId: 'user-a', revokedAt: null } }));
  });

  it('returns the same forgot-password response for known and unknown emails', async () => {
    const email = mail();
    const prisma: any = { user: { findUnique: jest.fn().mockResolvedValueOnce(null).mockResolvedValueOnce({ id: 'user-a', email: 'a@example.com' }) }, passwordResetToken: { findFirst: jest.fn().mockResolvedValue(null), create: jest.fn() } };
    const service = new AuthService(prisma, {} as any, email as any, audit as any);
    const unknown = await service.forgotPassword('missing@example.com'); const known = await service.forgotPassword('a@example.com');
    expect(known.message).toBe(unknown.message); expect(email.sendPasswordReset).toHaveBeenCalledTimes(1);
  });

  it('resets a password once and revokes all sessions', async () => {
    const prisma: any = { passwordResetToken: { findUnique: jest.fn().mockResolvedValue({ id: 'reset-a', userId: 'user-a' }), updateMany: jest.fn().mockResolvedValueOnce({ count: 1 }).mockResolvedValueOnce({ count: 0 }) }, user: { update: jest.fn() }, refreshToken: { updateMany: jest.fn() }, $transaction: jest.fn((queries) => Promise.all(queries)) };
    const service = new AuthService(prisma, {} as any, mail() as any, audit as any);
    await expect(service.resetPassword('r'.repeat(32), password)).resolves.toEqual({ reset: true });
    expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith(expect.objectContaining({ where: { userId: 'user-a', revokedAt: null } }));
    await expect(service.resetPassword('r'.repeat(32), password)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects invalid and expired password reset tokens without changing the user', async () => {
    const prisma: any = {
      passwordResetToken: {
        findUnique: jest.fn().mockResolvedValueOnce(null).mockResolvedValueOnce({ id: 'expired', userId: 'user-a' }),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      user: { update: jest.fn() },
    };
    const service = new AuthService(prisma, {} as any, mail() as any, audit as any);
    await expect(service.resetPassword('x'.repeat(32), password)).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(service.resetPassword('y'.repeat(32), password)).rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('revokes every session for the current user', async () => {
    const service = new AuthService({ refreshToken: { updateMany: jest.fn().mockResolvedValue({ count: 3 }) } } as any, {} as any, mail() as any, audit as any);
    await expect(service.signOutAll('user-a')).resolves.toEqual({ revoked: 3 });
  });

  it('blocks demo/shared deletion and unsafe ownership orphaning', async () => {
    const hash = await argon2.hash(password);
    const prisma: any = { user: { findUnique: jest.fn().mockResolvedValue({ id: 'demo', email: 'demo@profitlens.local', passwordHash: hash, memberships: [] }) } };
    const service = new AuthService(prisma, {} as any, mail() as any, audit as any);
    await expect(service.deleteAccount('demo', password)).rejects.toBeInstanceOf(ForbiddenException);
    prisma.user.findUnique.mockResolvedValue({ id: 'shared', email: 'test@profitlens.local', passwordHash: hash, memberships: [] });
    await expect(service.deleteAccount('shared', password)).rejects.toBeInstanceOf(ForbiddenException);
    prisma.user.findUnique.mockResolvedValue({ id: 'owner', email: 'owner@example.com', passwordHash: hash, memberships: [{ role: 'OWNER', organizationId: 'org-a' }] });
    prisma.organizationMember = { count: jest.fn().mockResolvedValueOnce(0).mockResolvedValueOnce(2) };
    await expect(service.deleteAccount('owner', password)).rejects.toBeInstanceOf(ConflictException);
  });

  it('soft-deletes a solo owner and archives the organization', async () => {
    const hash = await argon2.hash(password);
    const prisma: any = { user: { findUnique: jest.fn().mockResolvedValue({ id: 'owner', email: 'owner@example.com', passwordHash: hash, memberships: [{ role: 'OWNER', organizationId: 'org-a' }] }), update: jest.fn() }, organizationMember: { count: jest.fn().mockResolvedValue(0), deleteMany: jest.fn() }, organization: { updateMany: jest.fn() }, refreshToken: { updateMany: jest.fn() }, devicePushToken: { updateMany: jest.fn() }, $transaction: jest.fn((queries) => Promise.all(queries)) };
    const service = new AuthService(prisma, {} as any, mail() as any, audit as any);
    await expect(service.deleteAccount('owner', password)).resolves.toEqual({ deleted: true });
    expect(prisma.organization.updateMany).toHaveBeenCalledWith(expect.objectContaining({ where: { id: { in: ['org-a'] } } }));
  });
});
