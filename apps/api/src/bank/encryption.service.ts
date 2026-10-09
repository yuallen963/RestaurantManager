import { Injectable, InternalServerErrorException } from '@nestjs/common';
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

@Injectable()
export class BankTokenEncryptionService {
  private key(): Buffer {
    const configured = process.env.BANK_TOKEN_ENCRYPTION_KEY;
    if (!configured) throw new InternalServerErrorException('Bank token encryption is not configured');
    const key = Buffer.from(configured, 'base64');
    if (key.length !== 32) throw new InternalServerErrorException('BANK_TOKEN_ENCRYPTION_KEY must be a base64-encoded 32-byte key');
    return key;
  }
  encrypt(value: string) {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key(), iv);
    const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    return ['v1', iv.toString('base64url'), cipher.getAuthTag().toString('base64url'), ciphertext.toString('base64url')].join('.');
  }
  decrypt(payload: string) {
    const [version, iv, tag, ciphertext] = payload.split('.');
    if (version !== 'v1' || !iv || !tag || !ciphertext) throw new InternalServerErrorException('Stored bank credential is invalid');
    const decipher = createDecipheriv('aes-256-gcm', this.key(), Buffer.from(iv, 'base64url'));
    decipher.setAuthTag(Buffer.from(tag, 'base64url'));
    return Buffer.concat([decipher.update(Buffer.from(ciphertext, 'base64url')), decipher.final()]).toString('utf8');
  }
}

