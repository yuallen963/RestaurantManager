import { Body, Controller, Delete, ForbiddenException, Get, HttpCode, Param, Post, Query, UseGuards } from '@nestjs/common';
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
  list(@CurrentUser() user: { sub: string; publicDemo?: boolean }, @Query('organizationId') organizationId?: string) {
    if (user.publicDemo === true) throw new ForbiddenException('Invitation identities are not available in the public demo');
    return this.invitations.list(user.sub, organizationId);
  }

  @HttpCode(204)
  @Delete(':id')
  revoke(@CurrentUser() user: { sub: string }, @Param('id') id: string) {
    return this.invitations.revoke(user.sub, id);
  }
}
