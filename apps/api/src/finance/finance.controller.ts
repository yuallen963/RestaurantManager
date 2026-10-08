import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CreateExpenseDto, CreateRevenueDto, CreateVendorDto, ExpenseListQuery, RevenueListQuery, UpdateExpenseDto, UpdateRevenueDto, UpdateVendorDto, VendorDetailQuery, VendorSummaryQuery } from './dto';
import { FinanceService } from './finance.service';

@ApiTags('financial-data')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class FinanceController {
  constructor(private readonly s: FinanceService) {}
  @Get('revenue') revenues(@CurrentUser() u: { sub: string }, @Query() q: RevenueListQuery) { return this.s.revenues(u.sub, q); }
  @Post('revenue') revenue(@CurrentUser() u: { sub: string }, @Body() d: CreateRevenueDto) { return this.s.revenue(u.sub, d); }
  @Get('revenue/:id') revenueDetail(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.s.revenueDetail(u.sub, id); }
  @Patch('revenue/:id') updateRevenue(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Body() d: UpdateRevenueDto) { return this.s.updateRevenue(u.sub, id, d); }
  @HttpCode(204) @Delete('revenue/:id') deleteRevenue(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.s.deleteRevenue(u.sub, id); }
  @Get('expenses') expenses(@CurrentUser() u: { sub: string }, @Query() q: ExpenseListQuery) { return this.s.expenses(u.sub, q); }
  @Post('expenses') expense(@CurrentUser() u: { sub: string }, @Body() d: CreateExpenseDto) { return this.s.expense(u.sub, d); }
  @Get('expenses/:id') expenseDetail(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.s.expenseDetail(u.sub, id); }
  @Patch('expenses/:id') updateExpense(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Body() d: UpdateExpenseDto) { return this.s.updateExpense(u.sub, id, d); }
  @HttpCode(204) @Delete('expenses/:id') deleteExpense(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.s.deleteExpense(u.sub, id); }
  @Get('expense-categories') categories(@CurrentUser() u: { sub: string }, @Query('organizationId') o: string) { return this.s.categories(u.sub, o); }
  @Get('vendors') vendors(@CurrentUser() u: { sub: string }, @Query('organizationId') o: string) { return this.s.vendors(u.sub, o); }
  @Get('vendor-summaries') vendorSummaries(@CurrentUser() u: { sub: string }, @Query() q: VendorSummaryQuery) { return this.s.vendorSummaries(u.sub, q); }
  @Get('vendor-summaries/:id') vendorSummary(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Query() q: VendorDetailQuery) { return this.s.vendorSummary(u.sub, id, q); }
  @Post('vendors') vendor(@CurrentUser() u: { sub: string }, @Body() d: CreateVendorDto) { return this.s.vendor(u.sub, d); }
  @Get('vendors/:id') vendorDetail(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.s.vendorDetail(u.sub, id); }
  @Patch('vendors/:id') updateVendor(@CurrentUser() u: { sub: string }, @Param('id') id: string, @Body() d: UpdateVendorDto) { return this.s.updateVendor(u.sub, id, d); }
  @HttpCode(204) @Delete('vendors/:id') deleteVendor(@CurrentUser() u: { sub: string }, @Param('id') id: string) { return this.s.deleteVendor(u.sub, id); }
}
