import { IsEmail, IsOptional, IsString, MinLength } from 'class-validator';
export class RegisterDto { @IsEmail() email!: string; @IsString() @MinLength(12) password!: string; @IsOptional() @IsString() firstName?: string; @IsOptional() @IsString() lastName?: string; }
export class LoginDto { @IsEmail() email!: string; @IsString() password!: string; }
export class RefreshDto { @IsString() refreshToken!: string; }
export class EmailDto { @IsEmail() email!: string; }
export class TokenDto { @IsString() @MinLength(32) token!: string; }
export class ResetPasswordDto extends TokenDto { @IsString() @MinLength(12) password!: string; }
export class DeleteAccountDto { @IsString() password!: string; }
