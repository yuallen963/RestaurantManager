import { ServiceUnavailableException } from '@nestjs/common';
import { AuthEmailService } from '../src/auth/auth-email.service';

describe('AuthEmailService', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });

  const service = (values: Record<string, string | undefined>) =>
    new AuthEmailService({ get: (key: string) => values[key] } as any);

  it('fails safely when production email configuration is incomplete', () => {
    const email = service({ NODE_ENV: 'production', AUTH_EMAIL_PROVIDER: 'resend' });
    expect(() => email.assertConfigured()).toThrow(ServiceUnavailableException);
  });

  it('allows the isolated development provider only outside production', async () => {
    const email = service({ NODE_ENV: 'test', AUTH_EMAIL_PROVIDER: 'development' });
    const fetch = jest.fn();
    global.fetch = fetch as any;
    expect(email.developmentMode).toBe(true);
    await email.sendVerification('owner@example.com', 'verification-token');
    expect(fetch).not.toHaveBeenCalled();
  });

  it('generates production-safe verification and reset links through Resend', async () => {
    const fetch = jest.fn().mockResolvedValue({ ok: true });
    global.fetch = fetch as any;
    const email = service({
      NODE_ENV: 'production',
      AUTH_EMAIL_PROVIDER: 'resend',
      RESEND_API_KEY: 'secret',
      AUTH_FROM_EMAIL: 'FundWell <auth@example.com>',
      AUTH_PUBLIC_BASE_URL: 'https://app.example.com/',
    });

    await email.sendVerification('owner@example.com', 'verify/value');
    await email.sendPasswordReset('owner@example.com', 'reset/value');

    const verification = JSON.parse(fetch.mock.calls[0][1].body);
    const reset = JSON.parse(fetch.mock.calls[1][1].body);
    expect(verification.html).toContain('https://app.example.com/verify-email?token=verify%2Fvalue');
    expect(reset.html).toContain('https://app.example.com/reset-password?token=reset%2Fvalue');
    expect(fetch.mock.calls[0][1].headers.Authorization).toBe('Bearer secret');
  });

  it('contains provider failures without exposing credentials', async () => {
    global.fetch = jest.fn().mockResolvedValue({ ok: false }) as any;
    const email = service({
      NODE_ENV: 'production',
      AUTH_EMAIL_PROVIDER: 'resend',
      RESEND_API_KEY: 'secret',
      AUTH_FROM_EMAIL: 'FundWell <auth@example.com>',
      AUTH_PUBLIC_BASE_URL: 'https://app.example.com',
    });
    await expect(
      email.sendVerification('owner@example.com', 'token'),
    ).rejects.toThrow('Transactional email could not be delivered');
  });
});
