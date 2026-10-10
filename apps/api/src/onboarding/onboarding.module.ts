import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PrismaService } from '../prisma.service';
import { OnboardingController } from './onboarding.controller';
import { OnboardingService } from './onboarding.service';

@Module({ imports: [AuthModule], controllers: [OnboardingController], providers: [PrismaService, OnboardingService], exports: [OnboardingService] })
export class OnboardingModule {}
