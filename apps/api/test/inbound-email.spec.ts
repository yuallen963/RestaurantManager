import { ForbiddenException, NotAcceptableException, UnauthorizedException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHmac } from 'crypto';
import { InboundAttachment, InboundEmailService, MailgunInboundBody } from '../src/invoices/inbound-email.service';

const secret = 'mailgun-test-signing-key';
const location = { id: 'loc-a', organizationId: 'org-a', invoiceEmailToken: 'abcdef0123456789abcdef0123456789' };
const content = (mimetype: string, value = 'invoice') => mimetype === 'application/pdf' ? Buffer.from(`%PDF-${value}`) : mimetype === 'image/jpeg' ? Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.from(value)]) : mimetype === 'image/png' ? Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.from(value)]) : Buffer.from(value);
const file = (mimetype = 'application/pdf', name = 'invoice.pdf', value = 'invoice', extra: Partial<InboundAttachment> = {}): InboundAttachment => { const buffer = content(mimetype, value); return { fieldname: 'attachment-1', originalname: name, mimetype, size: buffer.length, buffer, ...extra }; };
const signedBody = (overrides: Partial<MailgunInboundBody> = {}, now = Date.now()): MailgunInboundBody => {
  const timestamp = String(Math.floor(now / 1000));
  const token = overrides.token ?? 'webhook-token';
  return { timestamp, recipient: `invoices+${location.invoiceEmailToken}@inbound.example.com`, sender: 'billing@vendor.example', subject: 'October invoice', 'Message-Id': '<message-1@example.com>', ...overrides, token, signature: overrides.signature ?? createHmac('sha256', secret).update(`${timestamp}${token}`).digest('hex') };
};

function setup(options: { configured?: boolean; location?: any } = {}) {
  const invoices = new Map<string, any>();
  const receipts = new Map<string, any>();
  const prisma: any = {
    restaurantLocation: { findUnique: jest.fn(({ where }) => Promise.resolve(where.id ? location : options.location === null ? null : location)) },
    organizationMember: { findFirst: jest.fn().mockResolvedValue({ userId: 'user-a' }) },
    invoice: {
      findUnique: jest.fn(({ where }) => Promise.resolve([...invoices.values()].find((row) => row.attachmentHash === where.organizationId_restaurantLocationId_attachmentHash?.attachmentHash) ?? null)),
      findFirst: jest.fn().mockResolvedValue(null),
      create: jest.fn(({ data }) => { invoices.set(data.id, data); return Promise.resolve(data); }),
      update: jest.fn(({ where, data }) => { const row = { ...invoices.get(where.id), ...data }; invoices.set(where.id, row); return Promise.resolve(row); }),
    },
    inboundEmailWebhookReceipt: {
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      create: jest.fn(({ data }) => {
        if (receipts.has(data.tokenHash)) throw new Prisma.PrismaClientKnownRequestError('duplicate', { code: 'P2002', clientVersion: '6.19.3' });
        receipts.set(data.tokenHash, data);
        return Promise.resolve(data);
      }),
      update: jest.fn(({ where, data }) => { receipts.set(where.tokenHash, { ...receipts.get(where.tokenHash), ...data }); return Promise.resolve(receipts.get(where.tokenHash)); }),
      delete: jest.fn(({ where }) => { receipts.delete(where.tokenHash); return Promise.resolve({}); }),
    },
  };
  const storage = { put: jest.fn().mockResolvedValue(undefined), remove: jest.fn().mockResolvedValue(undefined) };
  const extraction = { isConfigured: jest.fn().mockReturnValue(options.configured ?? true), process: jest.fn().mockResolvedValue(undefined) };
  const audit = { log: jest.fn().mockResolvedValue(undefined) };
  const access = { requireMember: jest.fn().mockResolvedValue({}) };
  const config = { get: jest.fn((key: string) => ({ INBOUND_EMAIL_WEBHOOK_SIGNING_KEY: secret, INVOICE_EMAIL_DOMAIN: 'inbound.example.com', INVOICE_EMAIL_PREFIX: 'invoices' })[key]) };
  return { service: new InboundEmailService(prisma, access as any, config as any, storage as any, extraction as any, audit as any), prisma, storage, extraction, audit, access, invoices, receipts };
}

describe('invoice email ingestion', () => {
  it('verifies Mailgun signatures and rejects tampered or stale webhooks', () => {
    const { service } = setup();
    expect(() => service.verifySignature(signedBody())).not.toThrow();
    expect(() => service.verifySignature(signedBody({ signature: '0'.repeat(64) }))).toThrow(UnauthorizedException);
    expect(() => service.verifySignature(signedBody({}, Date.now() - 10 * 60 * 1000))).toThrow(UnauthorizedException);
    expect(() => service.verifySignature({})).toThrow(UnauthorizedException);
  });

  it.each([['application/pdf', 'invoice.pdf'], ['image/jpeg', 'invoice.jpg'], ['image/png', 'invoice.png']])('accepts supported %s attachments', async (mime, name) => {
    const { service, prisma, storage } = setup({ configured: false });
    const result = await service.ingest(signedBody(), [file(mime, name)]);
    expect(result.created).toHaveLength(1);
    expect(storage.put).toHaveBeenCalledWith(expect.stringContaining('/invoices/'), mime, expect.any(Buffer));
    expect(prisma.invoice.create).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ organizationId: 'org-a', restaurantLocationId: 'loc-a', ingestionSource: 'EMAIL_FORWARD', inboundSender: 'billing@vendor.example', inboundSubject: 'October invoice' }) }));
  });

  it('rejects an unknown forwarding alias without storing data', async () => {
    const { service, storage } = setup({ location: null });
    await expect(service.ingest(signedBody(), [file()])).rejects.toBeInstanceOf(NotAcceptableException);
    expect(storage.put).not.toHaveBeenCalled();
  });

  it('ignores unsupported attachments and records a safe failure', async () => {
    const { service, prisma, audit } = setup();
    const result = await service.ingest(signedBody(), [file('text/plain', 'notes.txt')]);
    expect(result).toMatchObject({ accepted: true, created: [], ignoredAttachments: 1 });
    expect(prisma.invoice.create).not.toHaveBeenCalled();
    expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'invoice.ingestion_failed' }));
  });

  it('rejects oversized attachments and MIME types with mismatched magic bytes', async () => {
    const { service, prisma } = setup();
    const oversized = file('application/pdf', 'large.pdf', 'large', { size: 15 * 1024 * 1024 + 1, fieldname: 'attachment-2' });
    const forged = file('application/pdf', 'fake.pdf', 'fake', { buffer: Buffer.from('not a pdf'), size: 9, fieldname: 'attachment-3' });
    const result = await service.ingest(signedBody(), [oversized, forged]);
    expect(result).toMatchObject({ created: [], ignoredAttachments: 2 });
    expect(prisma.invoice.create).not.toHaveBeenCalled();
  });

  it('creates one invoice per supported attachment while one multi-page PDF stays one invoice', async () => {
    const { service, prisma } = setup({ configured: false });
    const pdf = file('application/pdf', 'multipage.pdf', 'page-one page-two');
    const result = await service.ingest(signedBody(), [pdf, file('image/jpeg', 'second.jpg', 'jpeg', { fieldname: 'attachment-2' }), file('image/png', 'third.png', 'png', { fieldname: 'attachment-3' })]);
    expect(result.created).toHaveLength(3);
    expect(prisma.invoice.create).toHaveBeenCalledTimes(3);
  });

  it('prevents duplicate attachment hashes and makes provider retries idempotent', async () => {
    const { service, prisma } = setup({ configured: false });
    const first = await service.ingest(signedBody(), [file()]);
    const retry = await service.ingest(signedBody({ token: 'second-webhook-token' }), [file()]);
    expect(first.created).toHaveLength(1);
    expect(retry).toMatchObject({ created: [], duplicates: [first.created[0]] });
    expect(prisma.invoice.create).toHaveBeenCalledTimes(1);
  });

  it('acknowledges an authenticated Mailgun webhook replay without processing it twice', async () => {
    const { service, prisma } = setup({ configured: false });
    await service.ingest(signedBody(), [file()]);
    const replay = await service.ingest(signedBody(), [file()]);
    expect(replay).toMatchObject({ accepted: true, replay: true, created: [] });
    expect(prisma.invoice.create).toHaveBeenCalledTimes(1);
  });

  it('ignores content-id inline artwork while accepting the invoice PDF', async () => {
    const { service, prisma } = setup({ configured: false });
    const body = signedBody({ 'content-id-map': JSON.stringify({ '<logo@example>': 'attachment-2' }) });
    const result = await service.ingest(body, [file(), file('image/png', 'brand.png', 'logo', { fieldname: 'attachment-2' })]);
    expect(result).toMatchObject({ ignoredAttachments: 1 });
    expect(result.created).toHaveLength(1);
    expect(prisma.invoice.create).toHaveBeenCalledTimes(1);
  });

  it('processes a valid attachment when another attachment is unsupported', async () => {
    const { service } = setup({ configured: false });
    const result = await service.ingest(signedBody(), [file('text/html', 'message.html'), file('application/pdf', 'invoice.pdf', 'valid', { fieldname: 'attachment-2' })]);
    expect(result.created).toHaveLength(1);
    expect(result.ignoredAttachments).toBe(1);
  });

  it('removes the replay claim after storage failure so Mailgun can retry', async () => {
    const { service, storage, prisma } = setup({ configured: false });
    storage.put.mockRejectedValueOnce(new Error('storage unavailable'));
    await expect(service.ingest(signedBody(), [file()])).rejects.toThrow('storage unavailable');
    expect(prisma.inboundEmailWebhookReceipt.delete).toHaveBeenCalled();
    storage.put.mockResolvedValue(undefined);
    await expect(service.ingest(signedBody(), [file()])).resolves.toMatchObject({ accepted: true });
  });

  it('starts the existing extraction processor when configured', async () => {
    const { service, extraction, prisma } = setup();
    const result = await service.ingest(signedBody(), [file()]);
    await new Promise((resolve) => setImmediate(resolve));
    expect(prisma.invoice.update).toHaveBeenCalledWith(expect.objectContaining({ where: { id: result.created[0] }, data: expect.objectContaining({ extractionStatus: 'PROCESSING' }) }));
    expect(extraction.process).toHaveBeenCalledWith(result.created[0], 'user-a');
  });

  it('persists the invoice as NOT_STARTED when extraction is unavailable', async () => {
    const { service, prisma, extraction } = setup({ configured: false });
    await service.ingest(signedBody(), [file()]);
    expect(prisma.invoice.create).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ extractionStatus: 'NOT_STARTED', inboundMessageId: '<message-1@example.com>', originalAttachmentName: 'invoice.pdf' }) }));
    expect(extraction.process).not.toHaveBeenCalled();
  });

  it('keeps forwarding addresses tenant scoped', async () => {
    const { service, access } = setup();
    access.requireMember.mockRejectedValue(new ForbiddenException());
    await expect(service.address('other-user', location.id)).rejects.toBeInstanceOf(ForbiddenException);
  });
});
