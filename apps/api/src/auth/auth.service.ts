import { ConflictException, ForbiddenException, Injectable, NotFoundException, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { BetaInvitationType, OrganizationRole, SecurityEmailType } from '@prisma/client';
import * as argon2 from 'argon2';
import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'crypto';
import { AuditService } from '../audit.service';
import { PrismaService } from '../prisma.service';
import { AuthEmailService } from './auth-email.service';
import { AuthSecurityService } from './auth-security.service';
import { RegisterDto } from './dto';

const normalizeEmail = (value: string) => value.trim().toLowerCase();
const tokenHash = (value: string) => createHash('sha256').update(value).digest('hex');
const genericResetMessage = 'If an account exists for this email, password reset instructions have been sent.';
const genericVerificationMessage = 'If this account needs verification, a new email has been sent.';

@Injectable()
export class AuthService {
  constructor(private readonly prisma: PrismaService, private readonly jwt: JwtService, private readonly email: AuthEmailService, private readonly audit: AuditService, private readonly security?: AuthSecurityService) {}

  async invitationPreview(rawToken: string) {
    const invitation = await this.prisma.betaInvitation.findUnique({
      where: { tokenHash: tokenHash(rawToken) },
      select: {
        email: true,
        type: true,
        organizationName: true,
        organization: { select: { name: true, archivedAt: true } },
        role: true,
        expiresAt: true,
        revokedAt: true,
        redeemedAt: true,
      },
    });
    const unavailable =
      !invitation ||
      invitation.revokedAt != null ||
      invitation.redeemedAt != null ||
      invitation.expiresAt <= new Date() ||
      (invitation.type === BetaInvitationType.JOIN_ORGANIZATION &&
        (!invitation.organization || invitation.organization.archivedAt != null));
    if (unavailable) {
      throw new UnauthorizedException('Invitation is invalid or unavailable');
    }
    return {
      email: invitation.email,
      organizationName:
        invitation.type === BetaInvitationType.JOIN_ORGANIZATION
          ? invitation.organization!.name
          : invitation.organizationName,
      role: invitation.role,
      expiresAt: invitation.expiresAt,
    };
  }

  async register(dto: RegisterDto) {
    this.email.assertConfigured();
    const email = normalizeEmail(dto.email);
    const now = new Date();
    const passwordHash = await argon2.hash(dto.password);
    const raw = randomBytes(32).toString('base64url');
    const invitationHash = tokenHash(dto.invitationToken);
    const user = await this.prisma.$transaction(async (tx) => {
      const invitation = await tx.betaInvitation.findUnique({ where: { tokenHash: invitationHash } });
      if (!invitation) throw new UnauthorizedException('Invitation is invalid');
      if (normalizeEmail(invitation.email) !== email) throw new ForbiddenException('This invitation was issued to a different email address');
      if (invitation.revokedAt) throw new ForbiddenException('Invitation has been revoked');
      if (invitation.redeemedAt) throw new ConflictException('Invitation has already been used');
      if (invitation.expiresAt <= now) throw new UnauthorizedException('Invitation has expired');
      if (await tx.user.findUnique({ where: { email } })) throw new ConflictException('Email is already registered. Log in or reset your password.');

      const created = await tx.user.create({
        data: {
          email,
          passwordHash,
          firstName: dto.firstName?.trim() || null,
          lastName: dto.lastName?.trim() || null,
        },
      });
      const claimed = await tx.betaInvitation.updateMany({
        where: { id: invitation.id, redeemedAt: null, revokedAt: null, expiresAt: { gt: now } },
        data: { redeemedAt: now, redeemedByUserId: created.id },
      });
      if (claimed.count !== 1) throw new ConflictException('Invitation has already been used');

      if (invitation.type === BetaInvitationType.NEW_ORGANIZATION) {
        if (!invitation.organizationName) throw new ConflictException('Invitation is not configured for a restaurant');
        const organization = await tx.organization.create({
          data: {
            name: invitation.organizationName,
            memberships: { create: { userId: created.id, role: OrganizationRole.OWNER } },
          },
        });
        await tx.onboardingState.create({ data: { userId: created.id, organizationId: organization.id } });
      } else {
        if (!invitation.organizationId || !invitation.role) throw new ConflictException('Invitation is not configured for an organization');
        const organization = await tx.organization.findFirst({
          where: { id: invitation.organizationId, archivedAt: null },
          select: { id: true, locations: { select: { id: true }, orderBy: { createdAt: 'asc' }, take: 1 } },
        });
        if (!organization) throw new ConflictException('Invitation organization is no longer available');
        await tx.organizationMember.create({
          data: { userId: created.id, organizationId: organization.id, role: invitation.role },
        });
        const location = organization.locations[0];
        await tx.onboardingState.create({
          data: {
            userId: created.id,
            organizationId: organization.id,
            restaurantLocationId: location?.id,
            currentStep: location ? 6 : 1,
            onboardingCompletedAt: location ? now : null,
          },
        });
      }
      await tx.emailVerificationToken.create({
        data: { userId: created.id, tokenHash: tokenHash(raw), expiresAt: new Date(now.getTime() + 24 * 60 * 60_000) },
      });
      return created;
    });
    await this.audit.log({ userId: user.id, action: 'auth.account_registered', entityType: 'User', entityId: user.id });
    await this.email.sendVerification(user.email, raw);
    return { verificationRequired: true, email: user.email, ...(this.email.developmentMode ? { developmentVerificationToken: raw } : {}) };
  }

  async verifyEmail(raw: string) {
    const stored = await this.prisma.emailVerificationToken.findUnique({ where: { tokenHash: tokenHash(raw) } });
    if (!stored) throw new UnauthorizedException('Verification link is invalid or expired');
    const claimed = await this.prisma.emailVerificationToken.updateMany({ where: { id: stored.id, usedAt: null, expiresAt: { gt: new Date() } }, data: { usedAt: new Date() } });
    if (claimed.count !== 1) throw new UnauthorizedException('Verification link is invalid or expired');
    await this.prisma.user.update({ where: { id: stored.userId }, data: { emailVerifiedAt: new Date() } });
    await this.audit.log({ userId: stored.userId, action: 'auth.email_verified', entityType: 'User', entityId: stored.userId });
    if (this.security) {
      const user = await this.prisma.user.findUnique({ where: { id: stored.userId } });
      if (user) await this.security.securityEmail(user, SecurityEmailType.WELCOME, `welcome:${user.id}`, 'Welcome to FundWell', 'Your email is verified and your FundWell account is ready.');
    }
    return { verified: true };
  }

  async resendVerification(rawEmail: string) {
    this.email.assertConfigured();
    const user = await this.prisma.user.findUnique({ where: { email: normalizeEmail(rawEmail) } });
    if (!user || user.emailVerifiedAt || user.deletedAt || user.disabledAt) return { message: genericVerificationMessage };
    const recent = await this.prisma.emailVerificationToken.findFirst({ where: { userId: user.id, createdAt: { gt: new Date(Date.now() - 60_000) } } });
    if (recent) return { message: genericVerificationMessage };
    const raw = await this.createVerificationToken(user.id);
    await this.email.sendVerification(user.email, raw);
    return { message: genericVerificationMessage, ...(this.email.developmentMode ? { developmentVerificationToken: raw } : {}) };
  }

  async login(rawEmail: string, password: string, device: { deviceId?: string; deviceName?: string } = {}) {
    const email = normalizeEmail(rawEmail);
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user || user.deletedAt || user.disabledAt) throw new UnauthorizedException('Invalid email or password');
    if (!(await argon2.verify(user.passwordHash, password))) {
      // Notification delivery must never change the neutral authentication
      // response or turn an email-provider outage into account enumeration.
      await this.security?.notifySuspiciousLogin(user).catch(() => undefined);
      throw new UnauthorizedException('Invalid email or password');
    }
    if (!user.emailVerifiedAt && email !== 'demo@profitlens.local') throw new ForbiddenException('Email verification required');
    const challenge = await this.security?.beginLogin(user, device);
    if (challenge) return challenge;
    const tokens = await this.issueTokens(user.id, user.email, undefined, device);
    await this.security?.recognizeDevice(user, device);
    return tokens;
  }

  /**
   * Temporary pre-release entry point for the one explicitly configured shared
   * test account. It is intentionally unavailable unless the server-side flag
   * is enabled, and it cannot authenticate an arbitrary user.
   */
  async sharedTestSession(clientToken?: string) {
    if (process.env.SHARED_TEST_USER_MODE !== 'true') throw new NotFoundException();
    const configuredToken = process.env.SHARED_TEST_CLIENT_TOKEN?.trim();
    if (!configuredToken || !clientToken) throw new NotFoundException();
    const expected = Buffer.from(configuredToken);
    const received = Buffer.from(clientToken);
    if (expected.length !== received.length || !timingSafeEqual(expected, received)) throw new NotFoundException();
    const email = normalizeEmail(process.env.SHARED_TEST_USER_EMAIL ?? 'test@profitlens.local');
    const user = await this.prisma.user.findFirst({
      where: {
        email,
        emailVerifiedAt: { not: null },
        disabledAt: null,
        deletedAt: null,
        memberships: { some: { role: OrganizationRole.OWNER } },
      },
      select: { id: true, email: true },
    });
    if (!user) throw new NotFoundException();
    return this.issueTokens(user.id, user.email);
  }

  async privateSession(accessCode: string, device: { deviceId?: string; deviceName?: string } = {}) {
    const accessCodeHash = process.env.PRIVATE_BETA_ACCESS_CODE_HASH?.trim();
    const configuredEmail = process.env.PRIVATE_BETA_USER_EMAIL?.trim();
    if (!accessCodeHash || !configuredEmail) throw new ServiceUnavailableException('Private account access is not configured');
    let valid = false;
    try { valid = await argon2.verify(accessCodeHash, accessCode); } catch { throw new ServiceUnavailableException('Private account access is not configured'); }
    if (!valid) throw new UnauthorizedException('Invalid private account access code');
    const email = normalizeEmail(configuredEmail);
    const user = await this.prisma.user.findFirst({
      where: { email, emailVerifiedAt: { not: null }, disabledAt: null, deletedAt: null },
      include: { memberships: { include: { organization: { include: { locations: true } } } } },
    });
    const ownerMemberships = user?.memberships.filter((membership) => membership.role === OrganizationRole.OWNER) ?? [];
    if (!user || ownerMemberships.length !== 1 || ownerMemberships[0].organization.locations.length !== 1) throw new ServiceUnavailableException('Private account is not provisioned correctly');
    const challenge = await this.security?.beginLogin(user, device);
    if (challenge) return { ...challenge, accountMode: 'private' as const };
    return { ...(await this.issueTokens(user.id, user.email, undefined, device)), accountMode: 'private' as const };
  }

  async completeLoginChallenge(challengeId: string, code: string) {
    if (!this.security) throw new NotFoundException();
    const result = await this.security.completeLogin(challengeId, code);
    const tokens = await this.issueTokens(result.user.id, result.user.email, undefined, { deviceName: result.deviceLabel ?? undefined }, result.deviceIdHash);
    await this.security.recognizeDevice(result.user, { deviceName: result.deviceLabel ?? undefined }, result.deviceIdHash);
    return tokens;
  }

  async refresh(rawToken: string) {
    const payload = await this.refreshPayload(rawToken);
    const user = await this.prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user || user.deletedAt || user.disabledAt || !user.emailVerifiedAt) throw new UnauthorizedException('Invalid refresh token');
    const stored = payload.sid ? await this.prisma.refreshToken.findUnique({ where: { id: payload.sid } }) : await this.findLegacyToken(payload.sub, rawToken);
    if (!stored || stored.userId !== payload.sub || stored.expiresAt <= new Date() || !(await argon2.verify(stored.tokenHash, rawToken))) throw new UnauthorizedException('Refresh token revoked');
    if (stored.revokedAt) {
      await this.revokeReplacementChain(stored.replacedByTokenId, stored.userId);
      throw new UnauthorizedException('Refresh token revoked');
    }
    const claimed = await this.prisma.refreshToken.updateMany({ where: { id: stored.id, revokedAt: null, expiresAt: { gt: new Date() } }, data: { revokedAt: new Date() } });
    if (claimed.count !== 1) {
      await this.revokeReplacementChain(stored.replacedByTokenId, stored.userId);
      throw new UnauthorizedException('Refresh token revoked');
    }
    await this.prisma.refreshToken.update({ where: { id: stored.id }, data: { lastSeenAt: new Date() } });
    return this.issueTokens(user.id, user.email, stored.id, { deviceName: stored.deviceLabel ?? undefined }, stored.deviceHash);
  }

  async logout(rawToken: string) {
    let payload: { sub: string; type: string; sid?: string };
    try { payload = await this.refreshPayload(rawToken); } catch { return; }
    if (payload.sid) { await this.prisma.refreshToken.updateMany({ where: { id: payload.sid, userId: payload.sub, revokedAt: null }, data: { revokedAt: new Date() } }); return; }
    const legacy = await this.findLegacyToken(payload.sub, rawToken);
    if (legacy) await this.prisma.refreshToken.updateMany({ where: { id: legacy.id, revokedAt: null }, data: { revokedAt: new Date() } });
  }

  async signOutAll(userId: string) {
    const result = await this.prisma.refreshToken.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
    await this.audit.log({ userId, action: 'auth.sessions_revoked', entityType: 'User', entityId: userId, metadata: { count: result.count } });
    return { revoked: result.count };
  }

  async forgotPassword(rawEmail: string) {
    this.email.assertConfigured();
    const user = await this.prisma.user.findUnique({ where: { email: normalizeEmail(rawEmail) } });
    if (!user || user.deletedAt || user.disabledAt) return { message: genericResetMessage };
    const recent = await this.prisma.passwordResetToken.findFirst({ where: { userId: user.id, createdAt: { gt: new Date(Date.now() - 60_000) } } });
    if (recent) return { message: genericResetMessage };
    const raw = randomBytes(32).toString('base64url');
    await this.prisma.passwordResetToken.create({ data: { userId: user.id, tokenHash: tokenHash(raw), expiresAt: new Date(Date.now() + 30 * 60_000) } });
    await this.email.sendPasswordReset(user.email, raw);
    return { message: genericResetMessage, ...(this.email.developmentMode ? { developmentResetToken: raw } : {}) };
  }

  async resetPassword(raw: string, password: string) {
    const stored = await this.prisma.passwordResetToken.findUnique({ where: { tokenHash: tokenHash(raw) } });
    if (!stored) throw new UnauthorizedException('Password reset link is invalid or expired');
    const claimed = await this.prisma.passwordResetToken.updateMany({ where: { id: stored.id, usedAt: null, expiresAt: { gt: new Date() } }, data: { usedAt: new Date() } });
    if (claimed.count !== 1) throw new UnauthorizedException('Password reset link is invalid or expired');
    await this.prisma.$transaction([
      this.prisma.user.update({ where: { id: stored.userId }, data: { passwordHash: await argon2.hash(password) } }),
      this.prisma.refreshToken.updateMany({ where: { userId: stored.userId, revokedAt: null }, data: { revokedAt: new Date() } }),
    ]);
    await this.audit.log({ userId: stored.userId, action: 'auth.password_reset_completed', entityType: 'User', entityId: stored.userId });
    if (this.security) {
      const user = await this.prisma.user.findUnique({ where: { id: stored.userId } });
      if (user) await this.security.securityEmail(user, SecurityEmailType.ACCOUNT_RECOVERED, `password-reset:${stored.id}`, 'Your FundWell password was reset', 'Password recovery completed successfully. Existing MFA remains enabled.');
    }
    return { reset: true };
  }

  async changePassword(userId: string, currentPassword: string, newPassword: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user || !(await argon2.verify(user.passwordHash, currentPassword))) throw new UnauthorizedException('Current password is incorrect');
    const now = new Date();
    await this.prisma.$transaction([
      this.prisma.user.update({ where: { id: userId }, data: { passwordHash: await argon2.hash(newPassword) } }),
      this.prisma.refreshToken.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: now } }),
    ]);
    await this.audit.log({ userId, action: 'auth.password_changed', entityType: 'User', entityId: userId });
    await this.security?.securityEmail(user, SecurityEmailType.PASSWORD_CHANGED, `password-changed:${userId}:${now.getTime()}`, 'Your FundWell password was changed', 'Your password changed successfully and active sessions were revoked.');
    return { changed: true };
  }

  async deleteAccount(userId: string, password: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId }, include: { memberships: true } });
    if (!user || user.deletedAt || !(await argon2.verify(user.passwordHash, password))) throw new UnauthorizedException('Password confirmation failed');
    const protectedSharedEmail = normalizeEmail(process.env.SHARED_TEST_USER_EMAIL ?? 'test@profitlens.local');
    if (user.email === 'demo@profitlens.local' || user.email === protectedSharedEmail) throw new ForbiddenException('The shared beta account cannot be deleted');
    const archiveOrganizationIds: string[] = [];
    for (const membership of user.memberships) {
      if (membership.role !== OrganizationRole.OWNER) continue;
      const [otherOwners, otherMembers] = await Promise.all([
        this.prisma.organizationMember.count({ where: { organizationId: membership.organizationId, userId: { not: userId }, role: OrganizationRole.OWNER } }),
        this.prisma.organizationMember.count({ where: { organizationId: membership.organizationId, userId: { not: userId } } }),
      ]);
      if (otherMembers > 0 && otherOwners === 0) throw new ConflictException('Transfer organization ownership before deleting your account');
      if (otherMembers === 0) archiveOrganizationIds.push(membership.organizationId);
    }
    const now = new Date();
    await this.prisma.$transaction([
      this.prisma.organization.updateMany({ where: { id: { in: archiveOrganizationIds } }, data: { archivedAt: now } }),
      this.prisma.organizationMember.deleteMany({ where: { userId } }),
      this.prisma.refreshToken.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: now } }),
      this.prisma.devicePushToken.updateMany({ where: { userId, active: true }, data: { active: false } }),
      this.prisma.user.update({ where: { id: userId }, data: { email: `deleted+${userId}@profitlens.invalid`, firstName: null, lastName: null, passwordHash: await argon2.hash(randomBytes(32)), disabledAt: now, deletedAt: now } }),
    ]);
    await this.audit.log({ userId, action: 'auth.account_deleted', entityType: 'User', entityId: userId, metadata: { archivedOrganizationCount: archiveOrganizationIds.length } });
    return { deleted: true };
  }

  async profile(userId: string) {
    const user = await this.prisma.user.findFirstOrThrow({ where: { id: userId, disabledAt: null, deletedAt: null }, select: { id: true, email: true, firstName: true, lastName: true, emailVerifiedAt: true, createdAt: true } });
    const privateEmail = process.env.PRIVATE_BETA_USER_EMAIL?.trim().toLowerCase();
    return { ...user, accountMode: privateEmail && user.email === privateEmail ? 'private' : 'standard' };
  }

  private async createVerificationToken(userId: string) {
    const raw = randomBytes(32).toString('base64url');
    await this.prisma.emailVerificationToken.create({ data: { userId, tokenHash: tokenHash(raw), expiresAt: new Date(Date.now() + 24 * 60 * 60_000) } });
    return raw;
  }

  private async refreshPayload(rawToken: string) {
    try {
      const payload = await this.jwt.verifyAsync<{ sub: string; type: string; sid?: string }>(rawToken, { secret: process.env.JWT_REFRESH_SECRET });
      if (payload.type !== 'refresh') throw new Error();
      return payload;
    } catch { throw new UnauthorizedException('Invalid refresh token'); }
  }

  private async findLegacyToken(userId: string, rawToken: string) {
    const tokens = await this.prisma.refreshToken.findMany({ where: { userId, revokedAt: null, expiresAt: { gt: new Date() } } });
    for (const token of tokens) if (await argon2.verify(token.tokenHash, rawToken)) return token;
    return null;
  }

  private async revokeReplacementChain(firstId: string | null | undefined, userId: string) {
    let id = firstId;
    const visited = new Set<string>();
    while (id && !visited.has(id) && visited.size < 100) {
      visited.add(id);
      const replacement = await this.prisma.refreshToken.findUnique({ where: { id } });
      if (!replacement || replacement.userId !== userId) break;
      await this.prisma.refreshToken.updateMany({ where: { id, userId, revokedAt: null }, data: { revokedAt: new Date() } });
      id = replacement.replacedByTokenId;
    }
  }

  private async issueTokens(userId: string, email: string, replacedId?: string, device: { deviceId?: string; deviceName?: string } = {}, knownDeviceHash?: string | null) {
    const refreshDays = Number(process.env.JWT_REFRESH_TTL_DAYS ?? 30);
    const id = randomUUID();
    const accessToken = await this.jwt.signAsync({ sub: userId, email }, { secret: process.env.JWT_ACCESS_SECRET, expiresIn: 900 });
    const refreshToken = await this.jwt.signAsync({ sub: userId, type: 'refresh', sid: id, jti: randomUUID() }, { secret: process.env.JWT_REFRESH_SECRET, expiresIn: refreshDays * 86400 });
    const deviceHash = knownDeviceHash ?? (device.deviceId ? createHash('sha256').update(`${process.env.AUTH_CHALLENGE_SECRET ?? process.env.JWT_ACCESS_SECRET ?? 'development'}:device:${device.deviceId}`).digest('hex') : null);
    await this.prisma.refreshToken.create({ data: { id, userId, tokenHash: await argon2.hash(refreshToken), expiresAt: new Date(Date.now() + refreshDays * 86400000), deviceHash, deviceLabel: device.deviceName?.trim().slice(0, 80) || null } });
    if (replacedId) await this.prisma.refreshToken.update({ where: { id: replacedId }, data: { replacedByTokenId: id } });
    return { accessToken, refreshToken, tokenType: 'Bearer' };
  }
}
