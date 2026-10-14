import { MODULE_METADATA } from '@nestjs/common/constants';
import { PrismaModule } from './prisma.module';
import { PrismaService } from './prisma.service';
import { AppModule } from './app.module';
import { AuthModule } from './auth/auth.module';
import { BankModule } from './bank/bank.module';
import { DashboardModule } from './dashboard/dashboard.module';
import { FinanceModule } from './finance/finance.module';
import { InvoicesModule } from './invoices/invoices.module';
import { LocationsModule } from './locations/locations.module';
import { NeedsAttentionModule } from './needs-attention/needs-attention.module';
import { NotificationsModule } from './notifications/notifications.module';
import { OnboardingModule } from './onboarding/onboarding.module';
import { OrganizationsModule } from './organizations/organizations.module';
import { PosModule } from './pos/pos.module';
import { PriceIntelligenceModule } from './price-intelligence/price-intelligence.module';
import { ProductMatchesModule } from './product-matches/product-matches.module';
import { SavingsIntelligenceModule } from './savings-intelligence/savings-intelligence.module';

describe('PrismaModule', () => {
  it('is imported once by the root module and is the only PrismaService provider', () => {
    const appImports = Reflect.getMetadata(MODULE_METADATA.IMPORTS, AppModule) ?? [];
    expect(appImports).toContain(PrismaModule);

    const featureModules = [
      AppModule,
      AuthModule,
      BankModule,
      DashboardModule,
      FinanceModule,
      InvoicesModule,
      LocationsModule,
      NeedsAttentionModule,
      NotificationsModule,
      OnboardingModule,
      OrganizationsModule,
      PosModule,
      PriceIntelligenceModule,
      ProductMatchesModule,
      SavingsIntelligenceModule,
    ];
    for (const module of featureModules) {
      const providers = Reflect.getMetadata(MODULE_METADATA.PROVIDERS, module) ?? [];
      expect(providers).not.toContain(PrismaService);
    }

    expect(Reflect.getMetadata(MODULE_METADATA.PROVIDERS, PrismaModule)).toEqual([
      PrismaService,
    ]);
  });
});
