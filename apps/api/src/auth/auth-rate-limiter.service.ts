import { HttpException, HttpStatus, Injectable } from '@nestjs/common';

@Injectable()
export class AuthRateLimiter {
  private readonly attempts = new Map<string, number[]>();

  check(action: string, ip: string, identity = '', limit = 10, windowMs = 15 * 60 * 1000) {
    const now = Date.now();
    const key = `${action}:${ip}:${identity.trim().toLowerCase()}`;
    const recent = (this.attempts.get(key) ?? []).filter((value) => value > now - windowMs);
    if (recent.length >= limit) throw new HttpException('Too many attempts. Try again later.', HttpStatus.TOO_MANY_REQUESTS);
    recent.push(now);
    this.attempts.set(key, recent);
  }
}
