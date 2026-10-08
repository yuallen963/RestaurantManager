import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DeleteObjectCommand, GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
@Injectable()
export class InvoiceStorageService {
  constructor(private readonly config: ConfigService) {}
  private get client() { const endpoint = this.config.get<string>('S3_ENDPOINT'); const bucket = this.config.get<string>('S3_BUCKET'); const accessKeyId = this.config.get<string>('S3_ACCESS_KEY_ID'); const secretAccessKey = this.config.get<string>('S3_SECRET_ACCESS_KEY'); if (!endpoint || !bucket || !accessKeyId || !secretAccessKey) throw new ServiceUnavailableException('Invoice storage is not configured'); return new S3Client({ endpoint, region: this.config.get<string>('S3_REGION') ?? 'us-east-1', forcePathStyle: this.config.get<string>('S3_FORCE_PATH_STYLE') === 'true', credentials: { accessKeyId, secretAccessKey } }); }
  bucket() { return this.config.get<string>('S3_BUCKET')!; }
  async putUrl(key: string, mimeType: string) { return getSignedUrl(this.client, new PutObjectCommand({ Bucket: this.bucket(), Key: key, ContentType: mimeType }), { expiresIn: 900 }); }
  async remove(key: string) { await this.client.send(new DeleteObjectCommand({ Bucket: this.bucket(), Key: key })); }
  async exists(key: string) { await this.client.send(new HeadObjectCommand({ Bucket: this.bucket(), Key: key })); }
  async get(key: string) { const result = await this.client.send(new GetObjectCommand({ Bucket: this.bucket(), Key: key })); if (!result.Body) throw new Error('Invoice source file is missing'); return Buffer.from(await result.Body.transformToByteArray()); }
}
