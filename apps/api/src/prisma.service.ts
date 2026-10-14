import { INestApplication, Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { pooledDatabaseUrl } from './database-url';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor() {
    const url = pooledDatabaseUrl();
    super(url ? { datasources: { db: { url } } } : {});
  }

  async onModuleInit() { await this.$connect(); }
  async onModuleDestroy() { await this.$disconnect(); }
  async enableShutdownHooks(app: INestApplication) { this.$on('beforeExit' as never, async () => app.close()); }
}
