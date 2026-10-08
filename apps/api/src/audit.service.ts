import { Injectable } from '@nestjs/common';
import { PrismaService } from './prisma.service';
@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}
  log(input: { userId?: string; organizationId?: string; action: string; entityType: string; entityId?: string; metadata?: object }) { return this.prisma.auditLog.create({ data: input }); }
}
