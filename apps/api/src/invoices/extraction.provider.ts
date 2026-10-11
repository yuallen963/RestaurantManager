import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import OpenAI from 'openai';
import { zodTextFormat } from 'openai/helpers/zod';
import { GoogleGenAI } from '@google/genai';
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
  private provider() {
    const configured = this.config.get<string>('INVOICE_AI_PROVIDER')?.trim().toLowerCase();
    const value = configured || (this.config.get<string>('GEMINI_API_KEY') && !this.config.get<string>('OPENAI_API_KEY') ? 'gemini' : 'openai');
    if (value !== 'openai' && value !== 'gemini') throw new ServiceUnavailableException(`Unsupported invoice AI provider: ${value}`);
    return value;
  }
  isConfigured() {
    const provider = this.provider();
    return Boolean(this.config.get<string>(provider === 'gemini' ? 'GEMINI_API_KEY' : 'OPENAI_API_KEY'));
  }
  async extract(file: Buffer, mimeType: string, fileName: string) {
    const provider = this.provider();
    if (provider === 'gemini') return this.extractGemini(file, mimeType, fileName);
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

  private async extractGemini(file: Buffer, mimeType: string, fileName: string) {
    if (!['application/pdf', 'image/jpeg', 'image/png'].includes(mimeType)) throw new Error('Unsupported invoice file type');
    const apiKey = this.config.get<string>('GEMINI_API_KEY');
    if (!apiKey) throw new ServiceUnavailableException('Invoice extraction is not configured');
    const model = this.config.get<string>('GEMINI_INVOICE_MODEL') ?? 'gemini-3.5-flash-lite';
    const ai = new GoogleGenAI({ apiKey });
    const prompt = `Extract this restaurant vendor invoice, including every page as one invoice. Preserve every line item rawDescription and packSize exactly as printed; never rewrite rawDescription. Combine line items across pages and do not duplicate headers, footers, subtotals, or totals. sourcePage is the one-based page number when clear. normalizedName and productAttributes are interpretations only. Normalize dates to YYYY-MM-DD. Use null when absent or unclear, and list ambiguous field names in uncertainFields. Do not invent package quantities or confidence scores. Return JSON matching the requested schema. Filename: ${fileName}. Today is ${new Date().toISOString().slice(0, 10)}.`;
    const responseSchema = {
      type: 'object', required: ['vendorName', 'vendorAddress', 'invoiceNumber', 'invoiceDate', 'dueDate', 'subtotal', 'tax', 'otherFees', 'total', 'currency', 'uncertainFields', 'lineItems'],
      properties: {
        vendorName: { type: ['string', 'null'] }, vendorAddress: { type: ['string', 'null'] }, invoiceNumber: { type: ['string', 'null'] }, invoiceDate: { type: ['string', 'null'] }, dueDate: { type: ['string', 'null'] }, subtotal: { type: ['number', 'null'] }, tax: { type: ['number', 'null'] }, otherFees: { type: ['number', 'null'] }, total: { type: ['number', 'null'] }, currency: { type: ['string', 'null'] }, uncertainFields: { type: 'array', items: { type: 'string' } },
        lineItems: { type: 'array', items: { type: 'object', required: ['lineNumber', 'sourcePage', 'rawDescription', 'normalizedName', 'sku', 'quantity', 'unit', 'packSize', 'unitPrice', 'extendedPrice', 'category', 'productAttributes', 'uncertainFields'], properties: {
          lineNumber: { type: 'integer' }, sourcePage: { type: ['integer', 'null'] }, rawDescription: { type: 'string' }, normalizedName: { type: ['string', 'null'] }, sku: { type: ['string', 'null'] }, quantity: { type: ['number', 'null'] }, unit: { type: ['string', 'null'] }, packSize: { type: ['string', 'null'] }, unitPrice: { type: ['number', 'null'] }, extendedPrice: { type: ['number', 'null'] }, category: { type: ['string', 'null'], enum: ['Food', 'Beverage', 'Alcohol', 'Supplies', 'Cleaning', 'Packaging', 'Other', null] }, productAttributes: { type: ['object', 'null'] }, uncertainFields: { type: 'array', items: { type: 'string' } },
        } } },
      },
    };
    try {
      const response = await ai.models.generateContent({ model, contents: [{ role: 'user', parts: [{ inlineData: { mimeType, data: file.toString('base64') } }, { text: prompt }] }], config: { responseMimeType: 'application/json', responseSchema } });
      const text = response.text?.trim();
      if (!text) throw new Error('Extraction provider returned no structured result');
      const data = ExtractedInvoiceSchema.parse(JSON.parse(text));
      const usage = response.usageMetadata;
      return { data, provider: 'gemini', model, usage: usage ? { input_tokens: usage.promptTokenCount, output_tokens: usage.candidatesTokenCount, total_tokens: usage.totalTokenCount } : null };
    } catch (error) {
      this.logger.warn(JSON.stringify({ event: 'invoice_extraction_provider_error', provider: 'gemini', errorType: error instanceof Error ? error.name : 'UnknownError', status: (error as { status?: number }).status ?? null, message: error instanceof Error ? error.message.slice(0, 300) : null }));
      throw error;
    }
  }
}
