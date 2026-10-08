import { IsEmail, IsOptional, IsString, MinLength } from 'class-validator';
export class RegisterDto { @IsEmail() email!: string; @IsString() @MinLength(12) password!: string; @IsOptional() @IsString() firstName?: string; @IsOptional() @IsString() lastName?: string; }
export class LoginDto { @IsEmail() email!: string; @IsString() password!: string; }
export class RefreshDto { @IsString() refreshToken!: string; }
