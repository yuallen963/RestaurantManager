import { Injectable, Logger } from '@nestjs/common';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
@Injectable()
export class FcmService {
  private readonly logger = new Logger(FcmService.name); private ready = false;
  private configured() { if (this.ready) return true; const encoded = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64; if (!encoded) return false; try { if (!getApps().length) initializeApp({ credential: cert(JSON.parse(Buffer.from(encoded, 'base64').toString('utf8'))) }); this.ready = true; return true; } catch { this.logger.warn('FCM is not configured correctly'); return false; } }
  async send(tokens: string[], payload: { title: string; body: string; data: Record<string, string> }) { if (!tokens.length || !this.configured()) return { sent: false, invalid: [] as string[] }; try { const result = await getMessaging().sendEachForMulticast({ tokens, notification: { title: payload.title, body: payload.body }, data: payload.data }); return { sent: result.successCount > 0, invalid: result.responses.flatMap((response, index) => !response.success && ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(response.error?.code ?? '') ? [tokens[index]] : []) }; } catch { this.logger.warn('FCM delivery failed'); return { sent: false, invalid: [] as string[] }; } }
}
