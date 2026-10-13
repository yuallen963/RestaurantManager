import { IsBoolean, IsEmail, IsOptional, IsString, IsUUID, Length, MinLength } from 'class-validator';
export class RegisterDto { @IsEmail() email!: string; @IsString() @MinLength(12) password!: string; @IsOptional() @IsString() firstName?: string; @IsOptional() @IsString() lastName?: string; }
export class LoginDto { @IsEmail() email!: string; @IsString() password!: string; @IsOptional() @IsString() deviceId?: string; @IsOptional() @IsString() deviceName?: string; }
export class RefreshDto { @IsString() refreshToken!: string; }
export class EmailDto { @IsEmail() email!: string; }
export class TokenDto { @IsString() @MinLength(32) token!: string; }
export class ResetPasswordDto extends TokenDto { @IsString() @MinLength(12) password!: string; }
export class DeleteAccountDto { @IsString() password!: string; }
export class PrivateSessionDto { @IsString() @MinLength(1) accessCode!: string; @IsOptional() @IsString() deviceId?: string; @IsOptional() @IsString() deviceName?: string; }
export class LoginChallengeDto { @IsUUID() challengeId!: string; @IsString() @MinLength(6) code!: string; }
export class ChallengeIdDto { @IsUUID() challengeId!: string; }
export class PasswordConfirmationDto { @IsString() password!: string; }
export class ChangePasswordDto { @IsString() currentPassword!: string; @IsString() @MinLength(12) newPassword!: string; }
export class EmailLoginVerificationDto extends PasswordConfirmationDto { @IsBoolean() enabled!: boolean; }
export class TotpCodeDto { @IsString() @Length(6, 32) code!: string; }
export class DisableMfaDto extends PasswordConfirmationDto { @IsString() @Length(6, 32) code!: string; }
