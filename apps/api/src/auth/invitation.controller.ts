import { Body, Controller, Delete, Get, HttpCode, Param, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from './current-user.decorator';
import { CreateBetaInvitationDto } from './invitation.dto';
import { InvitationService } from './invitation.service';
import { JwtAuthGuard } from './jwt-auth.guard';

@ApiTags('beta-invitations')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('beta-invitations')
export class InvitationController {
  constructor(private readonly invitations: InvitationService) {}

  @Post()
  create(@CurrentUser() user: { sub: string }, @Body() dto: CreateBetaInvitationDto) {
    return this.invitations.create(user.sub, dto);
  }

  @Get()
  list(@CurrentUser() user: { sub: string }, @Query('organizationId') organizationId?: string) {
    return this.invitations.list(user.sub, organizationId);
  }

  @HttpCode(204)
  @Delete(':id')
  revoke(@CurrentUser() user: { sub: string }, @Param('id') id: string) {
    return this.invitations.revoke(user.sub, id);
  }
}
