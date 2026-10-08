import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { OrganizationsModule } from '../organizations/organizations.module';
import { PrismaService } from '../prisma.service';
import { DashboardController } from './dashboard.controller';
import { DashboardService } from './dashboard.service';
@Module({ imports: [AuthModule, OrganizationsModule], controllers: [DashboardController], providers: [PrismaService, DashboardService] }) export class DashboardModule {}
