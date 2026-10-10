import { BadRequestException, Injectable, NotAcceptableException, NotFoundException, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ExtractionStatus, InvoiceIngestionSource, InvoiceStatus, Prisma } from '@prisma/client';
import { createHash, createHmac, randomUUID, timingSafeEqual } from 'crypto';
import { AuditService } from '../audit.service';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PrismaService } from '../prisma.service';
import { InvoiceExtractionProcessor } from './extraction.processor';
import { InvoiceStorageService } from './storage.service';

export interface InboundAttachment {
  fieldname?: string;
  originalname: string;
  mimetype: string;
  size: number;
  buffer: Buffer;
}

export interface MailgunInboundBody {
  timestamp?: string;
  token?: string;
  signature?: string;
  recipient?: string;
  sender?: string;
  from?: string;
  subject?: string;
  'Message-Id'?: string;
  'message-id'?: string;
  'content-id-map'?: string;
}

const allowedTypes = new Set(['application/pdf', 'image/jpeg', 'image/png']);
const maxAttachmentSize = 15 * 1024 * 1024;
const safeName = (name: string) => name.replace(/[^a-zA-Z0-9._-]/g, '_').slice(-160) || 'invoice';
const replayRetentionMs = 24 * 60 * 60 * 1000;
const isExpectedContent = (file: InboundAttachment) => {
  if (file.mimetype === 'application/pdf') return file.buffer.subarray(0, 1024).includes(Buffer.from('%PDF-'));
  if (file.mimetype === 'image/jpeg') return file.buffer.length >= 3 && file.buffer[0] === 0xff && file.buffer[1] === 0xd8 && file.buffer[2] === 0xff;
  if (file.mimetype === 'image/png') return file.buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  return false;
};

@Injectable()
export class InboundEmailService {
  private readonly rate = new Map<string, { minute: number; count: number }>();
  constructor(private readonly prisma: PrismaService, private readonly access: OrganizationAccessService, private readonly config: ConfigService, private readonly storage: InvoiceStorageService, private readonly extraction: InvoiceExtractionProcessor, private readonly audit: AuditService) {}

  private domain() {
    const domain = this.config.get<string>('INVOICE_EMAIL_DOMAIN')?.trim().toLowerCase();
    if (!domain) throw new ServiceUnavailableException('Invoice email domain is not configured');
    return domain;
  }

  private prefix() { return this.config.get<string>('INVOICE_EMAIL_PREFIX')?.trim().toLowerCase() || 'invoices'; }

  verifySignature(body: MailgunInboundBody, now = Date.now()) {
    const provider = this.config.get<string>('INBOUND_EMAIL_PROVIDER')?.toLowerCase() || 'mailgun';
    if (provider !== 'mailgun') throw new ServiceUnavailableException('Configured inbound email provider is not supported');
    const secret = this.config.get<string>('INBOUND_EMAIL_WEBHOOK_SIGNING_KEY');
    if (!secret || !body.timestamp || !body.token || !body.signature) throw new UnauthorizedException('Invalid inbound email signature');
    const timestamp = Number(body.timestamp);
    if (!Number.isFinite(timestamp) || Math.abs(now - timestamp * 1000) > 5 * 60 * 1000) throw new UnauthorizedException('Expired inbound email signature');
    const expected = createHmac('sha256', secret).update(`${body.timestamp}${body.token}`).digest('hex');
    const actual = body.signature.toLowerCase();
    if (expected.length !== actual.length || !timingSafeEqual(Buffer.from(expected), Buffer.from(actual))) throw new UnauthorizedException('Invalid inbound email signature');
    const minute = Math.floor(now / 60000);
    const current = this.rate.get('mailgun');
    const count = current?.minute === minute ? current.count + 1 : 1;
    this.rate.set('mailgun', { minute, count });
    if (count > 120) throw new BadRequestException('Inbound email rate limit exceeded');
  }

  private aliasToken(recipient?: string) {
    if (!recipient) throw new NotAcceptableException('Unknown invoice forwarding address');
    const address = recipient.match(/<?([^<>\s,]+@[^<>\s,]+)>?/)?.[1]?.toLowerCase();
    const match = address?.match(new RegExp(`^${this.prefix()}\\+([a-f0-9]{24,64})@${this.domain().replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`));
    if (!match) throw new NotAcceptableException('Unknown invoice forwarding address');
    return match[1];
  }

  async address(userId: string, restaurantLocationId: string) {
    const location = await this.prisma.restaurantLocation.findUnique({ where: { id: restaurantLocationId } });
    if (!location) throw new NotFoundException('Location not found');
    await this.access.requireMember(userId, location.organizationId);
    return { restaurantLocationId: location.id, address: `${this.prefix()}+${location.invoiceEmailToken}@${this.domain()}` };
  }

  async ingest(body: MailgunInboundBody, files: InboundAttachment[]) {
    this.verifySignature(body);
    const tokenHash = createHash('sha256').update(body.token!).digest('hex');
    await this.prisma.inboundEmailWebhookReceipt.deleteMany({ where: { receivedAt: { lt: new Date(Date.now() - replayRetentionMs) } } });
    try {
      await this.prisma.inboundEmailWebhookReceipt.create({ data: { tokenHash } });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') return { accepted: true, created: [], duplicates: [], ignoredAttachments: 0, replay: true };
      throw error;
    }
    try {
      const result = await this.ingestVerified(body, files);
      await this.prisma.inboundEmailWebhookReceipt.update({ where: { tokenHash }, data: { processedAt: new Date() } });
      return result;
    } catch (error) {
      await this.prisma.inboundEmailWebhookReceipt.delete({ where: { tokenHash } }).catch(() => undefined);
      throw error;
    }
  }

  private async ingestVerified(body: MailgunInboundBody, files: InboundAttachment[]) {
    const location = await this.prisma.restaurantLocation.findUnique({ where: { invoiceEmailToken: this.aliasToken(body.recipient) } });
    if (!location) throw new NotAcceptableException('Unknown invoice forwarding address');
    const member = await this.prisma.organizationMember.findFirst({ where: { organizationId: location.organizationId }, orderBy: { createdAt: 'asc' }, select: { userId: true } });
    if (!member) throw new ServiceUnavailableException('Invoice email location has no active organization member');
    const sender = (body.sender || body.from || '').slice(0, 320) || null;
    const subject = body.subject?.slice(0, 500) || null;
    const messageId = (body['Message-Id'] || body['message-id'])?.slice(0, 500) || null;
    await this.audit.log({ userId: member.userId, organizationId: location.organizationId, action: 'invoice.email_received', entityType: 'RestaurantLocation', entityId: location.id, metadata: { messageId, attachmentCount: files.length } });
    const inlineFields = this.inlineAttachmentFields(body['content-id-map']);
    const supported: InboundAttachment[] = [];
    const rejected: Array<{ file: InboundAttachment; reason: string }> = [];
    for (const file of files) {
      file.mimetype = file.mimetype.toLowerCase().split(';')[0].trim();
      const decorative = (file.fieldname && inlineFields.has(file.fieldname)) || inlineFields.has(file.originalname) || (file.size <= 256 * 1024 && /(?:^|[_.-])(logo|signature|spacer|pixel|icon)(?:[_.-]|$)/i.test(file.originalname));
      const reason = !allowedTypes.has(file.mimetype) ? 'unsupported_mime_type' : file.size > maxAttachmentSize ? 'attachment_too_large' : decorative ? 'decorative_inline_image' : !isExpectedContent(file) ? 'file_signature_mismatch' : null;
      if (reason) rejected.push({ file, reason }); else supported.push(file);
    }
    for (const { file, reason } of rejected) await this.audit.log({ userId: member.userId, organizationId: location.organizationId, action: reason === 'decorative_inline_image' ? 'invoice.attachment_ignored' : 'invoice.ingestion_failed', entityType: 'RestaurantLocation', entityId: location.id, metadata: { messageId, fileName: safeName(file.originalname), reason } });
    if (!supported.length) return { accepted: true, created: [], duplicates: [], ignoredAttachments: rejected.length, message: 'No supported invoice attachments were found' };
    const created: string[] = [];
    const duplicates: string[] = [];
    for (const file of supported) {
      const hash = createHash('sha256').update(file.buffer).digest('hex');
      const duplicate = await this.prisma.invoice.findUnique({ where: { organizationId_restaurantLocationId_attachmentHash: { organizationId: location.organizationId, restaurantLocationId: location.id, attachmentHash: hash } }, select: { id: true } });
      if (duplicate) {
        duplicates.push(duplicate.id);
        await this.audit.log({ userId: member.userId, organizationId: location.organizationId, action: 'invoice.duplicate_skipped', entityType: 'Invoice', entityId: duplicate.id, metadata: { messageId, attachmentHash: hash } });
        continue;
      }
      const id = randomUUID();
      const originalName = file.originalname.trim() || 'invoice';
      const fileName = safeName(originalName);
      const storageKey = `organizations/${location.organizationId}/locations/${location.id}/invoices/${id}/${fileName}`;
      try {
        await this.storage.put(storageKey, file.mimetype, file.buffer);
        await this.prisma.invoice.create({ data: { id, organizationId: location.organizationId, restaurantLocationId: location.id, fileName, originalFileName: originalName, originalAttachmentName: originalName, fileType: file.mimetype, fileSize: file.size, storageKey, createdByUserId: member.userId, status: InvoiceStatus.UPLOADED, ingestionSource: InvoiceIngestionSource.EMAIL_FORWARD, inboundMessageId: messageId, inboundSender: sender, inboundSubject: subject, inboundReceivedAt: new Date(), attachmentHash: hash, extractionStatus: ExtractionStatus.NOT_STARTED } });
      } catch (error) {
        if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
          try { await this.storage.remove(storageKey); } catch { /* best-effort cleanup */ }
          const existing = await this.prisma.invoice.findFirst({ where: { organizationId: location.organizationId, restaurantLocationId: location.id, attachmentHash: hash }, select: { id: true } });
          if (existing) {
            duplicates.push(existing.id);
            await this.audit.log({ userId: member.userId, organizationId: location.organizationId, action: 'invoice.duplicate_skipped', entityType: 'Invoice', entityId: existing.id, metadata: { messageId, attachmentHash: hash } });
          }
          continue;
        }
        try { await this.storage.remove(storageKey); } catch { /* best-effort cleanup */ }
        await this.audit.log({ userId: member.userId, organizationId: location.organizationId, action: 'invoice.ingestion_failed', entityType: 'Invoice', entityId: id, metadata: { messageId, reason: 'storage_or_invoice_creation_failed' } });
        throw error;
      }
      created.push(id);
      await this.audit.log({ userId: member.userId, organizationId: location.organizationId, action: 'invoice.attachment_accepted', entityType: 'Invoice', entityId: id, metadata: { messageId, fileType: file.mimetype, fileSize: file.size, attachmentHash: hash } });
      await this.audit.log({ userId: member.userId, organizationId: location.organizationId, action: 'invoice.created_from_email', entityType: 'Invoice', entityId: id, metadata: { messageId, restaurantLocationId: location.id } });
      if (this.extraction.isConfigured()) {
        await this.prisma.invoice.update({ where: { id }, data: { extractionStatus: ExtractionStatus.PROCESSING, extractionStartedAt: new Date(), extractionAttemptCount: { increment: 1 } } });
        await this.audit.log({ userId: member.userId, organizationId: location.organizationId, action: 'invoice.extraction_started', entityType: 'Invoice', entityId: id });
        setImmediate(() => void this.extraction.process(id, member.userId));
      }
    }
    return { accepted: true, created, duplicates, ignoredAttachments: rejected.length };
  }

  private inlineAttachmentFields(raw?: string) {
    if (!raw) return new Set<string>();
    try {
      const parsed = JSON.parse(raw);
      return new Set<string>(Object.values(parsed).filter((value): value is string => typeof value === 'string'));
    } catch {
      return new Set<string>();
    }
  }
}
