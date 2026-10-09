import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AuthModule } from '../auth/auth.module';
import { OrganizationsModule } from '../organizations/organizations.module';
import { PrismaService } from '../prisma.service';
import { SavingsIntelligenceController } from './savings-intelligence.controller';
import { SavingsIntelligenceService } from './savings-intelligence.service';

@Module({
  imports: [AuthModule, OrganizationsModule, ConfigModule],
  controllers: [SavingsIntelligenceController],
  providers: [SavingsIntelligenceService, PrismaService],
})
export class SavingsIntelligenceModule {}
