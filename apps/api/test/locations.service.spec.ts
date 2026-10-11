import { BadRequestException, NotFoundException } from '@nestjs/common';
import { OrganizationRole } from '@prisma/client';
import { validate } from 'class-validator';
import { CreateLocationDto } from '../src/locations/dto';
import { LocationsService } from '../src/locations/locations.service';

const input = {
  name: 'FundWell Test Restaurant',
  addressLine1: '123 Test Street',
  city: 'Rochester',
  state: 'MI',
  postalCode: '48307',
  timezone: 'America/Detroit',
};

function fixture() {
  const prisma: any = {
    restaurantLocation: {
      findMany: jest.fn().mockResolvedValue([]),
      findFirst: jest.fn().mockResolvedValue({ id: 'location-a', organizationId: 'org-a' }),
      create: jest.fn().mockImplementation(({ data }) => ({ id: 'location-new', ...data })),
      update: jest.fn().mockImplementation(({ data }) => ({ id: 'location-a', organizationId: 'org-a', ...data })),
    },
  };
  const access: any = { requireMember: jest.fn().mockResolvedValue({ role: OrganizationRole.OWNER }) };
  const audit: any = { log: jest.fn().mockResolvedValue(undefined) };
  return { prisma, access, audit, service: new LocationsService(prisma, access, audit) };
}

describe('LocationsService', () => {
  it('creates a location in the existing organization for OWNER/ADMIN only', async () => {
    const { service, access, prisma } = fixture();
    const result = await service.create('owner', 'org-a', input);
    expect(access.requireMember).toHaveBeenCalledWith('owner', 'org-a', [OrganizationRole.OWNER, OrganizationRole.ADMIN]);
    expect(result).toMatchObject({ id: 'location-new', organizationId: 'org-a', name: input.name });
    expect(prisma.restaurantLocation.create.mock.calls[0][0].data.invoiceEmailToken).toHaveLength(32);
  });

  it('updates location fields without changing its stable id', async () => {
    const { service, prisma } = fixture();
    const result = await service.update('admin', 'org-a', 'location-a', { name: 'Updated Restaurant', timezone: 'America/Chicago' });
    expect(result.id).toBe('location-a');
    expect(prisma.restaurantLocation.update).toHaveBeenCalledWith({ where: { id: 'location-a' }, data: { name: 'Updated Restaurant', timezone: 'America/Chicago' } });
  });

  it('rejects invalid input and invalid time zones', async () => {
    const dto = Object.assign(new CreateLocationDto(), { ...input, name: '', state: 'Michigan', postalCode: 'bad' });
    expect((await validate(dto)).length).toBeGreaterThanOrEqual(3);
    await expect(fixture().service.create('owner', 'org-a', { ...input, timezone: 'Not/AZone' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('does not update a location from another organization', async () => {
    const { service, prisma } = fixture();
    prisma.restaurantLocation.findFirst.mockResolvedValue(null);
    await expect(service.update('owner', 'org-a', 'location-b', { name: 'No access' })).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.restaurantLocation.update).not.toHaveBeenCalled();
  });

  it('passes role enforcement through for managers and viewers', async () => {
    const { service, access, prisma } = fixture();
    access.requireMember.mockRejectedValue(new Error('forbidden'));
    await expect(service.create('manager', 'org-a', input)).rejects.toThrow('forbidden');
    expect(prisma.restaurantLocation.create).not.toHaveBeenCalled();
  });
});
