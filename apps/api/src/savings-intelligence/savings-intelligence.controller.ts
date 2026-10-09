import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SavingsOpportunitiesQuery } from './dto';
import { SavingsIntelligenceService } from './savings-intelligence.service';

@ApiTags('savings-intelligence')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('savings-opportunities')
export class SavingsIntelligenceController {
  constructor(private readonly savings: SavingsIntelligenceService) {}

  @Get()
  get(@CurrentUser() user: { sub: string }, @Query() query: SavingsOpportunitiesQuery) {
    return this.savings.get(user.sub, query);
  }
}
