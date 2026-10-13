import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { BankService } from './bank.service';
import { AssignBankAccountDto, BankSyncStatusQuery, BankTransactionQuery, BulkReviewBankTransactionsDto, ConfirmInvoiceMatchDto, ExchangeBankTokenDto, OrganizationDto, ReviewBankTransactionDto, UpdateMerchantRuleDto } from './dto';

@ApiTags('banking') @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Controller()
export class BankController {
  constructor(private readonly service: BankService) {}
  @Post('bank/link-token') linkToken(@CurrentUser() u: { sub: string }, @Body() d: OrganizationDto) { return this.service.linkToken(u.sub, d.organizationId); }
  @Post('bank/connections/:id/link-token') reauthenticationLinkToken(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.service.reauthenticationLinkToken(u.sub, id); }
  @Post('bank/connections/:id/reauthenticated') reauthenticated(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.service.completeReauthentication(u.sub, id); }
  @Post('bank/exchange-token') exchange(@CurrentUser() u: { sub: string }, @Body() d: ExchangeBankTokenDto) { return this.service.exchange(u.sub, d); }
  @Get('bank/connections') connections(@CurrentUser() u: { sub: string }, @Query('organizationId') organizationId: string) { return this.service.connections(u.sub, organizationId); }
  @Get('bank/sync-status') syncStatus(@CurrentUser() u: { sub: string }, @Query() q: BankSyncStatusQuery) { return this.service.syncStatus(u.sub, q.organizationId, q.restaurantLocationId); }
  @Patch('bank/accounts/:id') account(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Body() d: AssignBankAccountDto) { return this.service.assignAccount(u.sub, id, d); }
  @Post('bank/connections/:id/sync') sync(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.service.sync(u.sub, id); }
  @HttpCode(204) @Delete('bank/connections/:id') disconnect(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.service.disconnect(u.sub, id); }
  @Get('bank-transactions') transactions(@CurrentUser() u: { sub: string }, @Query() q: BankTransactionQuery) { return this.service.transactions(u.sub, q); }
  @Patch('bank-transactions/:id/review') review(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Body() d: ReviewBankTransactionDto) { return this.service.review(u.sub, id, d); }
  @Post('bank-transactions/bulk-review') bulkReview(@CurrentUser() u: { sub: string }, @Body() d: BulkReviewBankTransactionsDto) { return this.service.bulkReview(u.sub, d); }
  @Post('bank-transactions/:id/reverse') reverse(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.service.reverseReconciliation(u.sub, id); }
  @Post('bank-transactions/:id/confirm-match') confirm(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Body() d: ConfirmInvoiceMatchDto) { return this.service.confirmMatch(u.sub, id, d); }
  @Post('bank-transactions/:id/reject-match') reject(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.service.rejectMatch(u.sub, id); }
  @Get('bank/merchant-rules') merchantRules(@CurrentUser() u: { sub: string }, @Query('organizationId') organizationId: string, @Query('restaurantLocationId') locationId: string) { return this.service.merchantRules(u.sub, organizationId, locationId); }
  @Patch('bank/merchant-rules/:id') updateMerchantRule(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Body() d: UpdateMerchantRuleDto) { return this.service.updateMerchantRule(u.sub, id, d); }
}
