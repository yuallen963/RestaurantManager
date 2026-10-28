import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { OrganizationRole } from '@prisma/client';
import { OrganizationsService } from '../src/organizations/organizations.service';

describe('organization team management', () => {
  const member = (overrides: Record<string, unknown> = {}) => ({ id: 'member-id', userId: 'target-user', organizationId: 'org-a', role: OrganizationRole.VIEWER, ...overrides });
  const setup = (actorRole: OrganizationRole = OrganizationRole.OWNER) => {
    const prisma: any = {
      organizationMember: {
        findUnique: jest.fn(), findFirst: jest.fn(), findMany: jest.fn().mockResolvedValue([]),
        upsert: jest.fn(), update: jest.fn(), delete: jest.fn(), count: jest.fn(),
      },
    };
    prisma.$transaction = jest.fn((operation: (transaction: typeof prisma) => unknown) => operation(prisma));
    const access: any = { requireMember: jest.fn().mockResolvedValue({ userId: 'actor', organizationId: 'org-a', role: actorRole }) };
    const audit: any = { log: jest.fn() };
    return { service: new OrganizationsService(prisma, access, audit), prisma, access, audit };
  };

  it('lists identities only after owner or administrator membership succeeds', async () => {
    const { service, access, prisma } = setup();
    await service.members('actor', 'org-a');
    expect(access.requireMember).toHaveBeenCalledWith('actor', 'org-a', [OrganizationRole.OWNER, OrganizationRole.ADMIN]);
    expect(prisma.organizationMember.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ organizationId: 'org-a' }) }));
  });

  it('rejects cross-organization member identifiers', async () => {
    const { service, prisma } = setup();
    prisma.organizationMember.findFirst.mockResolvedValue(null);
    await expect(service.updateMemberRole('actor', 'org-a', 'other-org-member', OrganizationRole.ADMIN)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('prevents self elevation or self role changes', async () => {
    const { service, prisma } = setup(OrganizationRole.ADMIN);
    prisma.organizationMember.findFirst.mockResolvedValue(member({ userId: 'actor', role: OrganizationRole.ADMIN }));
    await expect(service.updateMemberRole('actor', 'org-a', 'member-id', OrganizationRole.OWNER)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('prevents administrators from assigning owner or administrator access', async () => {
    const { service, prisma } = setup(OrganizationRole.ADMIN);
    prisma.organizationMember.findFirst.mockResolvedValue(member());
    await expect(service.updateMemberRole('actor', 'org-a', 'member-id', OrganizationRole.OWNER)).rejects.toBeInstanceOf(BadRequestException);
    await expect(service.updateMemberRole('actor', 'org-a', 'member-id', OrganizationRole.ADMIN)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('allows an owner to change a staff role and records an audit event', async () => {
    const { service, prisma, audit } = setup();
    prisma.organizationMember.findFirst.mockResolvedValue(member());
    prisma.organizationMember.update.mockResolvedValue(member({ role: OrganizationRole.ADMIN }));
    await service.updateMemberRole('actor', 'org-a', 'member-id', OrganizationRole.ADMIN);
    expect(prisma.organizationMember.update).toHaveBeenCalledWith({ where: { id: 'member-id' }, data: { role: OrganizationRole.ADMIN } });
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'member.role_changed', organizationId: 'org-a' }));
  });

  it('protects the last owner from removal', async () => {
    const { service, prisma } = setup();
    prisma.organizationMember.findFirst.mockResolvedValue(member({ role: OrganizationRole.OWNER }));
    prisma.organizationMember.count.mockResolvedValue(1);
    await expect(service.removeMember('actor', 'org-a', 'member-id')).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.organizationMember.delete).not.toHaveBeenCalled();
  });

  it('prevents administrators from removing owners and administrators', async () => {
    const { service, prisma } = setup(OrganizationRole.ADMIN);
    prisma.organizationMember.findFirst.mockResolvedValue(member({ role: OrganizationRole.OWNER }));
    await expect(service.removeMember('actor', 'org-a', 'member-id')).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('removes permitted staff access within the organization', async () => {
    const { service, prisma } = setup();
    prisma.organizationMember.findFirst.mockResolvedValue(member());
    await service.removeMember('actor', 'org-a', 'member-id');
    expect(prisma.organizationMember.delete).toHaveBeenCalledWith({ where: { id: 'member-id' } });
  });
});
