import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { OrganizationsModule } from '../organizations/organizations.module';
import { PrismaService } from '../prisma.service';
import { PriceIntelligenceController } from './price-intelligence.controller';
import { PriceIntelligenceService } from './price-intelligence.service';

@Module({
  imports: [AuthModule, OrganizationsModule],
  controllers: [PriceIntelligenceController],
  providers: [PriceIntelligenceService, PrismaService],
})
export class PriceIntelligenceModule {}
