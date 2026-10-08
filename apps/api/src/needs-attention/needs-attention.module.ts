import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { DashboardModule } from '../dashboard/dashboard.module';
import { OrganizationsModule } from '../organizations/organizations.module';
import { PriceIntelligenceModule } from '../price-intelligence/price-intelligence.module';
import { PrismaService } from '../prisma.service';
import { NeedsAttentionController } from './needs-attention.controller';
import { NeedsAttentionService } from './needs-attention.service';

@Module({
  imports: [AuthModule, OrganizationsModule, DashboardModule, PriceIntelligenceModule],
  controllers: [NeedsAttentionController],
  providers: [NeedsAttentionService, PrismaService],
})
export class NeedsAttentionModule {}
