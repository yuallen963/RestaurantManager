import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { AuditService } from '../audit.service';
import { AuthEmailService } from './auth-email.service';
import { AuthRateLimiter } from './auth-rate-limiter.service';
import { AuthSecurityService } from './auth-security.service';
@Module({ imports: [JwtModule.register({})], controllers: [AuthController], providers: [AuditService, AuthEmailService, AuthRateLimiter, AuthSecurityService, AuthService, JwtAuthGuard], exports: [JwtModule, JwtAuthGuard] })
export class AuthModule {}
