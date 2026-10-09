import { Injectable, InternalServerErrorException } from '@nestjs/common';
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

@Injectable()
export class BankTokenEncryptionService {
  private key(environmentVariable = 'BANK_TOKEN_ENCRYPTION_KEY'): Buffer {
    const configured = process.env[environmentVariable];
    if (!configured) throw new InternalServerErrorException(`${environmentVariable} is not configured`);
    const key = Buffer.from(configured, 'base64');
    if (key.length !== 32) throw new InternalServerErrorException(`${environmentVariable} must be a base64-encoded 32-byte key`);
    return key;
  }
  encrypt(value: string, environmentVariable = 'BANK_TOKEN_ENCRYPTION_KEY') {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key(environmentVariable), iv);
    const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    return ['v1', iv.toString('base64url'), cipher.getAuthTag().toString('base64url'), ciphertext.toString('base64url')].join('.');
  }
  decrypt(payload: string, environmentVariable = 'BANK_TOKEN_ENCRYPTION_KEY') {
    const [version, iv, tag, ciphertext] = payload.split('.');
    if (version !== 'v1' || !iv || !tag || !ciphertext) throw new InternalServerErrorException('Stored bank credential is invalid');
    const decipher = createDecipheriv('aes-256-gcm', this.key(environmentVariable), Buffer.from(iv, 'base64url'));
    decipher.setAuthTag(Buffer.from(tag, 'base64url'));
    return Buffer.concat([decipher.update(Buffer.from(ciphertext, 'base64url')), decipher.final()]).toString('utf8');
  }
  encryptPos(value: string) { return this.encrypt(value, 'POS_TOKEN_ENCRYPTION_KEY'); }
  decryptPos(value: string) { return this.decrypt(value, 'POS_TOKEN_ENCRYPTION_KEY'); }
}
