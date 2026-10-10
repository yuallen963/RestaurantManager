import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { BankService } from './bank.service';
import { AssignBankAccountDto, BankTransactionQuery, ConfirmInvoiceMatchDto, ExchangeBankTokenDto, OrganizationDto, ReviewBankTransactionDto } from './dto';

@ApiTags('banking') @ApiBearerAuth() @UseGuards(JwtAuthGuard) @Controller()
export class BankController {
  constructor(private readonly service: BankService) {}
  @Post('bank/link-token') linkToken(@CurrentUser() u: { sub: string }, @Body() d: OrganizationDto) { return this.service.linkToken(u.sub, d.organizationId); }
  @Post('bank/connections/:id/link-token') reauthenticationLinkToken(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.service.reauthenticationLinkToken(u.sub, id); }
  @Post('bank/connections/:id/reauthenticated') reauthenticated(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.service.completeReauthentication(u.sub, id); }
  @Post('bank/exchange-token') exchange(@CurrentUser() u: { sub: string }, @Body() d: ExchangeBankTokenDto) { return this.service.exchange(u.sub, d); }
  @Get('bank/connections') connections(@CurrentUser() u: { sub: string }, @Query('organizationId') organizationId: string) { return this.service.connections(u.sub, organizationId); }
  @Patch('bank/accounts/:id') account(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Body() d: AssignBankAccountDto) { return this.service.assignAccount(u.sub, id, d); }
  @Post('bank/connections/:id/sync') sync(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.service.sync(u.sub, id); }
  @HttpCode(204) @Delete('bank/connections/:id') disconnect(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.service.disconnect(u.sub, id); }
  @Get('bank-transactions') transactions(@CurrentUser() u: { sub: string }, @Query() q: BankTransactionQuery) { return this.service.transactions(u.sub, q); }
  @Patch('bank-transactions/:id/review') review(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Body() d: ReviewBankTransactionDto) { return this.service.review(u.sub, id, d); }
  @Post('bank-transactions/:id/confirm-match') confirm(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Body() d: ConfirmInvoiceMatchDto) { return this.service.confirmMatch(u.sub, id, d); }
  @Post('bank-transactions/:id/reject-match') reject(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.service.rejectMatch(u.sub, id); }
}
