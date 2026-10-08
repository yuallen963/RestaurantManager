import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import OpenAI from 'openai';
import { zodTextFormat } from 'openai/helpers/zod';
import { z } from 'zod';

const nullableText = z.string().nullable();
const nullableNumber = z.number().nonnegative().nullable();
export const ExtractedInvoiceSchema = z.object({
  vendorName: nullableText,
  invoiceNumber: nullableText,
  invoiceDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable(),
  subtotal: nullableNumber,
  tax: nullableNumber,
  total: nullableNumber,
  uncertainFields: z.array(z.string()),
  lineItems: z.array(z.object({
    lineNumber: z.number().int().positive(),
    rawDescription: z.string(),
    sku: nullableText,
    quantity: nullableNumber,
    unit: nullableText,
    packSize: nullableText,
    unitPrice: nullableNumber,
    extendedPrice: nullableNumber,
    category: z.enum(['Food', 'Beverage', 'Alcohol', 'Supplies', 'Cleaning', 'Packaging', 'Other']).nullable(),
    uncertainFields: z.array(z.string()),
  })),
});
export type ExtractedInvoice = z.infer<typeof ExtractedInvoiceSchema>;

@Injectable()
export class InvoiceExtractionProvider {
  constructor(private readonly config: ConfigService) {}
  isConfigured() { return Boolean(this.config.get<string>('OPENAI_API_KEY')); }
  async extract(file: Buffer, mimeType: string, fileName: string) {
    const apiKey = this.config.get<string>('OPENAI_API_KEY');
    if (!apiKey) throw new ServiceUnavailableException('Invoice extraction is not configured');
    const model = this.config.get<string>('OPENAI_INVOICE_MODEL') ?? 'gpt-4.1-mini';
    const client = new OpenAI({ apiKey, timeout: 60_000, maxRetries: 1 });
    const dataUrl = `data:${mimeType};base64,${file.toString('base64')}`;
    const document = mimeType === 'application/pdf'
      ? { type: 'input_file' as const, filename: fileName, file_data: dataUrl, detail: 'high' as const }
      : { type: 'input_image' as const, image_url: dataUrl, detail: 'high' as const };
    const response = await client.responses.parse({
      model,
      store: false,
      input: [{ role: 'user', content: [document as any, { type: 'input_text', text: 'Extract this restaurant vendor invoice. Preserve every line item raw description exactly as printed. Use null when a value is absent. List field names in uncertainFields only when the document is ambiguous; do not invent confidence scores or values. Categories are suggestions only.' }] }],
      text: { format: zodTextFormat(ExtractedInvoiceSchema, 'restaurant_invoice') },
    });
    if (!response.output_parsed) throw new Error('Extraction provider returned no structured result');
    return { data: ExtractedInvoiceSchema.parse(response.output_parsed), provider: 'openai', model, usage: response.usage ? JSON.parse(JSON.stringify(response.usage)) : null };
  }
}
