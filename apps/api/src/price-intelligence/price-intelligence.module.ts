import { Module } from '@nestjs/common';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PrismaService } from '../prisma.service';
import { PriceIntelligenceController } from './price-intelligence.controller';
import { PriceIntelligenceService } from './price-intelligence.service';

@Module({
  controllers: [PriceIntelligenceController],
  providers: [PriceIntelligenceService, PrismaService, OrganizationAccessService],
})
export class PriceIntelligenceModule {}
