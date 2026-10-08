import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { PrismaService } from '../prisma.service';
@Module({ imports: [JwtModule.register({})], controllers: [AuthController], providers: [PrismaService, AuthService, JwtAuthGuard], exports: [JwtModule, JwtAuthGuard] })
export class AuthModule {}
