import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CompleteUploadDto, InvoiceListQuery, ReviewInvoiceDto, UpdateInvoiceDto, UpdateLineItemDto, UploadIntentDto } from './dto';
import { InvoicesService } from './invoices.service';

@ApiTags('invoices')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('invoices')
export class InvoicesController {
  constructor(private readonly invoices: InvoicesService) {}
  @Post('upload-intent') intent(@CurrentUser() u: { sub: string }, @Body() data: UploadIntentDto) { return this.invoices.uploadIntent(u.sub, data); }
  @Post(':id/upload-complete') complete(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Body() data: CompleteUploadDto) { return this.invoices.complete(u.sub, id, data); }
  @Post(':id/extract') extract(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.invoices.startExtraction(u.sub, id); }
  @Get(':id/extraction-status') extractionStatus(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.invoices.extractionStatus(u.sub, id); }
  @Get(':id/line-items') lineItems(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.invoices.lineItems(u.sub, id); }
  @Patch(':invoiceId/line-items/:lineItemId') updateLineItem(@CurrentUser() u: { sub: string }, @Param('invoiceId') invoiceId: string, @Param('lineItemId') lineItemId: string, @Body() data: UpdateLineItemDto) { return this.invoices.updateLineItem(u.sub, invoiceId, lineItemId, data); }
  @Patch(':id/review') review(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Body() data: ReviewInvoiceDto) { return this.invoices.review(u.sub, id, data); }
  @Get() list(@CurrentUser() u: { sub: string }, @Query() query: InvoiceListQuery) { return this.invoices.list(u.sub, query); }
  @Get(':id') detail(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.invoices.detail(u.sub, id); }
  @Patch(':id') update(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Body() data: UpdateInvoiceDto) { return this.invoices.update(u.sub, id, data); }
  @HttpCode(204) @Delete(':id') delete(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.invoices.delete(u.sub, id); }
}
