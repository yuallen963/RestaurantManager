import { createHash } from 'crypto';
import { Prisma } from '@prisma/client';

export interface InvoiceIdentityFields {
  id: string;
  organizationId: string;
  restaurantLocationId: string;
  vendorId: string | null;
  invoiceNumber: string | null;
  invoiceDate: Date | null;
  currency: string | null;
  total: Prisma.Decimal | number | string | null;
  attachmentHash: string | null;
}

const digest = (value: string) => createHash('sha256').update(value).digest('hex');
export const normalizedInvoiceNumber = (value: string | null) =>
  value?.trim().toUpperCase().replace(/[^A-Z0-9]+/g, '') || null;

export function invoiceIdentity(invoice: InvoiceIdentityFields) {
  if (!invoice.vendorId || !invoice.invoiceDate || !invoice.currency?.trim() || invoice.total == null) return null;
  const amount = new Prisma.Decimal(invoice.total.toString());
  if (!amount.isFinite() || amount.lt(0)) return null;
  const base = [invoice.organizationId, invoice.restaurantLocationId, invoice.vendorId,
    invoice.invoiceDate.toISOString().slice(0, 10), invoice.currency.trim().toUpperCase(), amount.toFixed(2)].join('|');
  // The coarse claim serializes same-day, same-total purchases even when their
  // printed numbers differ. A reviewer can explicitly confirm distinctness.
  const claimKey = digest(`invoice-claim-v1|${base}`);
  const fingerprint = digest(`invoice-evidence-v1|${base}|${normalizedInvoiceNumber(invoice.invoiceNumber) ?? '<missing>'}`);
  return { claimKey, fingerprint };
}

export function distinctReviewedKey(claimKey: string, invoiceId: string) {
  return digest(`invoice-distinct-v1|${claimKey}|${invoiceId}`);
}

export function duplicateCandidateKind(current: InvoiceIdentityFields, other: InvoiceIdentityFields): 'DEFINITE' | 'POSSIBLE' | null {
  if (current.organizationId !== other.organizationId || current.restaurantLocationId !== other.restaurantLocationId || current.id === other.id) return null;
  if (current.attachmentHash && current.attachmentHash === other.attachmentHash) return 'DEFINITE';
  const a = invoiceIdentity(current), b = invoiceIdentity(other);
  if (!a || !b || a.claimKey !== b.claimKey) return null;
  return 'POSSIBLE';
}
