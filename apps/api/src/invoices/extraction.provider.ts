import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import OpenAI from 'openai';
import { zodTextFormat } from 'openai/helpers/zod';
import { z } from 'zod';

const nullableText = z.string().nullable();
const nullableNumber = z.number().nonnegative().nullable();
const ProductAttributesSchema = z.object({
  brand: nullableText,
  condition: nullableText,
  bone: nullableText,
  skin: nullableText,
  organic: nullableText,
  grade: nullableText,
  cut: nullableText,
  size: nullableText,
  packConfiguration: nullableText,
});
export const ExtractedInvoiceSchema = z.object({
  vendorName: nullableText,
  vendorAddress: nullableText,
  invoiceNumber: nullableText,
  invoiceDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable(),
  dueDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable(),
  subtotal: nullableNumber,
  tax: nullableNumber,
  otherFees: nullableNumber,
  total: nullableNumber,
  currency: z.string().regex(/^[A-Z]{3}$/).nullable(),
  uncertainFields: z.array(z.string()),
  lineItems: z.array(z.object({
    lineNumber: z.number().int().positive(),
    sourcePage: z.number().int().positive().nullable(),
    rawDescription: z.string(),
    normalizedName: nullableText,
    sku: nullableText,
    quantity: nullableNumber,
    unit: nullableText,
    packSize: nullableText,
    unitPrice: nullableNumber,
    extendedPrice: nullableNumber,
    category: z.enum(['Food', 'Beverage', 'Alcohol', 'Supplies', 'Cleaning', 'Packaging', 'Other']).nullable(),
    productAttributes: ProductAttributesSchema.nullable(),
    uncertainFields: z.array(z.string()),
  })),
});
export type ExtractedInvoice = z.infer<typeof ExtractedInvoiceSchema>;

@Injectable()
export class InvoiceExtractionProvider {
  private readonly logger = new Logger(InvoiceExtractionProvider.name);

  constructor(private readonly config: ConfigService) {}
  isConfigured() { return Boolean(this.config.get<string>('OPENAI_API_KEY')); }
  async extract(file: Buffer, mimeType: string, fileName: string) {
    const apiKey = this.config.get<string>('OPENAI_API_KEY');
    if (!apiKey) throw new ServiceUnavailableException('Invoice extraction is not configured');
    const model = this.config.get<string>('OPENAI_INVOICE_MODEL') ?? 'gpt-4.1-mini';
    const client = new OpenAI({ apiKey, timeout: 60_000, maxRetries: 1 });
    const dataUrl = `data:${mimeType};base64,${file.toString('base64')}`;
    const document = mimeType === 'application/pdf'
      ? { type: 'input_file' as const, filename: fileName, file_data: dataUrl }
      : { type: 'input_image' as const, image_url: dataUrl, detail: 'high' as const };
    try {
      const response = await client.responses.parse({
        model,
        store: false,
        input: [{ role: 'user', content: [document, { type: 'input_text', text: `Extract this restaurant vendor invoice, including every relevant page in page order as one invoice. Combine line items across pages. Do not duplicate repeated headers, footers, subtotals, or grand totals. Preserve every line item rawDescription and packSize exactly as printed. sourcePage is the one-based PDF page number when clear, otherwise null. normalizedName and productAttributes are interpretations, never replacements for rawDescription. Normalize invoiceDate and dueDate to YYYY-MM-DD. If a printed date omits its year, infer the current year only when clearly recent and unambiguous; otherwise return null and include the field in uncertainFields. Use null when a value or product attribute is absent or unclear. Do not infer package quantities that are not plainly printed. List field names in uncertainFields only when the document is ambiguous; do not invent confidence scores or values. Currency must be a three-letter ISO code only when shown or unambiguous. Categories are suggestions only. Today is ${new Date().toISOString().slice(0, 10)}.` }] }],
        text: { format: zodTextFormat(ExtractedInvoiceSchema, 'restaurant_invoice') },
      });
      if (!response.output_parsed) {
        this.logger.warn(JSON.stringify({ event: 'invoice_extraction_unparsed', responseId: response.id, status: response.status, incompleteReason: response.incomplete_details?.reason ?? null, outputTypes: response.output.map((item) => item.type) }));
        throw new Error('Extraction provider returned no structured result');
      }
      return { data: ExtractedInvoiceSchema.parse(response.output_parsed), provider: 'openai', model, usage: response.usage ? JSON.parse(JSON.stringify(response.usage)) : null };
    } catch (error) {
      const providerError = error as { status?: number; code?: string; type?: string; request_id?: string };
      this.logger.warn(JSON.stringify({ event: 'invoice_extraction_provider_error', errorType: error instanceof Error ? error.name : 'UnknownError', status: providerError.status ?? null, code: providerError.code ?? null, type: providerError.type ?? null, requestId: providerError.request_id ?? null }));
      throw error;
    }
  }
}
