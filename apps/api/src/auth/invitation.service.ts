import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { BetaInvitationType, OrganizationRole } from '@prisma/client';
import { createHash, randomBytes } from 'crypto';
import { AuditService } from '../audit.service';
import { PrismaService } from '../prisma.service';
import { AuthEmailService } from './auth-email.service';
import { CreateBetaInvitationDto } from './invitation.dto';

const normalizeEmail = (value: string) => value.trim().toLowerCase();
const hashToken = (value: string) => createHash('sha256').update(value).digest('hex');
const invitationManagers: OrganizationRole[] = [OrganizationRole.OWNER, OrganizationRole.ADMIN];

@Injectable()
export class InvitationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly email: AuthEmailService,
    private readonly audit: AuditService,
  ) {}

  private async actor(userId: string) {
    const user = await this.prisma.user.findFirst({
      where: { id: userId, disabledAt: null, deletedAt: null },
      select: { id: true, email: true },
    });
    if (!user) throw new ForbiddenException('Invitation management is unavailable');
    return user;
  }

  private platformAdmin(email: string) {
    const configured = (process.env.BETA_INVITE_ADMIN_EMAILS ?? '')
      .split(',')
      .map(normalizeEmail)
      .filter(Boolean);
    return configured.includes(normalizeEmail(email));
  }

  private async requireOrganizationManager(userId: string, organizationId: string) {
    const membership = await this.prisma.organizationMember.findUnique({
      where: { userId_organizationId: { userId, organizationId } },
    });
    if (!membership || !invitationManagers.includes(membership.role)) {
      throw new ForbiddenException('Only organization owners and administrators can manage invitations');
    }
  }

  async create(userId: string, dto: CreateBetaInvitationDto) {
    this.email.assertConfigured();
    const actor = await this.actor(userId);
    const isPlatformAdmin = this.platformAdmin(actor.email);
    const email = normalizeEmail(dto.email);
    let organizationId: string | null = null;
    let organizationName: string | null = null;
    let role: OrganizationRole | null = null;

    if (dto.type === BetaInvitationType.NEW_ORGANIZATION) {
      if (!isPlatformAdmin) throw new ForbiddenException('Only FundWell beta administrators can invite a new restaurant');
      organizationName = dto.organizationName?.trim() || null;
      if (!organizationName) throw new BadRequestException('Restaurant organization name is required');
      role = OrganizationRole.OWNER;
    } else {
      if (!dto.organizationId) throw new BadRequestException('Organization is required');
      organizationId = dto.organizationId;
      if (!isPlatformAdmin) await this.requireOrganizationManager(userId, organizationId);
      const organization = await this.prisma.organization.findFirst({ where: { id: organizationId, archivedAt: null }, select: { id: true } });
      if (!organization) throw new NotFoundException('Organization not found');
      role = dto.role ?? OrganizationRole.VIEWER;
      if (role === OrganizationRole.OWNER) throw new BadRequestException('Ownership must be transferred through the organization settings');
    }

    const rawToken = randomBytes(32).toString('base64url');
    const invitation = await this.prisma.betaInvitation.create({
      data: {
        email,
        tokenHash: hashToken(rawToken),
        type: dto.type,
        organizationId,
        organizationName,
        role,
        expiresAt: new Date(Date.now() + (dto.expiresInDays ?? 7) * 86400000),
        createdByUserId: userId,
      },
    });
    try {
      await this.email.sendBetaInvitation(email, rawToken);
    } catch (error) {
      await this.prisma.betaInvitation.updateMany({ where: { id: invitation.id, redeemedAt: null }, data: { revokedAt: new Date() } });
      throw error;
    }
    await this.audit.log({
      userId,
      organizationId: organizationId ?? undefined,
      action: 'beta_invitation.created',
      entityType: 'BetaInvitation',
      entityId: invitation.id,
      metadata: { type: invitation.type, role: invitation.role, expiresAt: invitation.expiresAt },
    });
    return {
      id: invitation.id,
      email: invitation.email,
      type: invitation.type,
      organizationId: invitation.organizationId,
      organizationName: invitation.organizationName,
      role: invitation.role,
      expiresAt: invitation.expiresAt,
      ...(this.email.developmentMode ? { developmentInvitationToken: rawToken } : {}),
    };
  }

  async list(userId: string, organizationId?: string) {
    const actor = await this.actor(userId);
    if (organizationId) {
      if (!this.platformAdmin(actor.email)) await this.requireOrganizationManager(userId, organizationId);
      return this.prisma.betaInvitation.findMany({
        where: { organizationId },
        select: { id: true, email: true, type: true, role: true, expiresAt: true, revokedAt: true, redeemedAt: true, createdAt: true },
        orderBy: { createdAt: 'desc' },
      });
    }
    if (!this.platformAdmin(actor.email)) throw new ForbiddenException('A restaurant is required');
    return this.prisma.betaInvitation.findMany({
      where: { type: BetaInvitationType.NEW_ORGANIZATION },
      select: { id: true, email: true, type: true, organizationName: true, expiresAt: true, revokedAt: true, redeemedAt: true, createdAt: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  async revoke(userId: string, id: string) {
    const invitation = await this.prisma.betaInvitation.findUnique({ where: { id } });
    if (!invitation) throw new NotFoundException('Invitation not found');
    const actor = await this.actor(userId);
    if (invitation.organizationId) {
      if (!this.platformAdmin(actor.email)) await this.requireOrganizationManager(userId, invitation.organizationId);
    } else if (!this.platformAdmin(actor.email)) {
      throw new ForbiddenException('Only FundWell beta administrators can revoke this invitation');
    }
    if (invitation.redeemedAt) throw new BadRequestException('A redeemed invitation cannot be revoked');
    await this.prisma.betaInvitation.updateMany({ where: { id, redeemedAt: null, revokedAt: null }, data: { revokedAt: new Date() } });
    await this.audit.log({ userId, organizationId: invitation.organizationId ?? undefined, action: 'beta_invitation.revoked', entityType: 'BetaInvitation', entityId: id });
  }
}
