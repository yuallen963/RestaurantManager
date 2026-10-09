import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PosService } from './pos.service';

@Injectable()
export class PosSyncScheduler implements OnModuleInit, OnModuleDestroy {
  private timer?: NodeJS.Timeout;
  constructor(private readonly service: PosService) {}
  onModuleInit() {
    if (!process.env.SQUARE_APPLICATION_ID) return;
    const hours = Math.max(Number(process.env.POS_SYNC_INTERVAL_HOURS ?? 24), 1);
    this.timer = setInterval(() => void this.service.syncAll().catch(() => undefined), hours * 60 * 60 * 1000);
    this.timer.unref();
  }
  onModuleDestroy() { if (this.timer) clearInterval(this.timer); }
}
