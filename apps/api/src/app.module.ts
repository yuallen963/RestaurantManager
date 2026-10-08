import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AuthModule } from './auth/auth.module';
import { OrganizationsModule } from './organizations/organizations.module';
import { LocationsModule } from './locations/locations.module';
import { PrismaService } from './prisma.service';
import { AuditService } from './audit.service';
import { DashboardModule } from './dashboard/dashboard.module';
import { FinanceModule } from './finance/finance.module';
import { InvoicesModule } from './invoices/invoices.module';
import { PriceIntelligenceModule } from './price-intelligence/price-intelligence.module';
@Module({ imports: [ConfigModule.forRoot({ isGlobal: true }), AuthModule, OrganizationsModule, LocationsModule, DashboardModule, FinanceModule, InvoicesModule, PriceIntelligenceModule], providers: [PrismaService, AuditService] })
export class AppModule {}
