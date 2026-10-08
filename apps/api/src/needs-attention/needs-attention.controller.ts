import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { NeedsAttentionQuery } from './dto';
import { NeedsAttentionService } from './needs-attention.service';

@ApiTags('needs-attention')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('needs-attention')
export class NeedsAttentionController {
  constructor(private readonly needsAttention: NeedsAttentionService) {}

  @Get()
  get(@CurrentUser() user: { sub: string }, @Query() query: NeedsAttentionQuery) {
    return this.needsAttention.get(user.sub, query);
  }
}
