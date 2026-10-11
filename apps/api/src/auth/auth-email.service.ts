import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class AuthEmailService {
  constructor(private readonly config: ConfigService) {}

  get developmentMode() {
    return this.config.get<string>('AUTH_EMAIL_PROVIDER') === 'development' && this.config.get<string>('NODE_ENV') !== 'production';
  }

  assertConfigured() {
    if (this.developmentMode) return;
    const publicBaseUrl = this.config.get<string>('AUTH_PUBLIC_BASE_URL');
    if (this.config.get<string>('AUTH_EMAIL_PROVIDER') !== 'resend' || !this.config.get<string>('RESEND_API_KEY') || !this.config.get<string>('AUTH_FROM_EMAIL') || !publicBaseUrl) {
      throw new ServiceUnavailableException('Transactional email delivery is not configured');
    }
    try {
      const url = new URL(publicBaseUrl);
      if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) throw new Error();
    } catch {
      throw new ServiceUnavailableException('Transactional email public URL is invalid');
    }
  }

  async sendVerification(email: string, token: string) {
    await this.send(email, 'Verify your ProfitLens account', 'verify-email', token, 'This link expires in 24 hours. If you did not create this account, you can ignore this email.');
  }

  async sendPasswordReset(email: string, token: string) {
    await this.send(email, 'Reset your ProfitLens password', 'reset-password', token, 'This link expires in 30 minutes. If you did not request a reset, you can ignore this email.');
  }

  private async send(email: string, subject: string, path: string, token: string, note: string) {
    this.assertConfigured();
    if (this.developmentMode) return;
    const base = this.config.get<string>('AUTH_PUBLIC_BASE_URL')!.replace(/\/$/, '');
    const link = `${base}/${path}?token=${encodeURIComponent(token)}`;
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.config.get<string>('RESEND_API_KEY')}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: this.config.get<string>('AUTH_FROM_EMAIL'), to: [email], subject, html: `<p>${subject}</p><p><a href="${link}">${subject}</a></p><p>${note}</p>` }),
    });
    if (!response.ok) throw new ServiceUnavailableException('Transactional email could not be delivered');
  }
}
