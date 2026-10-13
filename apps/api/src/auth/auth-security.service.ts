import { BadRequestException, ForbiddenException, Injectable, NotFoundException, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { AuthChallengeType, Prisma, SecurityEmailType } from '@prisma/client';
import * as argon2 from 'argon2';
import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import { AuditService } from '../audit.service';
import { PrismaService } from '../prisma.service';
import { AuthEmailService } from './auth-email.service';

type DeviceContext = { deviceId?: string; deviceName?: string };
const feature = (name: string) => process.env[name] === 'true';
const base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export const encodeBase32 = (bytes: Buffer) => {
  let bits = 0; let value = 0; let output = '';
  for (const byte of bytes) {
    value = (value << 8) | byte; bits += 8;
    while (bits >= 5) { output += base32Alphabet[(value >>> (bits - 5)) & 31]; bits -= 5; }
  }
  if (bits) output += base32Alphabet[(value << (5 - bits)) & 31];
  return output;
};

const decodeBase32 = (input: string) => {
  let bits = 0; let value = 0; const bytes: number[] = [];
  for (const character of input.replace(/=+$/g, '').toUpperCase()) {
    const index = base32Alphabet.indexOf(character);
    if (index < 0) throw new Error('Invalid base32');
    value = (value << 5) | index; bits += 5;
    if (bits >= 8) { bytes.push((value >>> (bits - 8)) & 255); bits -= 8; }
  }
  return Buffer.from(bytes);
};

export const totpAt = (secret: string, step: bigint) => {
  const counter = Buffer.alloc(8); counter.writeBigUInt64BE(step);
  const digest = createHmac('sha1', decodeBase32(secret)).update(counter).digest();
  const offset = digest[digest.length - 1] & 15;
  const number = (digest.readUInt32BE(offset) & 0x7fffffff) % 1_000_000;
  return number.toString().padStart(6, '0');
};

@Injectable()
export class AuthSecurityService {
  constructor(private readonly prisma: PrismaService, private readonly email: AuthEmailService, private readonly audit: AuditService) {}

  flags() {
    return {
      emailLoginVerificationAvailable: feature('AUTH_EMAIL_LOGIN_VERIFICATION_ENABLED'),
      authenticatorMfaAvailable: feature('AUTH_MFA_ENABLED'),
      deviceRecognitionAvailable: feature('AUTH_DEVICE_RECOGNITION_ENABLED'),
      passkeysAvailable: false,
    };
  }

  private pepper() { return process.env.AUTH_CHALLENGE_SECRET ?? process.env.JWT_ACCESS_SECRET ?? 'development-only-auth-challenge'; }
  private hash(value: string) { return createHash('sha256').update(`${this.pepper()}:${value}`).digest('hex'); }
  private deviceHash(deviceId?: string) { return deviceId ? this.hash(`device:${deviceId}`) : null; }
  private cleanLabel(label?: string) { return label?.trim().slice(0, 80) || null; }

  private encryptionKey() {
    const raw = process.env.AUTH_MFA_ENCRYPTION_KEY;
    if (!raw) {
      if (process.env.NODE_ENV === 'production') throw new ServiceUnavailableException('Authenticator MFA encryption is not configured');
      return createHash('sha256').update('fundwell-local-mfa-development-key').digest();
    }
    const key = Buffer.from(raw, 'base64');
    if (key.length !== 32) throw new ServiceUnavailableException('Authenticator MFA encryption is not configured');
    return key;
  }

  private encrypt(value: string) {
    const iv = randomBytes(12); const cipher = createCipheriv('aes-256-gcm', this.encryptionKey(), iv);
    const encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    return [iv, cipher.getAuthTag(), encrypted].map((value) => value.toString('base64url')).join('.');
  }

  private decrypt(value: string) {
    const [iv, tag, encrypted] = value.split('.').map((part) => Buffer.from(part, 'base64url'));
    const decipher = createDecipheriv('aes-256-gcm', this.encryptionKey(), iv); decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString('utf8');
  }

  async beginLogin(user: any, device: DeviceContext) {
    let type: AuthChallengeType | null = null;
    // Rollout flags control enrollment, never enforcement for an account that
    // has already opted in. Disabling a rollout flag must not become a bypass.
    if (user.mfaEnabled) type = AuthChallengeType.TOTP_LOGIN;
    else if (user.emailLoginVerificationEnabled) type = AuthChallengeType.EMAIL_LOGIN;
    if (!type) return null;
    await this.prisma.authChallenge.updateMany({
      where: { userId: user.id, usedAt: null, expiresAt: { gt: new Date() } },
      data: { usedAt: new Date() },
    });
    const code = type === AuthChallengeType.EMAIL_LOGIN ? randomInt(0, 1_000_000).toString().padStart(6, '0') : null;
    const challenge = await this.prisma.authChallenge.create({ data: {
      userId: user.id, type, codeHash: code ? this.hash(code) : null,
      expiresAt: new Date(Date.now() + 5 * 60_000), lastSentAt: code ? new Date() : null,
      deviceHash: this.deviceHash(device.deviceId), deviceLabel: this.cleanLabel(device.deviceName),
    } });
    if (code) {
      try { await this.email.sendLoginCode(user.email, code); }
      catch (error) { await this.prisma.authChallenge.delete({ where: { id: challenge.id } }); throw error; }
    }
    return { challengeRequired: true, challengeId: challenge.id, method: type === AuthChallengeType.TOTP_LOGIN ? 'AUTHENTICATOR' : 'EMAIL', expiresInSeconds: 300 };
  }

  async resendEmailChallenge(id: string) {
    const challenge = await this.prisma.authChallenge.findUnique({ where: { id }, include: { user: true } });
    if (!challenge || challenge.type !== AuthChallengeType.EMAIL_LOGIN || challenge.usedAt || challenge.expiresAt <= new Date()) throw new UnauthorizedException('Login challenge is invalid or expired');
    if (challenge.lastSentAt && challenge.lastSentAt > new Date(Date.now() - 60_000)) throw new BadRequestException('Wait before requesting another code');
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    await this.email.sendLoginCode(challenge.user.email, code);
    await this.prisma.authChallenge.update({ where: { id }, data: { codeHash: this.hash(code), lastSentAt: new Date(), attempts: 0 } });
    return { sent: true };
  }

  async completeLogin(id: string, code: string) {
    const challenge = await this.prisma.authChallenge.findUnique({ where: { id }, include: { user: true } });
    if (!challenge || challenge.usedAt || challenge.expiresAt <= new Date() || challenge.attempts >= challenge.maxAttempts) throw new UnauthorizedException('Login challenge is invalid or expired');
    await this.prisma.authChallenge.update({ where: { id }, data: { attempts: { increment: 1 } } });
    let acceptedStep: bigint | null = null;
    let recoveryCodeId: string | null = null;
    if (challenge.type === AuthChallengeType.EMAIL_LOGIN) {
      const expected = Buffer.from(challenge.codeHash ?? '', 'hex'); const actual = Buffer.from(this.hash(code), 'hex');
      if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) throw new UnauthorizedException('Incorrect verification code');
    } else {
      const secret = challenge.user.totpSecretEncrypted ? this.decrypt(challenge.user.totpSecretEncrypted) : null;
      if (!secret || !challenge.user.mfaEnabled) throw new UnauthorizedException('Authenticator MFA is unavailable');
      const current = BigInt(Math.floor(Date.now() / 30_000));
      for (const offset of [-1n, 0n, 1n]) if (totpAt(secret, current + offset) === code) acceptedStep = current + offset;
      if (acceptedStep == null) recoveryCodeId = await this.findRecoveryCode(challenge.userId, code);
      if (acceptedStep == null && recoveryCodeId == null) throw new UnauthorizedException('Incorrect verification code');
    }
    await this.prisma.$transaction(async (tx) => {
      const claimed = await tx.authChallenge.updateMany({ where: { id, usedAt: null, expiresAt: { gt: new Date() }, attempts: { lte: challenge.maxAttempts } }, data: { usedAt: new Date() } });
      if (claimed.count !== 1) throw new UnauthorizedException('Login challenge is invalid or expired');
      if (acceptedStep != null) {
        const replaySafe = await tx.user.updateMany({ where: { id: challenge.userId, OR: [{ totpLastUsedStep: null }, { totpLastUsedStep: { lt: acceptedStep } }] }, data: { totpLastUsedStep: acceptedStep } });
        if (replaySafe.count !== 1) throw new UnauthorizedException('Authenticator code was already used');
      }
      if (recoveryCodeId) {
        const consumed = await tx.mfaRecoveryCode.updateMany({ where: { id: recoveryCodeId, userId: challenge.userId, usedAt: null }, data: { usedAt: new Date() } });
        if (consumed.count !== 1) throw new UnauthorizedException('Recovery code was already used');
      }
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    if (recoveryCodeId) await this.securityEmail(challenge.user, SecurityEmailType.RECOVERY_CODE_USED, `recovery-used:${recoveryCodeId}`, 'A recovery code was used', 'A one-time MFA recovery code was used to sign in.');
    return { user: challenge.user, deviceIdHash: challenge.deviceHash, deviceLabel: challenge.deviceLabel };
  }

  private async findRecoveryCode(userId: string, code: string) {
    const rows = await this.prisma.mfaRecoveryCode.findMany({ where: { userId, usedAt: null } });
    for (const row of rows) if (await argon2.verify(row.codeHash, code.toUpperCase())) return row.id;
    return null;
  }

  async status(userId: string) {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { email: true, emailVerifiedAt: true, emailLoginVerificationEnabled: true, mfaEnabled: true } });
    return { ...user, ...this.flags(), recoveryCodesRemaining: await this.prisma.mfaRecoveryCode.count({ where: { userId, usedAt: null } }) };
  }

  async setEmailLoginVerification(userId: string, enabled: boolean, password: string) {
    if (enabled && !feature('AUTH_EMAIL_LOGIN_VERIFICATION_ENABLED')) throw new ForbiddenException('Email login verification is not enabled');
    const user = await this.requirePassword(userId, password);
    await this.prisma.user.update({ where: { id: userId }, data: { emailLoginVerificationEnabled: enabled } });
    await this.audit.log({ userId, action: 'auth.email_login_verification_changed', entityType: 'User', entityId: userId, metadata: { enabled } });
    await this.securityEmail(user, SecurityEmailType.SECURITY_SETTINGS_CHANGED, `email-login:${userId}:${enabled}`, 'FundWell security settings changed', `Email login verification was ${enabled ? 'enabled' : 'disabled'}.`);
    return { enabled };
  }

  async beginTotpEnrollment(userId: string, password: string) {
    if (!feature('AUTH_MFA_ENABLED')) throw new ForbiddenException('Authenticator MFA is not enabled');
    const user = await this.requirePassword(userId, password);
    const secret = encodeBase32(randomBytes(20));
    await this.prisma.user.update({ where: { id: userId }, data: { totpPendingSecretEncrypted: this.encrypt(secret), totpPendingExpiresAt: new Date(Date.now() + 10 * 60_000) } });
    return { secret, otpauthUri: `otpauth://totp/FundWell:${encodeURIComponent(user.email)}?secret=${secret}&issuer=FundWell&algorithm=SHA1&digits=6&period=30`, expiresInSeconds: 600 };
  }

  async confirmTotpEnrollment(userId: string, code: string) {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    if (!user.totpPendingSecretEncrypted || !user.totpPendingExpiresAt || user.totpPendingExpiresAt <= new Date()) throw new UnauthorizedException('Authenticator setup expired');
    const secret = this.decrypt(user.totpPendingSecretEncrypted); const step = BigInt(Math.floor(Date.now() / 30_000));
    if (![step - 1n, step, step + 1n].some((candidate) => totpAt(secret, candidate) === code)) throw new UnauthorizedException('Incorrect authenticator code');
    const codes = this.recoveryCodes();
    await this.prisma.$transaction([
      this.prisma.user.update({ where: { id: userId }, data: { mfaEnabled: true, totpSecretEncrypted: user.totpPendingSecretEncrypted, totpPendingSecretEncrypted: null, totpPendingExpiresAt: null, totpLastUsedStep: step } }),
      this.prisma.mfaRecoveryCode.deleteMany({ where: { userId } }),
      this.prisma.mfaRecoveryCode.createMany({ data: await Promise.all(codes.map(async (value) => ({ userId, codeHash: await argon2.hash(value) }))) }),
    ]);
    await this.audit.log({ userId, action: 'auth.mfa_enabled', entityType: 'User', entityId: userId });
    await this.securityEmail(user, SecurityEmailType.MFA_ENABLED, `mfa-enabled:${userId}`, 'Authenticator MFA enabled', 'Authenticator-app MFA was enabled for your FundWell account.');
    return { enabled: true, recoveryCodes: codes };
  }

  async disableTotp(userId: string, password: string, code: string) {
    const user = await this.requirePassword(userId, password);
    if (!user.mfaEnabled || !user.totpSecretEncrypted) throw new BadRequestException('Authenticator MFA is not enabled');
    const step = BigInt(Math.floor(Date.now() / 30_000));
    const secret = this.decrypt(user.totpSecretEncrypted);
    const acceptedStep = [step - 1n, step, step + 1n].find((candidate) => totpAt(secret, candidate) === code) ?? null;
    const recoveryCodeId = acceptedStep == null ? await this.findRecoveryCode(userId, code) : null;
    if (acceptedStep == null && recoveryCodeId == null) throw new UnauthorizedException('Strong authentication failed');
    await this.prisma.$transaction(async (tx) => {
      if (acceptedStep != null) {
        const replaySafe = await tx.user.updateMany({ where: { id: userId, OR: [{ totpLastUsedStep: null }, { totpLastUsedStep: { lt: acceptedStep } }] }, data: { totpLastUsedStep: acceptedStep } });
        if (replaySafe.count !== 1) throw new UnauthorizedException('Authenticator code was already used');
      } else {
        const consumed = await tx.mfaRecoveryCode.updateMany({ where: { id: recoveryCodeId!, userId, usedAt: null }, data: { usedAt: new Date() } });
        if (consumed.count !== 1) throw new UnauthorizedException('Recovery code was already used');
      }
      await tx.user.update({ where: { id: userId }, data: { mfaEnabled: false, totpSecretEncrypted: null, totpLastUsedStep: null } });
      await tx.mfaRecoveryCode.deleteMany({ where: { userId } });
      await tx.refreshToken.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    await this.audit.log({ userId, action: 'auth.mfa_disabled', entityType: 'User', entityId: userId });
    await this.securityEmail(user, SecurityEmailType.MFA_DISABLED, `mfa-disabled:${userId}:${Date.now()}`, 'Authenticator MFA disabled', 'Authenticator-app MFA was disabled and active sessions were revoked.');
    return { disabled: true };
  }

  async regenerateRecoveryCodes(userId: string, password: string, code: string) {
    const user = await this.requirePassword(userId, password);
    if (!user.mfaEnabled || !user.totpSecretEncrypted) throw new BadRequestException('Authenticator MFA is not enabled');
    const step = BigInt(Math.floor(Date.now() / 30_000));
    if (![step - 1n, step, step + 1n].some((candidate) => totpAt(this.decrypt(user.totpSecretEncrypted!), candidate) === code)) throw new UnauthorizedException('Strong authentication failed');
    const codes = this.recoveryCodes();
    await this.prisma.$transaction([this.prisma.mfaRecoveryCode.deleteMany({ where: { userId } }), this.prisma.mfaRecoveryCode.createMany({ data: await Promise.all(codes.map(async (value) => ({ userId, codeHash: await argon2.hash(value) }))) })]);
    await this.securityEmail(user, SecurityEmailType.RECOVERY_CODES_REGENERATED, `recovery-regenerated:${userId}:${Date.now()}`, 'MFA recovery codes regenerated', 'Your previous recovery codes are no longer valid.');
    return { recoveryCodes: codes };
  }

  async sessions(userId: string) { return this.prisma.refreshToken.findMany({ where: { userId, revokedAt: null, expiresAt: { gt: new Date() } }, select: { id: true, deviceLabel: true, createdAt: true, lastSeenAt: true, expiresAt: true }, orderBy: { lastSeenAt: 'desc' } }); }
  async revokeSession(userId: string, id: string) { const result = await this.prisma.refreshToken.updateMany({ where: { id, userId, revokedAt: null }, data: { revokedAt: new Date() } }); if (!result.count) throw new NotFoundException('Session not found'); return { revoked: true }; }
  async devices(userId: string) { return this.prisma.recognizedDevice.findMany({ where: { userId, revokedAt: null }, select: { id: true, label: true, firstSeenAt: true, lastSeenAt: true }, orderBy: { lastSeenAt: 'desc' } }); }
  async revokeDevice(userId: string, id: string) { const device = await this.prisma.recognizedDevice.findFirst({ where: { id, userId, revokedAt: null } }); if (!device) throw new NotFoundException('Device not found'); await this.prisma.$transaction([this.prisma.recognizedDevice.update({ where: { id }, data: { revokedAt: new Date() } }), this.prisma.refreshToken.updateMany({ where: { userId, deviceHash: device.deviceHash, revokedAt: null }, data: { revokedAt: new Date() } })]); return { revoked: true }; }

  async recognizeDevice(user: any, device: DeviceContext, knownHash?: string | null) {
    if (!feature('AUTH_DEVICE_RECOGNITION_ENABLED')) return;
    const hash = knownHash ?? this.deviceHash(device.deviceId); if (!hash) return;
    const existing = await this.prisma.recognizedDevice.findUnique({ where: { userId_deviceHash: { userId: user.id, deviceHash: hash } } });
    await this.prisma.recognizedDevice.upsert({ where: { userId_deviceHash: { userId: user.id, deviceHash: hash } }, create: { userId: user.id, deviceHash: hash, label: this.cleanLabel(device.deviceName) }, update: { label: this.cleanLabel(device.deviceName) ?? existing?.label, lastSeenAt: new Date(), revokedAt: null } });
    if (!existing || existing.revokedAt) await this.securityEmail(user, SecurityEmailType.NEW_DEVICE_LOGIN, `new-device:${user.id}:${hash}`, 'New sign-in to your FundWell account', `Device: ${this.cleanLabel(device.deviceName) ?? 'Unknown device'}. Time: ${new Date().toISOString()}.`);
  }

  async notifySuspiciousLogin(user: { id: string; email: string }) {
    const hour = Math.floor(Date.now() / 3_600_000);
    await this.securityEmail(
      user,
      SecurityEmailType.SUSPICIOUS_LOGIN,
      `suspicious-login:${user.id}:${hour}`,
      'Suspicious FundWell sign-in activity',
      `An incorrect password was used for your account around ${new Date().toISOString()}. No session was created.`,
    );
  }

  private recoveryCodes() { return Array.from({ length: 10 }, () => `${randomBytes(3).toString('hex').toUpperCase()}-${randomBytes(3).toString('hex').toUpperCase()}`); }
  private async requirePassword(userId: string, password: string) { const user = await this.prisma.user.findUnique({ where: { id: userId } }); if (!user || !(await argon2.verify(user.passwordHash, password))) throw new UnauthorizedException('Password confirmation failed'); return user; }

  async securityEmail(user: { id: string; email: string }, type: SecurityEmailType, dedupeKey: string, subject: string, detail: string) {
    const claimed = await this.prisma.securityEmailEvent.create({ data: { userId: user.id, type, dedupeKey } }).catch((error) => { if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') return null; throw error; });
    if (!claimed) return;
    try { await this.email.sendSecurityNotice(user.email, subject, detail); await this.prisma.securityEmailEvent.update({ where: { id: claimed.id }, data: { sentAt: new Date() } }); }
    catch (error) { await this.prisma.securityEmailEvent.delete({ where: { id: claimed.id } }); throw error; }
  }
}
