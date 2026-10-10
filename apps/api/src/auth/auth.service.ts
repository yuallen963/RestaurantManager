import { ConflictException, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { OrganizationRole } from '@prisma/client';
import * as argon2 from 'argon2';
import { createHash, randomBytes, randomUUID } from 'crypto';
import { AuditService } from '../audit.service';
import { PrismaService } from '../prisma.service';
import { AuthEmailService } from './auth-email.service';
import { RegisterDto } from './dto';

const normalizeEmail = (value: string) => value.trim().toLowerCase();
const tokenHash = (value: string) => createHash('sha256').update(value).digest('hex');
const genericResetMessage = 'If an account exists for this email, password reset instructions have been sent.';
const genericVerificationMessage = 'If this account needs verification, a new email has been sent.';

@Injectable()
export class AuthService {
  constructor(private readonly prisma: PrismaService, private readonly jwt: JwtService, private readonly email: AuthEmailService, private readonly audit: AuditService) {}

  async register(dto: RegisterDto) {
    this.email.assertConfigured();
    const email = normalizeEmail(dto.email);
    if (await this.prisma.user.findUnique({ where: { email } })) throw new ConflictException('Email is already registered. Log in or reset your password.');
    const user = await this.prisma.user.create({ data: { email, passwordHash: await argon2.hash(dto.password), firstName: dto.firstName?.trim() || null, lastName: dto.lastName?.trim() || null } });
    const raw = await this.createVerificationToken(user.id);
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

  async login(rawEmail: string, password: string) {
    const email = normalizeEmail(rawEmail);
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user || user.deletedAt || user.disabledAt || !(await argon2.verify(user.passwordHash, password))) throw new UnauthorizedException('Invalid email or password');
    if (!user.emailVerifiedAt && email !== 'demo@profitlens.local') throw new ForbiddenException('Email verification required');
    return this.issueTokens(user.id, user.email);
  }

  async refresh(rawToken: string) {
    const payload = await this.refreshPayload(rawToken);
    const user = await this.prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user || user.deletedAt || user.disabledAt || !user.emailVerifiedAt) throw new UnauthorizedException('Invalid refresh token');
    const stored = payload.sid ? await this.prisma.refreshToken.findUnique({ where: { id: payload.sid } }) : await this.findLegacyToken(payload.sub, rawToken);
    if (!stored || stored.userId !== payload.sub || stored.revokedAt || stored.expiresAt <= new Date() || !(await argon2.verify(stored.tokenHash, rawToken))) throw new UnauthorizedException('Refresh token revoked');
    const claimed = await this.prisma.refreshToken.updateMany({ where: { id: stored.id, revokedAt: null, expiresAt: { gt: new Date() } }, data: { revokedAt: new Date() } });
    if (claimed.count !== 1) throw new UnauthorizedException('Refresh token revoked');
    return this.issueTokens(user.id, user.email, stored.id);
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
    return { reset: true };
  }

  async deleteAccount(userId: string, password: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId }, include: { memberships: true } });
    if (!user || user.deletedAt || !(await argon2.verify(user.passwordHash, password))) throw new UnauthorizedException('Password confirmation failed');
    if (user.email === 'demo@profitlens.local') throw new ForbiddenException('The demo account cannot be deleted');
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
    return this.prisma.user.findFirstOrThrow({ where: { id: userId, disabledAt: null, deletedAt: null }, select: { id: true, email: true, firstName: true, lastName: true, emailVerifiedAt: true, createdAt: true } });
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

  private async issueTokens(userId: string, email: string, replacedId?: string) {
    const refreshDays = Number(process.env.JWT_REFRESH_TTL_DAYS ?? 30);
    const id = randomUUID();
    const accessToken = await this.jwt.signAsync({ sub: userId, email }, { secret: process.env.JWT_ACCESS_SECRET, expiresIn: 900 });
    const refreshToken = await this.jwt.signAsync({ sub: userId, type: 'refresh', sid: id, jti: randomUUID() }, { secret: process.env.JWT_REFRESH_SECRET, expiresIn: refreshDays * 86400 });
    await this.prisma.refreshToken.create({ data: { id, userId, tokenHash: await argon2.hash(refreshToken), expiresAt: new Date(Date.now() + refreshDays * 86400000) } });
    if (replacedId) await this.prisma.refreshToken.update({ where: { id: replacedId }, data: { replacedByTokenId: id } });
    return { accessToken, refreshToken, tokenType: 'Bearer' };
  }
}
