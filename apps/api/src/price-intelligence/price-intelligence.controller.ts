import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { PriceHistoryQuery, PriceIntelligenceQuery } from './dto';
import { PriceIntelligenceService } from './price-intelligence.service';

@ApiTags('price-intelligence')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('price-intelligence')
export class PriceIntelligenceController {
  constructor(private readonly prices: PriceIntelligenceService) {}

  @Get('changes')
  changes(@CurrentUser() user: { sub: string }, @Query() query: PriceIntelligenceQuery) {
    return this.prices.changes(user.sub, query);
  }

  @Get('items/:itemKey/history')
  history(@CurrentUser() user: { sub: string }, @Param('itemKey') itemKey: string, @Query() query: PriceHistoryQuery) {
    return this.prices.history(user.sub, itemKey, query);
  }
}
