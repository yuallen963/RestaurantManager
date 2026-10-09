import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ProductMatchQuery, RenameProductGroupDto } from './dto';
import { ProductMatchesService } from './product-matches.service';

@ApiTags('product-matches')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class ProductMatchesController {
  constructor(private readonly matches: ProductMatchesService) {}

  @Get('product-matches/candidates')
  candidates(@CurrentUser() user: { sub: string }, @Query() query: ProductMatchQuery) {
    return this.matches.candidates(user.sub, query.restaurantLocationId);
  }

  @Post('product-matches/:id/confirm')
  confirm(@CurrentUser() user: { sub: string }, @Param('id') id: string) {
    return this.matches.confirm(user.sub, id);
  }

  @Post('product-matches/:id/reject')
  reject(@CurrentUser() user: { sub: string }, @Param('id') id: string) {
    return this.matches.reject(user.sub, id);
  }

  @Get('product-groups')
  groups(@CurrentUser() user: { sub: string }, @Query() query: ProductMatchQuery) {
    return this.matches.groups(user.sub, query.restaurantLocationId);
  }

  @Get('product-groups/:id')
  group(@CurrentUser() user: { sub: string }, @Param('id') id: string) {
    return this.matches.group(user.sub, id);
  }

  @Patch('product-groups/:id')
  rename(@CurrentUser() user: { sub: string }, @Param('id') id: string, @Body() body: RenameProductGroupDto) {
    return this.matches.rename(user.sub, id, body.displayName);
  }
}
