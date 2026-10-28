import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { OrganizationRole } from "@prisma/client";
import { AuditService } from "../audit.service";
import { PrismaService } from "../prisma.service";
import { OrganizationAccessService } from "./organization-access.service";

const managers = [OrganizationRole.OWNER, OrganizationRole.ADMIN];
const assignableByAdmin: OrganizationRole[] = [
  OrganizationRole.MANAGER,
  OrganizationRole.VIEWER,
];
const protectedFromAdmin: OrganizationRole[] = [
  OrganizationRole.OWNER,
  OrganizationRole.ADMIN,
];

@Injectable()
export class OrganizationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: OrganizationAccessService,
    private readonly audit: AuditService,
  ) {}

  async create(userId: string, name: string) {
    const organization = await this.prisma.organization.create({
      data: {
        name,
        memberships: { create: { userId, role: OrganizationRole.OWNER } },
      },
    });
    await this.audit.log({
      userId,
      organizationId: organization.id,
      action: "organization.created",
      entityType: "Organization",
      entityId: organization.id,
    });
    return organization;
  }

  list(userId: string) {
    return this.prisma.organization.findMany({
      where: { memberships: { some: { userId } } },
      include: {
        memberships: { where: { userId }, select: { role: true } },
        _count: { select: { locations: true } },
      },
      orderBy: { createdAt: "asc" },
    });
  }

  async get(userId: string, id: string) {
    await this.access.requireMember(userId, id);
    return this.prisma.organization.findUniqueOrThrow({
      where: { id },
      include: {
        memberships: {
          where: { userId },
          select: { userId: true, role: true },
        },
      },
    });
  }

  async members(actorId: string, organizationId: string) {
    const actor = await this.access.requireMember(
      actorId,
      organizationId,
      managers,
    );
    const memberships = await this.prisma.organizationMember.findMany({
      where: { organizationId, user: { disabledAt: null, deletedAt: null } },
      select: {
        id: true,
        userId: true,
        role: true,
        createdAt: true,
        user: { select: { email: true, firstName: true, lastName: true } },
      },
      orderBy: [{ role: "asc" }, { createdAt: "asc" }],
    });
    return {
      currentUserId: actorId,
      currentRole: actor.role,
      members: memberships,
    };
  }

  private validateAssignment(
    actorId: string,
    actorRole: OrganizationRole,
    targetUserId: string,
    targetRole: OrganizationRole | undefined,
    nextRole: OrganizationRole,
  ) {
    if (actorId === targetUserId)
      throw new ForbiddenException(
        "You cannot change your own organization role",
      );
    if (nextRole === OrganizationRole.OWNER)
      throw new BadRequestException(
        "Ownership transfer is not available through team management",
      );
    if (
      actorRole === OrganizationRole.ADMIN &&
      (targetRole === OrganizationRole.OWNER ||
        targetRole === OrganizationRole.ADMIN ||
        !assignableByAdmin.includes(nextRole))
    ) {
      throw new ForbiddenException(
        "Administrators can manage manager and viewer access only",
      );
    }
  }

  async addMember(
    actorId: string,
    organizationId: string,
    userId: string,
    role: OrganizationRole,
  ) {
    const actor = await this.access.requireMember(
      actorId,
      organizationId,
      managers,
    );
    const existing = await this.prisma.organizationMember.findUnique({
      where: { userId_organizationId: { userId, organizationId } },
    });
    this.validateAssignment(actorId, actor.role, userId, existing?.role, role);
    const member = await this.prisma.organizationMember.upsert({
      where: { userId_organizationId: { userId, organizationId } },
      update: { role },
      create: { userId, organizationId, role },
    });
    await this.audit.log({
      userId: actorId,
      organizationId,
      action: existing ? "member.role_changed" : "member.added",
      entityType: "OrganizationMember",
      entityId: member.id,
      metadata: { role },
    });
    return member;
  }

  async updateMemberRole(
    actorId: string,
    organizationId: string,
    memberId: string,
    role: OrganizationRole,
  ) {
    const actor = await this.access.requireMember(
      actorId,
      organizationId,
      managers,
    );
    const member = await this.prisma.organizationMember.findFirst({
      where: { id: memberId, organizationId },
    });
    if (!member) throw new NotFoundException("Team member not found");
    this.validateAssignment(
      actorId,
      actor.role,
      member.userId,
      member.role,
      role,
    );
    const updated = await this.prisma.organizationMember.update({
      where: { id: member.id },
      data: { role },
    });
    await this.audit.log({
      userId: actorId,
      organizationId,
      action: "member.role_changed",
      entityType: "OrganizationMember",
      entityId: member.id,
      metadata: { previousRole: member.role, role },
    });
    return updated;
  }

  async removeMember(
    actorId: string,
    organizationId: string,
    memberId: string,
  ) {
    const actor = await this.access.requireMember(
      actorId,
      organizationId,
      managers,
    );
    const member = await this.prisma.$transaction(
      async (transaction) => {
        const target = await transaction.organizationMember.findFirst({
          where: { id: memberId, organizationId },
        });
        if (!target) throw new NotFoundException("Team member not found");
        if (actorId === target.userId)
          throw new ForbiddenException(
            "You cannot remove your own organization access",
          );
        if (
          actor.role === OrganizationRole.ADMIN &&
          protectedFromAdmin.includes(target.role)
        )
          throw new ForbiddenException(
            "Administrators cannot remove owners or other administrators",
          );
        if (target.role === OrganizationRole.OWNER) {
          const owners = await transaction.organizationMember.count({
            where: { organizationId, role: OrganizationRole.OWNER },
          });
          if (owners <= 1)
            throw new BadRequestException("The last owner cannot be removed");
        }
        await transaction.organizationMember.delete({
          where: { id: target.id },
        });
        return target;
      },
      { isolationLevel: "Serializable" },
    );
    await this.audit.log({
      userId: actorId,
      organizationId,
      action: "member.removed",
      entityType: "OrganizationMember",
      entityId: member.id,
      metadata: { role: member.role },
    });
  }
}
