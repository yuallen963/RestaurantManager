import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from './current-user.decorator';
import { AuthRateLimiter } from './auth-rate-limiter.service';
import { AuthService } from './auth.service';
import { AuthSecurityService } from './auth-security.service';
import { ChallengeIdDto, ChangePasswordDto, DeleteAccountDto, DisableMfaDto, EmailDto, EmailLoginVerificationDto, LoginChallengeDto, LoginDto, PasswordConfirmationDto, PrivateSessionDto, RefreshDto, RegisterDto, ResetPasswordDto, TokenDto, TotpCodeDto } from './dto';
import { JwtAuthGuard } from './jwt-auth.guard';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService, private readonly limiter: AuthRateLimiter, private readonly security: AuthSecurityService) {}
  private limit(req: any, action: string, identity = '', count = 10) { this.limiter.check(action, req.ip ?? 'unknown', identity, count); }

  @Post('register') register(@Req() req: any, @Body() dto: RegisterDto) { this.limit(req, 'register', dto.email, 5); return this.auth.register(dto); }
  @HttpCode(200) @Post('verify-email') verify(@Req() req: any, @Body() dto: TokenDto) { this.limit(req, 'verify'); return this.auth.verifyEmail(dto.token); }
  @HttpCode(200) @Post('resend-verification') resend(@Req() req: any, @Body() dto: EmailDto) { this.limit(req, 'resend', dto.email, 3); return this.auth.resendVerification(dto.email); }
  @HttpCode(200) @Post('login') login(@Req() req: any, @Body() dto: LoginDto) { this.limit(req, 'login', dto.email); return this.auth.login(dto.email, dto.password, dto); }
  @HttpCode(200) @Post('login-challenge') challenge(@Req() req: any, @Body() dto: LoginChallengeDto) { this.limit(req, 'login-challenge', dto.challengeId, 8); return this.auth.completeLoginChallenge(dto.challengeId, dto.code); }
  @HttpCode(200) @Post('login-challenge/resend') resendChallenge(@Req() req: any, @Body() dto: ChallengeIdDto) { this.limit(req, 'login-challenge-resend', dto.challengeId, 3); return this.security.resendEmailChallenge(dto.challengeId); }
  @HttpCode(200) @Post('shared-test-session') sharedTestSession(@Req() req: any) { this.limit(req, 'shared-test-session', '', 30); return this.auth.sharedTestSession(); }
  @HttpCode(200) @Post('private-session') privateSession(@Req() req: any, @Body() dto: PrivateSessionDto) { this.limit(req, 'private-session', '', 5); return this.auth.privateSession(dto.accessCode, dto); }
  @HttpCode(200) @Post('refresh') refresh(@Body() dto: RefreshDto) { return this.auth.refresh(dto.refreshToken); }
  @HttpCode(204) @Post('logout') async logout(@Body() dto: RefreshDto) { await this.auth.logout(dto.refreshToken); }
  @HttpCode(200) @Post('forgot-password') forgot(@Req() req: any, @Body() dto: EmailDto) { this.limit(req, 'forgot', dto.email, 3); return this.auth.forgotPassword(dto.email); }
  @HttpCode(200) @Post('reset-password') reset(@Req() req: any, @Body() dto: ResetPasswordDto) { this.limit(req, 'reset', '', 5); return this.auth.resetPassword(dto.token, dto.password); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @HttpCode(200) @Post('sign-out-all') signOutAll(@CurrentUser() user: { sub: string }) { return this.auth.signOutAll(user.sub); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @HttpCode(200) @Post('change-password') changePassword(@CurrentUser() user: { sub: string }, @Body() dto: ChangePasswordDto) { return this.auth.changePassword(user.sub, dto.currentPassword, dto.newPassword); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Get('security') securityStatus(@CurrentUser() user: { sub: string }) { return this.security.status(user.sub); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Patch('security/email-login-verification') emailLogin(@CurrentUser() user: { sub: string }, @Body() dto: EmailLoginVerificationDto) { return this.security.setEmailLoginVerification(user.sub, dto.enabled, dto.password); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Post('security/mfa/enroll') enrollMfa(@CurrentUser() user: { sub: string }, @Body() dto: PasswordConfirmationDto) { return this.security.beginTotpEnrollment(user.sub, dto.password); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Post('security/mfa/confirm') confirmMfa(@CurrentUser() user: { sub: string }, @Body() dto: TotpCodeDto) { return this.security.confirmTotpEnrollment(user.sub, dto.code); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Post('security/mfa/disable') disableMfa(@CurrentUser() user: { sub: string }, @Body() dto: DisableMfaDto) { return this.security.disableTotp(user.sub, dto.password, dto.code); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Post('security/mfa/recovery-codes') recoveryCodes(@CurrentUser() user: { sub: string }, @Body() dto: DisableMfaDto) { return this.security.regenerateRecoveryCodes(user.sub, dto.password, dto.code); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Get('sessions') sessions(@CurrentUser() user: { sub: string }) { return this.security.sessions(user.sub); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Delete('sessions/:id') revokeSession(@CurrentUser() user: { sub: string }, @Param('id') id: string) { return this.security.revokeSession(user.sub, id); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Get('devices') devices(@CurrentUser() user: { sub: string }) { return this.security.devices(user.sub); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Delete('devices/:id') revokeDevice(@CurrentUser() user: { sub: string }, @Param('id') id: string) { return this.security.revokeDevice(user.sub, id); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Delete('account') deleteAccount(@CurrentUser() user: { sub: string }, @Body() dto: DeleteAccountDto) { return this.auth.deleteAccount(user.sub, dto.password); }
  @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Get('me') me(@CurrentUser() user: { sub: string }) { return this.auth.profile(user.sub); }
}
