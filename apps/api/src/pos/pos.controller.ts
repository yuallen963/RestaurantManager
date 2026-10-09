import { Body, Controller, Delete, Get, Headers, HttpCode, Param, Patch, Post, Query, Req, Res, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { PosMapLocationDto, PosOrganizationDto, ResolveRevenueConflictDto } from './dto';
import { PosService } from './pos.service';

@ApiTags('pos-integrations')
@Controller('pos')
export class PosController {
  constructor(private readonly service: PosService) {}

  @ApiBearerAuth() @UseGuards(JwtAuthGuard)
  @Post('square/authorize') authorize(@CurrentUser() user: { sub: string }, @Body() dto: PosOrganizationDto) { return this.service.authorization(user.sub, dto.organizationId); }

  @Get('square/callback')
  async callback(@Query('code') code: string | undefined, @Query('state') state: string | undefined, @Query('error') error: string | undefined, @Res() response: any) {
    const result = await this.service.callback(code, state, error);
    const destination = process.env.POS_OAUTH_SUCCESS_REDIRECT;
    if (destination) return response.redirect(`${destination}${destination.includes('?') ? '&' : '?'}square=connected`);
    return response.status(200).json(result);
  }

  @ApiBearerAuth() @UseGuards(JwtAuthGuard)
  @Get('connections') connections(@CurrentUser() user: { sub: string }, @Query('organizationId') organizationId: string) { return this.service.list(user.sub, organizationId); }

  @ApiBearerAuth() @UseGuards(JwtAuthGuard)
  @Get('connections/:id/locations') locations(@CurrentUser() user: { sub: string }, @Param('id') id: string) { return this.service.providerLocations(user.sub, id); }

  @ApiBearerAuth() @UseGuards(JwtAuthGuard)
  @Post('connections/:id/mappings') map(@CurrentUser() user: { sub: string }, @Param('id') id: string, @Body() dto: PosMapLocationDto) { return this.service.map(user.sub, id, dto); }

  @ApiBearerAuth() @UseGuards(JwtAuthGuard)
  @Post('connections/:id/sync') sync(@CurrentUser() user: { sub: string }, @Param('id') id: string) { return this.service.sync(user.sub, id); }

  @ApiBearerAuth() @UseGuards(JwtAuthGuard)
  @Patch('revenue-conflicts/:id') resolve(@CurrentUser() user: { sub: string }, @Param('id') id: string, @Body() dto: ResolveRevenueConflictDto) { return this.service.resolveConflict(user.sub, id, dto.resolution); }

  @ApiBearerAuth() @UseGuards(JwtAuthGuard)
  @HttpCode(204) @Delete('connections/:id') disconnect(@CurrentUser() user: { sub: string }, @Param('id') id: string) { return this.service.disconnect(user.sub, id); }

  @HttpCode(200) @Post('square/webhook')
  webhook(@Headers('x-square-hmacsha256-signature') signature: string | undefined, @Req() request: any, @Body() body: any) { return this.service.webhook(signature, request.rawBody ?? Buffer.from(JSON.stringify(body)), body); }
}
