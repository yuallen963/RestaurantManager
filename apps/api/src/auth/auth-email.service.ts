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
    await this.sendLink(email, 'Verify your FundWell email address', 'verify-email', token, 'Verify email address', 'This link expires in 24 hours. If you did not create this account, you can ignore this email.');
  }

  async sendPasswordReset(email: string, token: string) {
    await this.sendLink(email, 'Reset your FundWell password', 'reset-password', token, 'Reset password', 'This link expires in 30 minutes. If you did not request a reset, secure your account from FundWell.');
  }

  async sendBetaInvitation(email: string, token: string) {
    this.assertConfigured();
    if (this.developmentMode) return;
    const base = this.config.get<string>('AUTH_PUBLIC_BASE_URL')!.replace(/\/$/, '');
    const link = `${base}/register?invite=${encodeURIComponent(token)}&email=${encodeURIComponent(email)}`;
    await this.deliver(
      email,
      'You are invited to FundWell',
      `<p>You have been invited to create a private FundWell account.</p><p><a style="background:#5b3fb5;color:white;padding:12px 18px;border-radius:8px;text-decoration:none" href="${link}">Accept invitation</a></p><p>This invitation is bound to this email address, expires automatically, and can be used once.</p>`,
    );
  }

  async sendLoginCode(email: string, code: string) {
    await this.sendMessage(email, 'Your FundWell sign-in code', `<p style="font-size:16px">Enter this code to finish signing in:</p><p style="font-size:30px;font-weight:700;letter-spacing:6px">${code}</p><p>This code expires in 5 minutes and can be used once. FundWell will never ask you to share it.</p>`);
  }

  async sendWelcome(email: string) { await this.sendMessage(email, 'Welcome to FundWell', '<p>Your email is verified and your FundWell account is ready.</p>'); }
  async sendPasswordChanged(email: string) { await this.sendMessage(email, 'Your FundWell password was changed', '<p>Your password was changed and existing sessions were signed out. If this was not you, reset your password immediately.</p>'); }
  async sendNewDeviceLogin(email: string, context: string) { await this.sendMessage(email, 'New sign-in to your FundWell account', `<p>A new device signed in to FundWell.</p><p>${this.escape(context)}</p><p>If this was not you, open Account Security and revoke the session.</p>`); }
  async sendSecurityNotice(email: string, subject: string, detail: string) { await this.sendMessage(email, subject, `<p>${this.escape(detail)}</p><p>If this was not you, open FundWell Account Security immediately.</p>`); }

  private async sendLink(email: string, subject: string, path: string, token: string, label: string, note: string) {
    this.assertConfigured();
    if (this.developmentMode) return;
    const base = this.config.get<string>('AUTH_PUBLIC_BASE_URL')!.replace(/\/$/, '');
    const link = `${base}/${path}?token=${encodeURIComponent(token)}`;
    await this.deliver(email, subject, `<p><a style="background:#5b3fb5;color:white;padding:12px 18px;border-radius:8px;text-decoration:none" href="${link}">${label}</a></p><p>${note}</p>`);
  }

  private async sendMessage(email: string, subject: string, content: string) {
    this.assertConfigured();
    if (this.developmentMode) return;
    await this.deliver(email, subject, content);
  }

  private async deliver(email: string, subject: string, content: string) {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.config.get<string>('RESEND_API_KEY')}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: this.config.get<string>('AUTH_FROM_EMAIL'), to: [email], subject, html: `<!doctype html><html><body style="margin:0;background:#f7f5fb;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;color:#241f2d"><div style="max-width:560px;margin:auto;padding:28px"><h1 style="color:#5b3fb5">FundWell</h1><h2>${this.escape(subject)}</h2>${content}<p style="font-size:12px;color:#6f6878;margin-top:28px">This is a transactional account-security email. It contains no financial details.</p></div></body></html>` }),
    });
    if (!response.ok) throw new ServiceUnavailableException('Transactional email could not be delivered');
  }

  private escape(value: string) { return value.replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character]!); }
}
