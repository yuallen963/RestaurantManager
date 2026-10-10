import { Body, Controller, Get, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SetupRestaurantDto, UpdateOnboardingDto } from './dto';
import { OnboardingService } from './onboarding.service';

@ApiTags('onboarding') @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Controller('onboarding')
export class OnboardingController {
  constructor(private readonly service: OnboardingService) {}
  @Get() get(@CurrentUser() user: { sub: string }) { return this.service.get(user.sub); }
  @Patch('progress') update(@CurrentUser() user: { sub: string }, @Body() dto: UpdateOnboardingDto) { return this.service.update(user.sub, dto); }
  @Post('setup') setup(@CurrentUser() user: { sub: string }, @Body() dto: SetupRestaurantDto) { return this.service.setup(user.sub, dto); }
  @Post('complete') complete(@CurrentUser() user: { sub: string }) { return this.service.complete(user.sub); }
}
