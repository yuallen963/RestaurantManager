import { Module } from '@nestjs/common';
import { AuditService } from '../audit.service';
import { AuthModule } from '../auth/auth.module';
import { OrganizationsModule } from '../organizations/organizations.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PrismaService } from '../prisma.service';
import { BankController } from './bank.controller';
import { BankProviderFactory } from './bank.provider';
import { BankService } from './bank.service';
import { BankTokenEncryptionService } from './encryption.service';

@Module({ imports: [AuthModule, OrganizationsModule, NotificationsModule], controllers: [BankController], providers: [PrismaService, AuditService, BankProviderFactory, BankTokenEncryptionService, BankService], exports: [BankService] })
export class BankModule {}
