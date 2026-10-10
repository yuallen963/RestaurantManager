import { ConflictException, ForbiddenException, UnauthorizedException } from '@nestjs/common';
import * as argon2 from 'argon2';
import { AuthService } from '../src/auth/auth.service';

const password = 'long-enough-password';
const audit = { log: jest.fn().mockResolvedValue(undefined) };
const mail = () => ({ developmentMode: false, assertConfigured: jest.fn(), sendVerification: jest.fn(), sendPasswordReset: jest.fn() });

describe('auth service', () => {
  beforeEach(() => jest.clearAllMocks());

  it('registers a normalized account and stores a hash of the verification token', async () => {
    const prisma: any = { user: { findUnique: jest.fn().mockResolvedValue(null), create: jest.fn(({ data }) => Promise.resolve({ id: 'user-a', ...data })) }, emailVerificationToken: { create: jest.fn() } };
    const email = mail(); const service = new AuthService(prisma, {} as any, email as any, audit as any);
    await expect(service.register({ email: ' Owner@Example.COM ', password })).resolves.toEqual({ verificationRequired: true, email: 'owner@example.com' });
    expect(prisma.user.create).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ email: 'owner@example.com' }) }));
    expect(prisma.emailVerificationToken.create.mock.calls[0][0].data.tokenHash).not.toBe(email.sendVerification.mock.calls[0][1]);
  });

  it('rejects duplicate normalized registration', async () => {
    const service = new AuthService({ user: { findUnique: jest.fn().mockResolvedValue({ id: 'existing' }) } } as any, {} as any, mail() as any, audit as any);
    await expect(service.register({ email: 'OWNER@example.com', password })).rejects.toBeInstanceOf(ConflictException);
  });

  it('verifies a token exactly once', async () => {
    const prisma: any = { emailVerificationToken: { findUnique: jest.fn().mockResolvedValue({ id: 'token-a', userId: 'user-a' }), updateMany: jest.fn().mockResolvedValueOnce({ count: 1 }).mockResolvedValueOnce({ count: 0 }) }, user: { update: jest.fn() } };
    const service = new AuthService(prisma, {} as any, mail() as any, audit as any);
    await expect(service.verifyEmail('x'.repeat(32))).resolves.toEqual({ verified: true });
    await expect(service.verifyEmail('x'.repeat(32))).rejects.toBeInstanceOf(UnauthorizedException);
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

  it('atomically rotates refresh tokens and rejects replay', async () => {
    const raw = 'refresh-token';
    const stored = { id: 'session-a', userId: 'user-a', tokenHash: await argon2.hash(raw), expiresAt: new Date(Date.now() + 60_000), revokedAt: null };
    const prisma: any = { user: { findUnique: jest.fn().mockResolvedValue({ id: 'user-a', email: 'a@example.com', emailVerifiedAt: new Date() }) }, refreshToken: { findUnique: jest.fn().mockResolvedValue(stored), updateMany: jest.fn().mockResolvedValueOnce({ count: 1 }).mockResolvedValueOnce({ count: 0 }), create: jest.fn(), update: jest.fn() } };
    const jwt = { verifyAsync: jest.fn().mockResolvedValue({ sub: 'user-a', type: 'refresh', sid: 'session-a' }), signAsync: jest.fn().mockResolvedValueOnce('access').mockResolvedValueOnce('next-refresh') };
    const service = new AuthService(prisma, jwt as any, mail() as any, audit as any);
    await expect(service.refresh(raw)).resolves.toMatchObject({ refreshToken: 'next-refresh' });
    await expect(service.refresh(raw)).rejects.toThrow('Refresh token revoked');
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

  it('revokes every session for the current user', async () => {
    const service = new AuthService({ refreshToken: { updateMany: jest.fn().mockResolvedValue({ count: 3 }) } } as any, {} as any, mail() as any, audit as any);
    await expect(service.signOutAll('user-a')).resolves.toEqual({ revoked: 3 });
  });

  it('blocks demo deletion and unsafe ownership orphaning', async () => {
    const hash = await argon2.hash(password);
    const prisma: any = { user: { findUnique: jest.fn().mockResolvedValue({ id: 'demo', email: 'demo@profitlens.local', passwordHash: hash, memberships: [] }) } };
    const service = new AuthService(prisma, {} as any, mail() as any, audit as any);
    await expect(service.deleteAccount('demo', password)).rejects.toBeInstanceOf(ForbiddenException);
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
