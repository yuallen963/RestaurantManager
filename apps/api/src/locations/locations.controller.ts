import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CreateLocationDto, UpdateLocationDto } from './dto';
import { LocationsService } from './locations.service';

@ApiTags('locations')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('organizations/:organizationId/locations')
export class LocationsController {
  constructor(private readonly service: LocationsService) {}

  @Get()
  list(@CurrentUser() user: { sub: string }, @Param('organizationId') organizationId: string) {
    return this.service.list(user.sub, organizationId);
  }

  @Post()
  create(@CurrentUser() user: { sub: string }, @Param('organizationId') organizationId: string, @Body() dto: CreateLocationDto) {
    return this.service.create(user.sub, organizationId, dto);
  }

  @Patch(':locationId')
  update(@CurrentUser() user: { sub: string }, @Param('organizationId') organizationId: string, @Param('locationId') locationId: string, @Body() dto: UpdateLocationDto) {
    return this.service.update(user.sub, organizationId, locationId, dto);
  }
}
