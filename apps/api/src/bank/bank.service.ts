import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { BankCategorizationSource, BankConnectionStatus, BankProvider, BankReconciliationStatus, ExpenseSource, InvoiceMatchConfidence, MerchantRuleMatchType, Prisma, ReviewStatus } from '@prisma/client';
import { AuditService } from '../audit.service';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PrismaService } from '../prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { AssignBankAccountDto, BankTransactionQuery, ConfirmInvoiceMatchDto, ExchangeBankTokenDto, ReviewBankTransactionDto } from './dto';
import { BankTokenEncryptionService } from './encryption.service';
import { BankProviderFactory, ProviderTransaction } from './bank.provider';

const cleanMerchant = (value?: string | null) => (value ?? '').toUpperCase().replace(/\b(ACH|POS|PAYMENT|PURCHASE|DEBIT|CREDIT|ONLINE)\b/g, ' ').replace(/[#*]\s*\d+|\b\d{3,}\b/g, ' ').replace(/[^A-Z0-9]+/g, ' ').trim().replace(/\s+/g, ' ');
export const normalizeMerchant = (value?: string | null) => {
  const clean = cleanMerchant(value);
  if (/\bSYSCO\b/.test(clean)) return 'Sysco';
  if (/\bADP\b/.test(clean)) return 'ADP';
  if (/\bDTE\b/.test(clean)) return 'DTE Energy';
  if (/\bUS\s*FOODS?\b/.test(clean)) return 'US Foods';
  if (/\bGFS\b|\bGORDON FOOD SERVICE\b/.test(clean)) return 'Gordon Food Service';
  if (/\bRESTAURANT DEPOT\b/.test(clean)) return 'Restaurant Depot';
  return clean.toLowerCase().replace(/\b\w/g, (letter) => letter.toUpperCase());
};

@Injectable()
export class BankService {
  constructor(private readonly prisma: PrismaService, private readonly access: OrganizationAccessService, private readonly audit: AuditService, private readonly encryption: BankTokenEncryptionService, private readonly providers: BankProviderFactory, private readonly notifications?: NotificationsService) {}

  private async organization(userId: string, organizationId: string) { await this.access.requireMember(userId, organizationId); return organizationId; }
  private async connection(userId: string, id: string) { const row = await this.prisma.bankConnection.findUnique({ where: { id }, include: { accounts: true } }); if (!row) throw new NotFoundException('Bank connection not found'); await this.organization(userId, row.organizationId); return row; }
  private async account(userId: string, id: string) { const row = await this.prisma.bankAccount.findUnique({ where: { id } }); if (!row) throw new NotFoundException('Bank account not found'); await this.organization(userId, row.organizationId); return row; }
  private async transaction(userId: string, id: string) { const row = await this.prisma.bankTransaction.findUnique({ where: { id } }); if (!row) throw new NotFoundException('Bank transaction not found'); await this.organization(userId, row.organizationId); return row; }
  private safeConnection(row: any) { const { encryptedAccessToken: _secret, ...safe } = row; return safe; }

  async linkToken(userId: string, organizationId: string) {
    await this.organization(userId, organizationId);
    const provider = this.providers.get();
    return { linkToken: await provider.createLinkToken(userId), provider: provider.name, demo: provider.name === 'DEMO' };
  }

  async reauthenticationLinkToken(userId: string, id: string) {
    const connection = await this.connection(userId, id);
    if (connection.status === BankConnectionStatus.DISCONNECTED) throw new BadRequestException('Bank connection is disconnected');
    const provider = this.providers.get(connection.provider);
    return { linkToken: await provider.createLinkToken(userId, this.encryption.decrypt(connection.encryptedAccessToken)), provider: provider.name, demo: provider.name === 'DEMO', updateMode: true };
  }

  async completeReauthentication(userId: string, id: string) {
    const connection = await this.connection(userId, id);
    if (connection.status === BankConnectionStatus.DISCONNECTED) throw new BadRequestException('Bank connection is disconnected');
    await this.prisma.bankConnection.update({ where: { id }, data: { status: BankConnectionStatus.CONNECTED, lastError: null } });
    await this.audit.log({ userId, organizationId: connection.organizationId, action: 'bank.reauthenticated', entityType: 'BankConnection', entityId: id });
    return this.sync(userId, id);
  }

  async exchange(userId: string, data: ExchangeBankTokenDto) {
    await this.organization(userId, data.organizationId);
    if (data.restaurantLocationId) await this.validateLocation(data.organizationId, data.restaurantLocationId);
    const provider = this.providers.get();
    const exchanged = await provider.exchange(data.publicToken);
    const existing = await this.prisma.bankConnection.findUnique({ where: { provider_providerItemId: { provider: provider.name as BankProvider, providerItemId: exchanged.itemId } }, include: { accounts: true } });
    if (existing && existing.organizationId !== data.organizationId) throw new ConflictException('This bank connection is already linked to another organization');
    const connection = existing
      ? await this.prisma.bankConnection.update({ where: { id: existing.id }, data: { encryptedAccessToken: this.encryption.encrypt(exchanged.accessToken), institutionId: exchanged.institutionId, institutionName: exchanged.institutionName, status: BankConnectionStatus.CONNECTED, lastError: null, accounts: { upsert: exchanged.accounts.map((account) => ({ where: { bankConnectionId_providerAccountId: { bankConnectionId: existing.id, providerAccountId: account.id } }, create: { organizationId: data.organizationId, restaurantLocationId: data.restaurantLocationId, providerAccountId: account.id, name: account.name, mask: account.mask?.slice(-4), subtype: account.subtype, type: account.type }, update: { name: account.name, mask: account.mask?.slice(-4), subtype: account.subtype, type: account.type, active: true } })) } }, include: { accounts: true } })
      : await this.prisma.bankConnection.create({ data: { organizationId: data.organizationId, provider: provider.name as BankProvider, providerItemId: exchanged.itemId, encryptedAccessToken: this.encryption.encrypt(exchanged.accessToken), institutionId: exchanged.institutionId, institutionName: exchanged.institutionName, createdByUserId: userId, accounts: { create: exchanged.accounts.map((account) => ({ organizationId: data.organizationId, restaurantLocationId: data.restaurantLocationId, providerAccountId: account.id, name: account.name, mask: account.mask?.slice(-4), subtype: account.subtype, type: account.type })) } }, include: { accounts: true } });
    await this.audit.log({ userId, organizationId: data.organizationId, action: 'bank.connected', entityType: 'BankConnection', entityId: connection.id, metadata: { provider: provider.name, accountCount: exchanged.accounts.length } });
    await this.sync(userId, connection.id);
    return this.safeConnection(await this.prisma.bankConnection.findUnique({ where: { id: connection.id }, include: { accounts: true } }));
  }

  async connections(userId: string, organizationId: string) {
    await this.organization(userId, organizationId);
    const rows = await this.prisma.bankConnection.findMany({ where: { organizationId }, include: { accounts: { include: { restaurantLocation: { select: { id: true, name: true } } } } }, orderBy: { createdAt: 'desc' } });
    return rows.map((row) => this.safeConnection(row));
  }

  async assignAccount(userId: string, id: string, data: AssignBankAccountDto) {
    const account = await this.account(userId, id);
    if (data.restaurantLocationId) await this.validateLocation(account.organizationId, data.restaurantLocationId);
    const saved = await this.prisma.bankAccount.update({ where: { id }, data: { restaurantLocationId: data.restaurantLocationId, active: data.active } });
    if (data.restaurantLocationId !== undefined) await this.prisma.bankTransaction.updateMany({ where: { bankAccountId: id, reconciliationStatus: { in: [BankReconciliationStatus.UNMATCHED, BankReconciliationStatus.NEEDS_REVIEW] } }, data: { restaurantLocationId: data.restaurantLocationId ?? null, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW } });
    await this.audit.log({ userId, organizationId: account.organizationId, action: 'bank.account_location_changed', entityType: 'BankAccount', entityId: id, metadata: { restaurantLocationId: data.restaurantLocationId ?? null } });
    return saved;
  }

  async sync(userId: string, id: string) {
    const connection = await this.connection(userId, id);
    if (connection.status === BankConnectionStatus.DISCONNECTED) throw new BadRequestException('Bank connection is disconnected');
    const staleBefore = new Date(Date.now() - 10 * 60 * 1000);
    const locked = await this.prisma.bankConnection.updateMany({ where: { id, OR: [{ status: { not: BankConnectionStatus.SYNCING } }, { updatedAt: { lt: staleBefore } }] }, data: { status: BankConnectionStatus.SYNCING, lastError: null } });
    if (!locked.count) throw new ConflictException('Bank connection is already syncing');
    try {
      const updates = await this.providers.get(connection.provider).sync(this.encryption.decrypt(connection.encryptedAccessToken), connection.syncCursor);
      for (const removedId of updates.removed) await this.prisma.bankTransaction.updateMany({ where: { bankAccount: { bankConnectionId: id }, providerTransactionId: removedId }, data: { removedAt: new Date(), reconciliationStatus: BankReconciliationStatus.IGNORED } });
      for (const transaction of [...updates.added, ...updates.modified]) await this.ingest(connection.organizationId, connection.accounts, transaction);
      const saved = await this.prisma.bankConnection.update({ where: { id }, data: { syncCursor: updates.cursor, status: BankConnectionStatus.CONNECTED, lastSyncAt: new Date(), lastError: null } });
      await this.audit.log({ userId, organizationId: connection.organizationId, action: 'bank.synced', entityType: 'BankConnection', entityId: id, metadata: { added: updates.added.length, modified: updates.modified.length, removed: updates.removed.length } });
      return this.safeConnection(saved);
    } catch (error) {
      const reauth = error instanceof UnauthorizedException;
      await this.prisma.bankConnection.update({ where: { id }, data: { status: reauth ? BankConnectionStatus.NEEDS_ATTENTION : BankConnectionStatus.ERROR, lastError: reauth ? 'Reconnect your bank to continue syncing.' : 'Unable to sync this connection. Try again.' } });
      await this.audit.log({ userId, organizationId: connection.organizationId, action: 'bank.sync_failed', entityType: 'BankConnection', entityId: id, metadata: { reauthRequired: reauth } });
      await this.notifications?.notifyOperational({ organizationId: connection.organizationId, type: reauth ? 'BANK_REAUTH_REQUIRED' : 'BANK_SYNC_FAILED', severity: 'HIGH', title: reauth ? 'Reconnect your bank account' : 'Bank sync failed', body: reauth ? 'Reconnect your bank account to continue syncing transactions.' : 'We could not sync this bank connection. Try again shortly.', deepLinkType: 'OPEN_BANK_ACCOUNTS', deepLinkId: id, dedupeKey: reauth ? `bank-reauth:${id}` : `bank-sync-failed:${id}:${error instanceof Error ? error.name : 'unknown'}` });
      throw error;
    }
  }

  private async ingest(organizationId: string, accounts: any[], transaction: ProviderTransaction) {
    const account = accounts.find((candidate) => candidate.providerAccountId === transaction.accountId);
    if (!account || !account.active) return;
    const merchant = normalizeMerchant(transaction.merchantName ?? transaction.description);
    const categorization = await this.categorize(organizationId, account.restaurantLocationId, merchant, transaction.categoryId ?? transaction.category);
    const invoiceMatch = account.restaurantLocationId && transaction.amount > 0 ? await this.matchInvoice(organizationId, account.restaurantLocationId, categorization.vendorId, merchant, transaction.amount, new Date(transaction.date)) : null;
    const raw = { restaurantLocationId: account.restaurantLocationId, postedDate: new Date(transaction.date), authorizedDate: transaction.authorizedDate ? new Date(transaction.authorizedDate) : null, merchantNameRaw: transaction.merchantName, merchantNameNormalized: merchant, description: transaction.description, amount: new Prisma.Decimal(transaction.amount), pending: transaction.pending, providerCategory: transaction.category, providerCategoryId: transaction.categoryId, removedAt: null };
    const proposed = { ...raw, categoryId: categorization.categoryId, vendorId: categorization.vendorId, suggestedInvoiceId: invoiceMatch?.invoiceId, matchConfidence: invoiceMatch?.confidence ?? InvoiceMatchConfidence.NO_MATCH, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW, categorizationSource: categorization.source };
    const posted = await this.prisma.bankTransaction.findUnique({ where: { bankAccountId_providerTransactionId: { bankAccountId: account.id, providerTransactionId: transaction.id } } });
    const pending = transaction.pendingTransactionId ? await this.prisma.bankTransaction.findFirst({ where: { bankAccountId: account.id, providerTransactionId: transaction.pendingTransactionId, pending: true } }) : null;
    if (posted) {
      if (pending && pending.id !== posted.id) await this.prisma.bankTransaction.delete({ where: { id: pending.id } });
      const amountChanged = posted.amount != null && !new Prisma.Decimal(posted.amount).eq(transaction.amount);
      const dateChanged = posted.postedDate && new Date(posted.postedDate).toISOString().slice(0, 10) !== transaction.date;
      let reconciliation = {};
      if (posted.expenseId && (amountChanged || dateChanged)) {
        const expense = await this.prisma.expense.findUnique({ where: { id: posted.expenseId } });
        if (expense?.source === ExpenseSource.BANK_IMPORT) {
          await this.prisma.expense.update({ where: { id: expense.id }, data: { amount: raw.amount, date: raw.postedDate, description: raw.description } });
        } else {
          reconciliation = { expenseId: null, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW };
        }
      }
      await this.prisma.bankTransaction.update({ where: { id: posted.id }, data: { ...raw, ...reconciliation } });
      return;
    }
    if (pending) {
      await this.prisma.bankTransaction.update({ where: { id: pending.id }, data: { ...raw, providerTransactionId: transaction.id, suggestedInvoiceId: pending.suggestedInvoiceId ?? invoiceMatch?.invoiceId, matchConfidence: pending.matchConfidence === InvoiceMatchConfidence.NO_MATCH ? invoiceMatch?.confidence ?? InvoiceMatchConfidence.NO_MATCH : pending.matchConfidence } });
      return;
    }
    await this.prisma.bankTransaction.create({ data: { organizationId, bankAccountId: account.id, providerTransactionId: transaction.id, ...proposed } });
  }

  private async categorize(organizationId: string, locationId: string | null, merchant: string, providerCategory?: string) {
    const canonical = cleanMerchant(merchant);
    const rules = await this.prisma.merchantRule.findMany({ where: { organizationId, OR: [{ restaurantLocationId: locationId }, { restaurantLocationId: null }] }, orderBy: [{ restaurantLocationId: 'desc' }, { createdAt: 'asc' }] });
    const rule = rules.find((candidate) => candidate.matchType === MerchantRuleMatchType.EXACT ? canonical === candidate.matchValue : candidate.matchType === MerchantRuleMatchType.PREFIX ? canonical.startsWith(candidate.matchValue) : canonical.includes(candidate.matchValue));
    if (rule) return { vendorId: rule.vendorId, categoryId: rule.expenseCategoryId, source: BankCategorizationSource.USER_RULE };
    const vendors = await this.prisma.vendor.findMany({ where: { organizationId }, select: { id: true, normalizedName: true } });
    const vendor = vendors.find((candidate) => canonical.includes(cleanMerchant(candidate.normalizedName)) || cleanMerchant(candidate.normalizedName).includes(canonical));
    if (vendor) return { vendorId: vendor.id, categoryId: null, source: BankCategorizationSource.MERCHANT_RULE };
    const mapping: Record<string, string> = { UTILITIES: 'utilities', PAYROLL: 'labor' };
    const slug = Object.entries(mapping).find(([key]) => (providerCategory ?? '').toUpperCase().includes(key))?.[1];
    const category = slug ? await this.prisma.expenseCategory.findFirst({ where: { slug, OR: [{ organizationId: null }, { organizationId }] }, select: { id: true } }) : null;
    return { vendorId: null, categoryId: category?.id ?? null, source: category ? BankCategorizationSource.PROVIDER : BankCategorizationSource.UNRESOLVED };
  }

  private async matchInvoice(organizationId: string, locationId: string, vendorId: string | null, merchant: string, amount: number, postedDate: Date) {
    const earliest = new Date(postedDate); earliest.setUTCDate(earliest.getUTCDate() - 30);
    const candidates = await this.prisma.invoice.findMany({ where: { organizationId, restaurantLocationId: locationId, reviewStatus: ReviewStatus.REVIEWED, invoiceDate: { gte: earliest, lte: postedDate }, total: { not: null }, bankTransactions: { none: { reconciliationStatus: BankReconciliationStatus.MATCHED_INVOICE } } }, orderBy: { invoiceDate: 'desc' } });
    for (const invoice of candidates) {
      const vendorMatches = vendorId ? invoice.vendorId === vendorId : cleanMerchant(invoice.extractedVendorName).includes(cleanMerchant(merchant)) || cleanMerchant(merchant).includes(cleanMerchant(invoice.extractedVendorName));
      if (!vendorMatches) continue;
      const difference = Math.abs(Number(invoice.total) - amount);
      if (difference <= .01) return { invoiceId: invoice.id, confidence: InvoiceMatchConfidence.EXACT };
      if (difference <= .5) return { invoiceId: invoice.id, confidence: InvoiceMatchConfidence.LIKELY };
    }
    return null;
  }

  async transactions(userId: string, query: BankTransactionQuery) {
    await this.organization(userId, query.organizationId);
    if (query.restaurantLocationId) await this.validateLocation(query.organizationId, query.restaurantLocationId);
    const rows = await this.prisma.bankTransaction.findMany({ where: { organizationId: query.organizationId, restaurantLocationId: query.restaurantLocationId, reconciliationStatus: query.status, removedAt: null }, include: { category: { select: { id: true, name: true } }, vendor: { select: { id: true, name: true } }, invoice: { select: { id: true, invoiceNumber: true } }, bankAccount: { select: { id: true, name: true, mask: true } } }, orderBy: [{ postedDate: 'desc' }, { id: 'asc' }] });
    const suggested = await this.prisma.invoice.findMany({ where: { id: { in: rows.map((row) => row.suggestedInvoiceId).filter(Boolean) as string[] }, organizationId: query.organizationId }, select: { id: true, invoiceNumber: true, total: true } });
    const byId = new Map(suggested.map((invoice) => [invoice.id, invoice]));
    return rows.map((row) => ({ ...row, suggestedInvoice: row.suggestedInvoiceId ? byId.get(row.suggestedInvoiceId) ?? null : null }));
  }

  async review(userId: string, id: string, data: ReviewBankTransactionDto) {
    const transaction = await this.transaction(userId, id);
    if (data.restaurantLocationId) await this.validateLocation(transaction.organizationId, data.restaurantLocationId);
    if (data.vendorId && !(await this.prisma.vendor.findFirst({ where: { id: data.vendorId, organizationId: transaction.organizationId } }))) throw new ForbiddenException('Vendor is not available');
    if (data.categoryId && !(await this.prisma.expenseCategory.findFirst({ where: { id: data.categoryId, OR: [{ organizationId: null }, { organizationId: transaction.organizationId }] } }))) throw new ForbiddenException('Category is not available');
    const locationId = data.restaurantLocationId ?? transaction.restaurantLocationId;
    const vendorId = data.vendorId === undefined ? transaction.vendorId : data.vendorId;
    const categoryId = data.categoryId === undefined ? transaction.categoryId : data.categoryId;
    let saved;
    if (data.ignored) {
      saved = await this.prisma.bankTransaction.update({ where: { id }, data: { vendorId, categoryId, restaurantLocationId: locationId, categorizationSource: BankCategorizationSource.MANUAL, reconciliationStatus: BankReconciliationStatus.IGNORED } });
    } else if (transaction.pending) {
      saved = await this.prisma.bankTransaction.update({ where: { id }, data: { vendorId, categoryId, restaurantLocationId: locationId, categorizationSource: BankCategorizationSource.MANUAL, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW } });
    } else {
      if (!locationId) throw new BadRequestException('Assign a restaurant location before reconciling this transaction');
      if (!categoryId) throw new BadRequestException('Select an expense category before reconciling this transaction');
      if (transaction.amount.lte(0)) throw new BadRequestException('Credits cannot be reconciled as expenses');
      if (transaction.suggestedInvoiceId) throw new BadRequestException('Confirm or reject the suggested invoice match first');
      saved = await this.prisma.$transaction(async (tx) => {
        const current = await tx.bankTransaction.findUnique({ where: { id } });
        if (!current) throw new NotFoundException('Bank transaction not found');
        if (current.expenseId) return tx.bankTransaction.update({ where: { id }, data: { vendorId, categoryId, restaurantLocationId: locationId, categorizationSource: BankCategorizationSource.MANUAL, reconciliationStatus: BankReconciliationStatus.MATCHED_EXPENSE } });
        const start = new Date(current.postedDate); start.setUTCDate(start.getUTCDate() - 3);
        const end = new Date(current.postedDate); end.setUTCDate(end.getUTCDate() + 3);
        const matchingExpenses = await tx.expense.findMany({ where: { organizationId: current.organizationId, restaurantLocationId: locationId, amount: current.amount, date: { gte: start, lte: end }, vendorId: vendorId ?? undefined, expenseCategoryId: categoryId, bankTransactions: { none: {} } }, take: 2 });
        if (matchingExpenses.length > 1) throw new ConflictException('Multiple matching expenses require manual reconciliation');
        const expense = matchingExpenses[0] ?? await tx.expense.create({ data: { organizationId: current.organizationId, restaurantLocationId: locationId, vendorId, expenseCategoryId: categoryId, amount: current.amount, date: current.postedDate, description: current.description, source: ExpenseSource.BANK_IMPORT, createdByUserId: userId } });
        return tx.bankTransaction.update({ where: { id }, data: { vendorId, categoryId, restaurantLocationId: locationId, expenseId: expense.id, categorizationSource: BankCategorizationSource.MANUAL, reconciliationStatus: BankReconciliationStatus.MATCHED_EXPENSE } });
      }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    }
    await this.audit.log({ userId, organizationId: transaction.organizationId, action: data.ignored ? 'bank.transaction_ignored' : 'bank.transaction_categorized', entityType: 'BankTransaction', entityId: id });
    if (data.createMerchantRule && transaction.merchantNameNormalized) {
      const matchValue = cleanMerchant(transaction.merchantNameNormalized);
      const locationId = data.restaurantLocationId ?? transaction.restaurantLocationId;
      const matchType = data.ruleMatchType ?? MerchantRuleMatchType.EXACT;
      const existing = await this.prisma.merchantRule.findFirst({ where: { organizationId: transaction.organizationId, restaurantLocationId: locationId, matchType, matchValue } });
      const rule = existing
        ? await this.prisma.merchantRule.update({ where: { id: existing.id }, data: { vendorId: data.vendorId ?? transaction.vendorId, expenseCategoryId: data.categoryId ?? transaction.categoryId, normalizedMerchantName: transaction.merchantNameNormalized } })
        : await this.prisma.merchantRule.create({ data: { organizationId: transaction.organizationId, restaurantLocationId: locationId, matchType, matchValue, normalizedMerchantName: transaction.merchantNameNormalized, vendorId: data.vendorId ?? transaction.vendorId, expenseCategoryId: data.categoryId ?? transaction.categoryId, createdByUserId: userId } });
      await this.audit.log({ userId, organizationId: transaction.organizationId, action: 'bank.merchant_rule_created', entityType: 'MerchantRule', entityId: rule.id });
    }
    return saved;
  }

  async confirmMatch(userId: string, id: string, data: ConfirmInvoiceMatchDto) {
    const transaction = await this.transaction(userId, id);
    if (transaction.pending) throw new BadRequestException('Wait for the transaction to post before matching an invoice');
    if (transaction.expenseId) throw new BadRequestException('Transaction is already reconciled to an expense');
    if (!transaction.restaurantLocationId) throw new BadRequestException('Assign a restaurant location first');
    if (transaction.suggestedInvoiceId !== data.invoiceId) throw new BadRequestException('Invoice is not a current match candidate');
    const invoice = await this.prisma.invoice.findFirst({ where: { id: data.invoiceId, organizationId: transaction.organizationId, restaurantLocationId: transaction.restaurantLocationId, reviewStatus: ReviewStatus.REVIEWED } });
    if (!invoice) throw new ForbiddenException('Invoice is not available');
    const alreadyMatched = await this.prisma.bankTransaction.findFirst({ where: { invoiceId: invoice.id, reconciliationStatus: BankReconciliationStatus.MATCHED_INVOICE, id: { not: id } } });
    if (alreadyMatched) throw new BadRequestException('Invoice is already matched');
    const saved = await this.prisma.bankTransaction.update({ where: { id }, data: { invoiceId: invoice.id, suggestedInvoiceId: invoice.id, matchConfidence: transaction.matchConfidence === InvoiceMatchConfidence.NO_MATCH ? InvoiceMatchConfidence.LIKELY : transaction.matchConfidence, reconciliationStatus: BankReconciliationStatus.MATCHED_INVOICE, categorizationSource: BankCategorizationSource.INVOICE_MATCH, vendorId: invoice.vendorId } });
    await this.audit.log({ userId, organizationId: transaction.organizationId, action: 'bank.invoice_match_confirmed', entityType: 'BankTransaction', entityId: id, metadata: { invoiceId: invoice.id } });
    return saved;
  }

  async rejectMatch(userId: string, id: string) {
    const transaction = await this.transaction(userId, id);
    const saved = await this.prisma.bankTransaction.update({ where: { id }, data: { suggestedInvoiceId: null, matchConfidence: InvoiceMatchConfidence.NO_MATCH, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW } });
    await this.audit.log({ userId, organizationId: transaction.organizationId, action: 'bank.invoice_match_rejected', entityType: 'BankTransaction', entityId: id });
    return saved;
  }

  async disconnect(userId: string, id: string) {
    const connection = await this.connection(userId, id);
    if (connection.status === BankConnectionStatus.DISCONNECTED) return;
    await this.providers.get(connection.provider).disconnect(this.encryption.decrypt(connection.encryptedAccessToken));
    await this.prisma.bankConnection.update({ where: { id }, data: { status: BankConnectionStatus.DISCONNECTED, encryptedAccessToken: this.encryption.encrypt('revoked'), syncCursor: null } });
    await this.audit.log({ userId, organizationId: connection.organizationId, action: 'bank.disconnected', entityType: 'BankConnection', entityId: id });
  }

  private async validateLocation(organizationId: string, locationId: string) { const location = await this.prisma.restaurantLocation.findFirst({ where: { id: locationId, organizationId } }); if (!location) throw new ForbiddenException('Restaurant location is not available'); return location; }
}
