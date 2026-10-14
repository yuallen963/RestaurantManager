import { Module } from '@nestjs/common';
import { AuditService } from '../audit.service';
import { AuthModule } from '../auth/auth.module';
import { BankTokenEncryptionService } from '../bank/encryption.service';
import { OrganizationsModule } from '../organizations/organizations.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PosController } from './pos.controller';
import { PosService } from './pos.service';
import { SquareProvider } from './square.provider';
import { PosSyncScheduler } from './pos-sync.scheduler';

@Module({ imports: [AuthModule, OrganizationsModule, NotificationsModule], controllers: [PosController], providers: [AuditService, BankTokenEncryptionService, SquareProvider, PosService, PosSyncScheduler], exports: [PosService] })
export class PosModule {}
