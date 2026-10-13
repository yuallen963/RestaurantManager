import { AuthChallengeType } from '@prisma/client';
import * as argon2 from 'argon2';
import { AuthSecurityService, totpAt } from '../src/auth/auth-security.service';

const audit = { log: jest.fn().mockResolvedValue(undefined) };
const mail = { sendLoginCode: jest.fn().mockResolvedValue(undefined), sendSecurityNotice: jest.fn().mockResolvedValue(undefined) };

function setup() {
  const prisma: any = {
    user: { findUnique: jest.fn(), findUniqueOrThrow: jest.fn(), update: jest.fn().mockResolvedValue({}), updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
    authChallenge: { create: jest.fn(), findUnique: jest.fn(), update: jest.fn(), updateMany: jest.fn().mockResolvedValue({ count: 1 }), delete: jest.fn() },
    mfaRecoveryCode: { findMany: jest.fn().mockResolvedValue([]), count: jest.fn().mockResolvedValue(0), deleteMany: jest.fn(), createMany: jest.fn(), update: jest.fn(), updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
    recognizedDevice: { findUnique: jest.fn(), findMany: jest.fn(), findFirst: jest.fn(), upsert: jest.fn(), update: jest.fn() },
    refreshToken: { findMany: jest.fn().mockResolvedValue([]), updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
    securityEmailEvent: { create: jest.fn().mockResolvedValue({ id: 'email-event' }), update: jest.fn(), delete: jest.fn() },
  };
  prisma.$transaction = jest.fn((value: any) => typeof value === 'function' ? value(prisma) : Promise.all(value));
  return { prisma, service: new AuthSecurityService(prisma, mail as any, audit as any) };
}

describe('authentication security foundation', () => {
  const original = { mfa: process.env.AUTH_MFA_ENABLED, email: process.env.AUTH_EMAIL_LOGIN_VERIFICATION_ENABLED, devices: process.env.AUTH_DEVICE_RECOGNITION_ENABLED, key: process.env.AUTH_MFA_ENCRYPTION_KEY };
  beforeEach(() => { jest.clearAllMocks(); process.env.AUTH_CHALLENGE_SECRET = 'test-challenge-secret'; process.env.AUTH_MFA_ENCRYPTION_KEY = Buffer.alloc(32, 9).toString('base64'); });
  afterAll(() => { process.env.AUTH_MFA_ENABLED = original.mfa; process.env.AUTH_EMAIL_LOGIN_VERIFICATION_ENABLED = original.email; process.env.AUTH_DEVICE_RECOGNITION_ENABLED = original.devices; process.env.AUTH_MFA_ENCRYPTION_KEY = original.key; });

  it('keeps every new security capability disabled by default', () => {
    delete process.env.AUTH_MFA_ENABLED; delete process.env.AUTH_EMAIL_LOGIN_VERIFICATION_ENABLED; delete process.env.AUTH_DEVICE_RECOGNITION_ENABLED;
    expect(setup().service.flags()).toEqual(expect.objectContaining({ emailLoginVerificationAvailable: false, authenticatorMfaAvailable: false, deviceRecognitionAvailable: false, passkeysAvailable: false }));
  });

  it('continues enforcing an enrolled factor when rollout flags are disabled', async () => {
    delete process.env.AUTH_MFA_ENABLED;
    const { prisma, service } = setup();
    prisma.authChallenge.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'challenge', ...data }));
    await expect(service.beginLogin({ id: 'user', email: 'owner@example.com', mfaEnabled: true, emailLoginVerificationEnabled: false }, {})).resolves.toEqual(expect.objectContaining({ challengeRequired: true, method: 'AUTHENTICATOR' }));
  });

  it('creates a five-minute hashed email login challenge without issuing a session', async () => {
    process.env.AUTH_EMAIL_LOGIN_VERIFICATION_ENABLED = 'true';
    const { prisma, service } = setup();
    prisma.authChallenge.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'challenge', ...data }));
    await expect(service.beginLogin({ id: 'user', email: 'owner@example.com', emailLoginVerificationEnabled: true, mfaEnabled: false }, { deviceId: 'device', deviceName: 'iPhone' })).resolves.toEqual(expect.objectContaining({ challengeRequired: true, method: 'EMAIL' }));
    const saved = prisma.authChallenge.create.mock.calls[0][0].data;
    expect(prisma.authChallenge.updateMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ userId: 'user', usedAt: null }) }));
    expect(saved.codeHash).toHaveLength(64);
    expect(mail.sendLoginCode).toHaveBeenCalledWith('owner@example.com', expect.stringMatching(/^\d{6}$/));
    expect(saved.expiresAt.getTime()).toBeLessThanOrEqual(Date.now() + 300_000);
  });

  it('removes an unusable challenge when email delivery fails', async () => {
    process.env.AUTH_EMAIL_LOGIN_VERIFICATION_ENABLED = 'true';
    const { prisma, service } = setup();
    prisma.authChallenge.create.mockResolvedValue({ id: 'challenge' });
    mail.sendLoginCode.mockRejectedValueOnce(new Error('provider unavailable'));
    await expect(service.beginLogin({ id: 'user', email: 'owner@example.com', emailLoginVerificationEnabled: true }, {})).rejects.toThrow('provider unavailable');
    expect(prisma.authChallenge.delete).toHaveBeenCalledWith({ where: { id: 'challenge' } });
  });

  it('rejects expired, reused, and exhausted login challenges', async () => {
    const { prisma, service } = setup();
    for (const challenge of [
      { usedAt: new Date(), expiresAt: new Date(Date.now() + 1000), attempts: 0, maxAttempts: 5 },
      { usedAt: null, expiresAt: new Date(Date.now() - 1000), attempts: 0, maxAttempts: 5 },
      { usedAt: null, expiresAt: new Date(Date.now() + 1000), attempts: 5, maxAttempts: 5 },
    ]) {
      prisma.authChallenge.findUnique.mockResolvedValueOnce({ id: 'challenge', user: {}, ...challenge });
      await expect(service.completeLogin('challenge', '000000')).rejects.toThrow('invalid or expired');
    }
  });

  it('increments incorrect attempts and does not consume the challenge', async () => {
    const { prisma, service } = setup();
    prisma.authChallenge.findUnique.mockResolvedValue({ id: 'challenge', userId: 'user', type: AuthChallengeType.EMAIL_LOGIN, codeHash: '0'.repeat(64), user: {}, usedAt: null, expiresAt: new Date(Date.now() + 1000), attempts: 0, maxAttempts: 5 });
    await expect(service.completeLogin('challenge', '123456')).rejects.toThrow('Incorrect');
    expect(prisma.authChallenge.update).toHaveBeenCalledWith({ where: { id: 'challenge' }, data: { attempts: { increment: 1 } } });
    expect(prisma.authChallenge.updateMany).not.toHaveBeenCalled();
  });

  it('requires password and initial TOTP proof before enabling MFA', async () => {
    process.env.AUTH_MFA_ENABLED = 'true';
    const { prisma, service } = setup();
    const passwordHash = await argon2.hash('correct-password');
    prisma.user.findUnique.mockResolvedValue({ id: 'user', email: 'owner@example.com', passwordHash });
    const setupResult = await service.beginTotpEnrollment('user', 'correct-password');
    const pending = prisma.user.update.mock.calls[0][0].data;
    prisma.user.findUniqueOrThrow.mockResolvedValue({ id: 'user', email: 'owner@example.com', totpPendingSecretEncrypted: pending.totpPendingSecretEncrypted, totpPendingExpiresAt: pending.totpPendingExpiresAt });
    const code = totpAt(setupResult.secret, BigInt(Math.floor(Date.now() / 30_000)));
    await expect(service.confirmTotpEnrollment('user', code)).resolves.toEqual(expect.objectContaining({ enabled: true, recoveryCodes: expect.any(Array) }));
    expect(prisma.user.update).toHaveBeenLastCalledWith(expect.objectContaining({ data: expect.objectContaining({ mfaEnabled: true, totpPendingSecretEncrypted: null }) }));
    expect(prisma.mfaRecoveryCode.createMany.mock.calls[0][0].data).toHaveLength(10);
  });

  it('prevents reuse of an accepted authenticator time step', async () => {
    const { prisma, service } = setup();
    process.env.AUTH_MFA_ENABLED = 'true';
    const passwordHash = await argon2.hash('correct-password');
    prisma.user.findUnique.mockResolvedValue({ id: 'user', email: 'owner@example.com', passwordHash });
    const enrollment = await service.beginTotpEnrollment('user', 'correct-password');
    const encrypted = prisma.user.update.mock.calls[0][0].data.totpPendingSecretEncrypted;
    const step = BigInt(Math.floor(Date.now() / 30_000));
    prisma.authChallenge.findUnique.mockResolvedValue({ id: 'challenge', userId: 'user', type: AuthChallengeType.TOTP_LOGIN, user: { id: 'user', email: 'owner@example.com', mfaEnabled: true, totpSecretEncrypted: encrypted }, usedAt: null, expiresAt: new Date(Date.now() + 1000), attempts: 0, maxAttempts: 5 });
    prisma.user.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.completeLogin('challenge', totpAt(enrollment.secret, step))).rejects.toThrow('already used');
  });

  it('atomically prevents recovery-code reuse', async () => {
    const { prisma, service } = setup();
    const recovery = 'ABCDEF-123456';
    prisma.authChallenge.findUnique.mockResolvedValue({ id: 'challenge', userId: 'user', type: AuthChallengeType.TOTP_LOGIN, user: { id: 'user', email: 'owner@example.com', mfaEnabled: true, totpSecretEncrypted: null }, usedAt: null, expiresAt: new Date(Date.now() + 1000), attempts: 0, maxAttempts: 5 });
    // A recovery code cannot be considered until an authenticator secret exists.
    await expect(service.completeLogin('challenge', recovery)).rejects.toThrow('unavailable');

    const passwordHash = await argon2.hash('password');
    prisma.user.findUnique.mockResolvedValue({ id: 'user', email: 'owner@example.com', passwordHash });
    const enrollment = await service.beginTotpEnrollment('user', 'password');
    const latestUpdate = prisma.user.update.mock.calls[prisma.user.update.mock.calls.length - 1];
    const encrypted = latestUpdate[0].data.totpPendingSecretEncrypted;
    prisma.authChallenge.findUnique.mockResolvedValue({ id: 'challenge', userId: 'user', type: AuthChallengeType.TOTP_LOGIN, user: { id: 'user', email: 'owner@example.com', mfaEnabled: true, totpSecretEncrypted: encrypted }, usedAt: null, expiresAt: new Date(Date.now() + 1000), attempts: 0, maxAttempts: 5 });
    prisma.mfaRecoveryCode.findMany.mockResolvedValue([{ id: 'recovery', userId: 'user', codeHash: await argon2.hash(recovery), usedAt: null }]);
    prisma.mfaRecoveryCode.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.completeLogin('challenge', recovery)).rejects.toThrow('already used');
    expect(enrollment.secret).toBeTruthy();
  });

  it('keeps password reset independent from MFA settings', async () => {
    const { prisma, service } = setup();
    prisma.user.findUniqueOrThrow.mockResolvedValue({ email: 'owner@example.com', emailVerifiedAt: new Date(), emailLoginVerificationEnabled: false, mfaEnabled: true });
    await expect(service.status('user')).resolves.toEqual(expect.objectContaining({ mfaEnabled: true }));
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('scopes session revocation to the current user', async () => {
    const { prisma, service } = setup();
    prisma.refreshToken.updateMany.mockResolvedValueOnce({ count: 0 }).mockResolvedValueOnce({ count: 1 });
    await expect(service.revokeSession('user-a', 'other-session')).rejects.toThrow('Session not found');
    await expect(service.revokeSession('user-a', 'own-session')).resolves.toEqual({ revoked: true });
    expect(prisma.refreshToken.updateMany).toHaveBeenLastCalledWith({ where: { id: 'own-session', userId: 'user-a', revokedAt: null }, data: { revokedAt: expect.any(Date) } });
  });

  it('deduplicates new-device security email and stores only a device hash', async () => {
    process.env.AUTH_DEVICE_RECOGNITION_ENABLED = 'true';
    const { prisma, service } = setup();
    prisma.recognizedDevice.findUnique.mockResolvedValue(null);
    await service.recognizeDevice({ id: 'user', email: 'owner@example.com' }, { deviceId: 'raw-device-secret', deviceName: 'Owner iPhone' });
    const create = prisma.recognizedDevice.upsert.mock.calls[0][0].create;
    expect(create.deviceHash).not.toContain('raw-device-secret');
    expect(create.deviceHash).toHaveLength(64);
    expect(mail.sendSecurityNotice).toHaveBeenCalledTimes(1);
  });
});
