import { Body, Controller, Delete, ForbiddenException, Get, HttpCode, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AddMemberDto, CreateOrganizationDto, UpdateMemberRoleDto } from './dto';
import { OrganizationsService } from './organizations.service';

@ApiTags('organizations')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('organizations')
export class OrganizationsController {
  constructor(private readonly service: OrganizationsService) {}
  @Get() list(@CurrentUser() user: { sub: string }) { return this.service.list(user.sub); }
  @Post() create(@CurrentUser() user: { sub: string }, @Body() dto: CreateOrganizationDto) { return this.service.create(user.sub, dto.name); }
  @Get(':id') get(@CurrentUser() user: { sub: string }, @Param('id') id: string) { return this.service.get(user.sub, id); }
  @Get(':id/members') members(@CurrentUser() user: { sub: string; publicDemo?: boolean }, @Param('id') id: string) {
    if (user.publicDemo === true) throw new ForbiddenException('Team identities are not available in the public demo');
    return this.service.members(user.sub, id);
  }
  @Post(':id/members') addMember(@CurrentUser() user: { sub: string }, @Param('id') id: string, @Body() dto: AddMemberDto) { return this.service.addMember(user.sub, id, dto.userId, dto.role); }
  @Patch(':id/members/:memberId') updateMember(@CurrentUser() user: { sub: string }, @Param('id') id: string, @Param('memberId') memberId: string, @Body() dto: UpdateMemberRoleDto) { return this.service.updateMemberRole(user.sub, id, memberId, dto.role); }
  @HttpCode(204)
  @Delete(':id/members/:memberId') removeMember(@CurrentUser() user: { sub: string }, @Param('id') id: string, @Param('memberId') memberId: string) { return this.service.removeMember(user.sub, id, memberId); }
}
