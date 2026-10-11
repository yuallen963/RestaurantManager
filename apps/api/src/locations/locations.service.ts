import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { OrganizationRole } from '@prisma/client';
import { randomBytes } from 'crypto';
import { AuditService } from '../audit.service';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PrismaService } from '../prisma.service';
import { CreateLocationDto, UpdateLocationDto } from './dto';

const managementRoles = [OrganizationRole.OWNER, OrganizationRole.ADMIN];

@Injectable()
export class LocationsService {
  constructor(private readonly prisma: PrismaService, private readonly access: OrganizationAccessService, private readonly audit: AuditService) {}

  async list(userId: string, organizationId: string) {
    await this.access.requireMember(userId, organizationId);
    return this.prisma.restaurantLocation.findMany({ where: { organizationId }, orderBy: { createdAt: 'asc' } });
  }

  async create(userId: string, organizationId: string, dto: CreateLocationDto) {
    await this.access.requireMember(userId, organizationId, managementRoles);
    this.validateTimezone(dto.timezone);
    const location = await this.prisma.restaurantLocation.create({ data: { organizationId, invoiceEmailToken: randomBytes(16).toString('hex'), ...this.clean(dto) } });
    await this.audit.log({ userId, organizationId, action: 'location.created', entityType: 'RestaurantLocation', entityId: location.id });
    return location;
  }

  async update(userId: string, organizationId: string, locationId: string, dto: UpdateLocationDto) {
    await this.access.requireMember(userId, organizationId, managementRoles);
    const existing = await this.prisma.restaurantLocation.findFirst({ where: { id: locationId, organizationId } });
    if (!existing) throw new NotFoundException('Location not found');
    if (dto.timezone != null) this.validateTimezone(dto.timezone);
    const location = await this.prisma.restaurantLocation.update({ where: { id: locationId }, data: this.clean(dto) });
    await this.audit.log({ userId, organizationId, action: 'location.updated', entityType: 'RestaurantLocation', entityId: location.id });
    return location;
  }

  private clean<T extends CreateLocationDto | UpdateLocationDto>(dto: T): T {
    return Object.fromEntries(Object.entries(dto).map(([key, value]) => [key, typeof value === 'string' ? value.trim() : value])) as T;
  }

  private validateTimezone(timezone: string) {
    try {
      new Intl.DateTimeFormat('en-US', { timeZone: timezone }).format();
    } catch {
      throw new BadRequestException('timezone must be a valid IANA time zone');
    }
  }
}
