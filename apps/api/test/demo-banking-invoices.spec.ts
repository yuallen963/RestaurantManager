import { demoInvoiceSpecs } from '../prisma/demo-banking-invoices';
import {
  demoDowntownLocationId,
  demoMainLocationId,
} from '../prisma/demo-financial-profile';

describe('public demo banking and invoice history', () => {
  it('creates a deterministic, balanced twelve-month invoice history', () => {
    const first = demoInvoiceSpecs();
    const second = demoInvoiceSpecs();
    expect(second).toEqual(first);
    expect(first).toHaveLength(24);
    expect(new Set(first.map(({ id }) => id))).toHaveProperty('size', 24);
    for (const locationId of [demoMainLocationId, demoDowntownLocationId]) {
      const invoices = first.filter((invoice) => invoice.locationId === locationId);
      expect(invoices).toHaveLength(12);
      expect(invoices.filter((invoice) => invoice.paid)).toHaveLength(4);
      expect(new Set(invoices.map(({ daysAgo }) => daysAgo)).size).toBe(12);
    }
  });

  it('uses positive, reconcilable line amounts and applies tax only where configured', () => {
    const invoices = demoInvoiceSpecs();
    for (const invoice of invoices) {
      const subtotal = invoice.lines.reduce(
        (sum, line) => sum + line.quantity * line.unitPrice,
        0,
      );
      expect(subtotal).toBeGreaterThan(0);
      expect(invoice.lines.every((line) => line.quantity > 0 && line.unitPrice > 0)).toBe(true);
      expect(invoice.taxRate).toBeGreaterThanOrEqual(0);
      expect(invoice.taxRate).toBeLessThanOrEqual(.06);
    }
    expect(invoices.some((invoice) => invoice.taxRate > 0)).toBe(true);
    expect(invoices.some((invoice) => invoice.taxRate === 0)).toBe(true);
  });
});
