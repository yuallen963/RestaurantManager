import { Body, Controller, Delete, Get, HttpCode, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from './current-user.decorator';
import { AuthRateLimiter } from './auth-rate-limiter.service';
import { AuthService } from './auth.service';
import { DeleteAccountDto, EmailDto, LoginDto, RefreshDto, RegisterDto, ResetPasswordDto, TokenDto } from './dto';
import { JwtAuthGuard } from './jwt-auth.guard';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService, private readonly limiter: AuthRateLimiter) {}
  private limit(req: any, action: string, identity = '', count = 10) { this.limiter.check(action, req.ip ?? 'unknown', identity, count); }

  @Post('register') register(@Req() req: any, @Body() dto: RegisterDto) { this.limit(req, 'register', dto.email, 5); return this.auth.register(dto); }
  @HttpCode(200) @Post('verify-email') verify(@Req() req: any, @Body() dto: TokenDto) { this.limit(req, 'verify'); return this.auth.verifyEmail(dto.token); }
  @HttpCode(200) @Post('resend-verification') resend(@Req() req: any, @Body() dto: EmailDto) { this.limit(req, 'resend', dto.email, 3); return this.auth.resendVerification(dto.email); }
  @HttpCode(200) @Post('login') login(@Req() req: any, @Body() dto: LoginDto) { this.limit(req, 'login', dto.email); return this.auth.login(dto.email, dto.password); }
  @HttpCode(200) @Post('refresh') refresh(@Body() dto: RefreshDto) { return this.auth.refresh(dto.refreshToken); }
  @HttpCode(204) @Post('logout') async logout(@Body() dto: RefreshDto) { await this.auth.logout(dto.refreshToken); }
  @HttpCode(200) @Post('forgot-password') forgot(@Req() req: any, @Body() dto: EmailDto) { this.limit(req, 'forgot', dto.email, 3); return this.auth.forgotPassword(dto.email); }
  @HttpCode(200) @Post('reset-password') reset(@Req() req: any, @Body() dto: ResetPasswordDto) { this.limit(req, 'reset', '', 5); return this.auth.resetPassword(dto.token, dto.password); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @HttpCode(200) @Post('sign-out-all') signOutAll(@CurrentUser() user: { sub: string }) { return this.auth.signOutAll(user.sub); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Delete('account') deleteAccount(@CurrentUser() user: { sub: string }, @Body() dto: DeleteAccountDto) { return this.auth.deleteAccount(user.sub, dto.password); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Get('me') me(@CurrentUser() user: { sub: string }) { return this.auth.profile(user.sub); }
}
