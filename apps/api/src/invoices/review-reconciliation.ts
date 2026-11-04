import { Prisma } from '@prisma/client';

type Amount = Prisma.Decimal | number | string | null;
export interface ReviewAmounts {
  subtotal: Amount;
  tax: Amount;
  otherFees: Amount;
  discount: Amount;
  total: Amount;
  lines: Array<{ id: string; quantity: Amount; unit: string | null; unitPrice: Amount; extendedPrice: Amount }>;
}

const decimal = (value: Exclude<Amount, null>) => new Prisma.Decimal(value.toString());
const withinCent = (a: Prisma.Decimal, b: Prisma.Decimal) => a.sub(b).abs().lte(new Prisma.Decimal('0.01'));

export function reviewDiscrepancies(data: ReviewAmounts): string[] {
  const problems: string[] = [];
  const completeLines = data.lines.length > 0 && data.lines.every((line) => line.extendedPrice != null);
  const lineSum = completeLines
    ? data.lines.reduce((sum, line) => sum.add(decimal(line.extendedPrice!)), new Prisma.Decimal(0))
    : null;
  if (data.subtotal != null && lineSum && !withinCent(lineSum, decimal(data.subtotal)))
    problems.push(`line items sum to ${lineSum.toFixed(2)}, but subtotal is ${decimal(data.subtotal).toFixed(2)}`);
  const supportedSubtotal = data.subtotal != null ? decimal(data.subtotal) : lineSum;
  if (data.lines.length && !supportedSubtotal) problems.push('subtotal is missing and complete line-item amounts are unavailable');
  if (supportedSubtotal && data.total != null) {
    const supportedTotal = supportedSubtotal
      .add(data.tax == null ? 0 : decimal(data.tax))
      .add(data.otherFees == null ? 0 : decimal(data.otherFees))
      .sub(data.discount == null ? 0 : decimal(data.discount));
    if (!withinCent(supportedTotal, decimal(data.total))) {
      const missing = [data.tax == null && 'tax', data.otherFees == null && 'delivery or service fees', data.discount == null && 'discount'].filter(Boolean);
      problems.push(`known charges reconcile to ${supportedTotal.toFixed(2)}, but total is ${decimal(data.total).toFixed(2)}${missing.length ? `; check missing ${missing.join(', ')}` : ''}`);
    }
  }
  for (const line of data.lines) {
    if (line.quantity != null && line.unitPrice != null && line.extendedPrice != null && ['EA', 'EACH', 'UNIT', 'CT', 'COUNT'].includes(line.unit?.trim().toUpperCase() ?? '')) {
      const calculated = decimal(line.quantity).mul(decimal(line.unitPrice));
      if (!withinCent(calculated, decimal(line.extendedPrice)))
        problems.push(`line ${line.id}: quantity times unit price is ${calculated.toFixed(2)}, but extended price is ${decimal(line.extendedPrice).toFixed(2)}`);
    }
  }
  return problems;
}
