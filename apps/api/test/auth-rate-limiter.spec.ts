import { HttpException, HttpStatus } from '@nestjs/common';
import { AuthRateLimiter } from '../src/auth/auth-rate-limiter.service';

describe('AuthRateLimiter', () => {
  it('normalizes identities and rejects requests beyond the configured limit', () => {
    const limiter = new AuthRateLimiter();
    limiter.check('forgot', '127.0.0.1', ' Owner@Example.COM ', 2);
    limiter.check('forgot', '127.0.0.1', 'owner@example.com', 2);
    try {
      limiter.check('forgot', '127.0.0.1', 'OWNER@example.com', 2);
      throw new Error('Expected rate limiting');
    } catch (error) {
      expect(error).toBeInstanceOf(HttpException);
      expect((error as HttpException).getStatus()).toBe(
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  });

  it('keeps rate-limit buckets isolated by action and client', () => {
    const limiter = new AuthRateLimiter();
    limiter.check('forgot', '127.0.0.1', 'owner@example.com', 1);
    expect(() =>
      limiter.check('login', '127.0.0.1', 'owner@example.com', 1),
    ).not.toThrow();
    expect(() =>
      limiter.check('forgot', '127.0.0.2', 'owner@example.com', 1),
    ).not.toThrow();
  });
});
