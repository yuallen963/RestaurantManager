import { ForbiddenException, NotAcceptableException, UnauthorizedException } from '@nestjs/common';
import { createHmac } from 'crypto';
import { InboundAttachment, InboundEmailService, MailgunInboundBody } from '../src/invoices/inbound-email.service';

const secret = 'mailgun-test-signing-key';
const location = { id: 'loc-a', organizationId: 'org-a', invoiceEmailToken: 'abcdef0123456789abcdef0123456789' };
const file = (mimetype = 'application/pdf', name = 'invoice.pdf', contents = 'invoice'): InboundAttachment => ({ originalname: name, mimetype, size: Buffer.byteLength(contents), buffer: Buffer.from(contents) });
const signedBody = (overrides: Partial<MailgunInboundBody> = {}, now = Date.now()): MailgunInboundBody => {
  const timestamp = String(Math.floor(now / 1000));
  const token = 'webhook-token';
  return { timestamp, token, signature: createHmac('sha256', secret).update(`${timestamp}${token}`).digest('hex'), recipient: `invoices+${location.invoiceEmailToken}@inbound.example.com`, sender: 'billing@vendor.example', subject: 'October invoice', 'Message-Id': '<message-1@example.com>', ...overrides };
};

function setup(options: { configured?: boolean; location?: any } = {}) {
  const invoices = new Map<string, any>();
  const prisma: any = {
    restaurantLocation: { findUnique: jest.fn(({ where }) => Promise.resolve(where.id ? location : options.location === null ? null : location)) },
    organizationMember: { findFirst: jest.fn().mockResolvedValue({ userId: 'user-a' }) },
    invoice: {
      findUnique: jest.fn(({ where }) => Promise.resolve([...invoices.values()].find((row) => row.attachmentHash === where.organizationId_restaurantLocationId_attachmentHash?.attachmentHash) ?? null)),
      findFirst: jest.fn().mockResolvedValue(null),
      create: jest.fn(({ data }) => { invoices.set(data.id, data); return Promise.resolve(data); }),
      update: jest.fn(({ where, data }) => { const row = { ...invoices.get(where.id), ...data }; invoices.set(where.id, row); return Promise.resolve(row); }),
    },
  };
  const storage = { put: jest.fn().mockResolvedValue(undefined), remove: jest.fn().mockResolvedValue(undefined) };
  const extraction = { isConfigured: jest.fn().mockReturnValue(options.configured ?? true), process: jest.fn().mockResolvedValue(undefined) };
  const audit = { log: jest.fn().mockResolvedValue(undefined) };
  const access = { requireMember: jest.fn().mockResolvedValue({}) };
  const config = { get: jest.fn((key: string) => ({ INBOUND_EMAIL_WEBHOOK_SIGNING_KEY: secret, INVOICE_EMAIL_DOMAIN: 'inbound.example.com', INVOICE_EMAIL_PREFIX: 'invoices' })[key]) };
  return { service: new InboundEmailService(prisma, access as any, config as any, storage as any, extraction as any, audit as any), prisma, storage, extraction, audit, access, invoices };
}

describe('invoice email ingestion', () => {
  it('verifies Mailgun signatures and rejects tampered or stale webhooks', () => {
    const { service } = setup();
    expect(() => service.verifySignature(signedBody())).not.toThrow();
    expect(() => service.verifySignature(signedBody({ signature: '0'.repeat(64) }))).toThrow(UnauthorizedException);
    expect(() => service.verifySignature(signedBody({}, Date.now() - 10 * 60 * 1000))).toThrow(UnauthorizedException);
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

  it('creates one invoice per supported attachment while one multi-page PDF stays one invoice', async () => {
    const { service, prisma } = setup({ configured: false });
    const pdf = file('application/pdf', 'multipage.pdf', '%PDF page-one page-two');
    const result = await service.ingest(signedBody(), [pdf, file('image/jpeg', 'second.jpg', 'jpeg'), file('image/png', 'third.png', 'png')]);
    expect(result.created).toHaveLength(3);
    expect(prisma.invoice.create).toHaveBeenCalledTimes(3);
  });

  it('prevents duplicate attachment hashes and makes provider retries idempotent', async () => {
    const { service, prisma } = setup({ configured: false });
    const first = await service.ingest(signedBody(), [file()]);
    const retry = await service.ingest(signedBody(), [file()]);
    expect(first.created).toHaveLength(1);
    expect(retry).toMatchObject({ created: [], duplicates: [first.created[0]] });
    expect(prisma.invoice.create).toHaveBeenCalledTimes(1);
  });

  it('starts the existing extraction processor when configured', async () => {
    const { service, extraction, prisma } = setup();
    const result = await service.ingest(signedBody(), [file()]);
    await new Promise((resolve) => setImmediate(resolve));
    expect(prisma.invoice.update).toHaveBeenCalledWith(expect.objectContaining({ where: { id: result.created[0] }, data: expect.objectContaining({ extractionStatus: 'PROCESSING' }) }));
    expect(extraction.process).toHaveBeenCalledWith(result.created[0], 'user-a');
  });

  it('keeps forwarding addresses tenant scoped', async () => {
    const { service, access } = setup();
    access.requireMember.mockRejectedValue(new ForbiddenException());
    await expect(service.address('other-user', location.id)).rejects.toBeInstanceOf(ForbiddenException);
  });
});
