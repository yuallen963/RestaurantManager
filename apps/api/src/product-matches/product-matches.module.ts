import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { OrganizationsModule } from '../organizations/organizations.module';
import { AuditService } from '../audit.service';
import { PrismaService } from '../prisma.service';
import { ProductMatchesController } from './product-matches.controller';
import { ProductMatchesService } from './product-matches.service';

@Module({
  imports: [AuthModule, OrganizationsModule],
  controllers: [ProductMatchesController],
  providers: [ProductMatchesService, PrismaService, AuditService],
})
export class ProductMatchesModule {}
