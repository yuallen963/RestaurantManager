import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { BankCategorizationSource, BankConnectionStatus, BankProvider, BankReconciliationStatus, BankTransactionDirection, ExpenseSource, InvoiceMatchConfidence, MerchantRuleDecision, MerchantRuleMatchType, OrganizationRole, Prisma, ReviewStatus } from '@prisma/client';
import { AuditService } from '../audit.service';
import { OrganizationAccessService } from '../organizations/organization-access.service';
import { PrismaService } from '../prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { AssignBankAccountDto, BankReviewDecision, BankTransactionQuery, BulkReviewBankTransactionsDto, ConfirmInvoiceMatchDto, ExchangeBankTokenDto, ReviewBankTransactionDto, UpdateMerchantRuleDto } from './dto';
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
    const saved = await this.prisma.bankConnection.update({ where: { id }, data: { status: BankConnectionStatus.CONNECTED, lastError: null } });
    await this.audit.log({ userId, organizationId: connection.organizationId, action: 'bank.reauthenticated', entityType: 'BankConnection', entityId: id });
    this.scheduleSync(userId, id);
    return this.safeConnection(saved);
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
    this.scheduleSync(userId, connection.id);
    return this.safeConnection(connection);
  }

  private scheduleSync(userId: string, connectionId: string) {
    setImmediate(() => void this.sync(userId, connectionId).catch(() => undefined));
  }

  async connections(userId: string, organizationId: string) {
    await this.organization(userId, organizationId);
    const rows = await this.prisma.bankConnection.findMany({ where: { organizationId }, include: { accounts: { include: { restaurantLocation: { select: { id: true, name: true } } } } }, orderBy: { createdAt: 'desc' } });
    return rows.map((row) => this.safeConnection(row));
  }

  async syncStatus(userId: string, organizationId: string, restaurantLocationId: string) {
    await this.organization(userId, organizationId);
    await this.validateLocation(organizationId, restaurantLocationId);
    const connections = await this.prisma.bankConnection.findMany({
      where: {
        organizationId,
        status: { not: BankConnectionStatus.DISCONNECTED },
        accounts: { some: { restaurantLocationId, active: true } },
      },
      select: { id: true, status: true, lastSyncAt: true, lastError: true },
    });
    if (!connections.length) {
      return { state: 'NONE', connectionCount: 0, transactionCount: 0, lastSyncAt: null, message: null, canRetry: false };
    }
    const transactionCount = await this.prisma.bankTransaction.count({
      where: {
        organizationId,
        restaurantLocationId,
        removedAt: null,
        bankAccount: { bankConnectionId: { in: connections.map((connection) => connection.id) } },
      },
    });
    const failed = connections.find((connection) => connection.status === BankConnectionStatus.ERROR || connection.status === BankConnectionStatus.NEEDS_ATTENTION);
    const syncing = connections.filter((connection) => connection.status === BankConnectionStatus.SYNCING);
    const pending = connections.filter((connection) => connection.status === BankConnectionStatus.CONNECTED && connection.lastSyncAt == null);
    const completed = connections.filter((connection) => connection.status === BankConnectionStatus.CONNECTED && connection.lastSyncAt != null);
    const lastSyncAt = completed.map((connection) => connection.lastSyncAt!).sort((a, b) => b.getTime() - a.getTime())[0] ?? null;
    if (failed) {
      return {
        state: 'FAILED', connectionCount: connections.length, transactionCount, lastSyncAt,
        message: failed.lastError ?? (failed.status === BankConnectionStatus.NEEDS_ATTENTION ? 'Reconnect your bank to continue syncing.' : 'Bank synchronization failed. Try again from Bank Accounts.'),
        canRetry: true,
      };
    }
    if (syncing.length || pending.length) {
      const partial = transactionCount > 0 || completed.length > 0;
      return {
        state: partial ? 'PARTIALLY_COMPLETE' : syncing.length ? 'IMPORTING' : 'PENDING',
        connectionCount: connections.length, transactionCount, lastSyncAt, message: null, canRetry: false,
      };
    }
    return { state: 'COMPLETE', connectionCount: connections.length, transactionCount, lastSyncAt, message: null, canRetry: false };
  }

  async assignAccount(userId: string, id: string, data: AssignBankAccountDto) {
    const account = await this.account(userId, id);
    await this.access.requireMember(userId, account.organizationId, [OrganizationRole.OWNER, OrganizationRole.ADMIN]);
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
      for (const transaction of [...updates.added, ...updates.modified]) await this.ingest(userId, connection.organizationId, connection.accounts, transaction);
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

  private async ingest(userId: string, organizationId: string, accounts: any[], transaction: ProviderTransaction) {
    const account = accounts.find((candidate) => candidate.providerAccountId === transaction.accountId);
    if (!account || !account.active) return;
    const merchant = normalizeMerchant(transaction.merchantName ?? transaction.description);
    const providerType = transaction.categoryId ?? transaction.category;
    const direction = transaction.amount > 0 ? BankTransactionDirection.OUTFLOW : BankTransactionDirection.INFLOW;
    const categorization = await this.categorize(organizationId, account.restaurantLocationId, account.id, direction, merchant, providerType);
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
      const updated = await this.prisma.bankTransaction.update({ where: { id: posted.id }, data: { ...raw, ...reconciliation } });
      await this.autoReconcile(userId, updated, categorization.rule);
      return;
    }
    if (pending) {
      const updated = await this.prisma.bankTransaction.update({ where: { id: pending.id }, data: { ...raw, providerTransactionId: transaction.id, suggestedInvoiceId: pending.suggestedInvoiceId ?? invoiceMatch?.invoiceId, matchConfidence: pending.matchConfidence === InvoiceMatchConfidence.NO_MATCH ? invoiceMatch?.confidence ?? InvoiceMatchConfidence.NO_MATCH : pending.matchConfidence } });
      if (!updated.pending && updated.pendingReviewDecision === MerchantRuleDecision.PERSONAL_TRANSFER && !updated.expenseId && !updated.invoiceId && !updated.suggestedInvoiceId) {
        await this.prisma.bankTransaction.update({ where: { id: updated.id }, data: { reconciliationStatus: BankReconciliationStatus.IGNORED, pendingReviewDecision: null } });
        return;
      }
      await this.autoReconcile(userId, updated, categorization.rule);
      return;
    }
    const created = await this.prisma.bankTransaction.create({ data: { organizationId, bankAccountId: account.id, providerTransactionId: transaction.id, ...proposed } });
    await this.autoReconcile(userId, created, categorization.rule);
  }

  private async categorize(organizationId: string, locationId: string | null, bankAccountId: string, direction: BankTransactionDirection, merchant: string, providerCategory?: string) {
    const canonical = cleanMerchant(merchant);
    const rules = await this.prisma.merchantRule.findMany({ where: { organizationId, active: true, OR: [{ restaurantLocationId: locationId }, { restaurantLocationId: null }] }, orderBy: [{ restaurantLocationId: 'desc' }, { createdAt: 'asc' }] });
    const rule = rules.find((candidate) => (!candidate.bankAccountId || candidate.bankAccountId === bankAccountId)
      && (!candidate.direction || candidate.direction === direction)
      && (!candidate.providerCategoryId || candidate.providerCategoryId === providerCategory)
      && (candidate.matchType === MerchantRuleMatchType.EXACT ? canonical === candidate.matchValue : candidate.matchType === MerchantRuleMatchType.PREFIX ? canonical.startsWith(candidate.matchValue) : canonical.includes(candidate.matchValue)));
    if (rule) return { vendorId: rule.vendorId, categoryId: rule.expenseCategoryId, source: BankCategorizationSource.USER_RULE, rule };
    const vendors = await this.prisma.vendor.findMany({ where: { organizationId }, select: { id: true, normalizedName: true } });
    const vendor = vendors.find((candidate) => canonical.includes(cleanMerchant(candidate.normalizedName)) || cleanMerchant(candidate.normalizedName).includes(canonical));
    if (vendor) return { vendorId: vendor.id, categoryId: null, source: BankCategorizationSource.MERCHANT_RULE, rule: null };
    const mapping: Record<string, string> = { UTILITIES: 'utilities', PAYROLL: 'labor' };
    const slug = Object.entries(mapping).find(([key]) => (providerCategory ?? '').toUpperCase().includes(key))?.[1];
    const category = slug ? await this.prisma.expenseCategory.findFirst({ where: { slug, OR: [{ organizationId: null }, { organizationId }] }, select: { id: true } }) : null;
    return { vendorId: null, categoryId: category?.id ?? null, source: category ? BankCategorizationSource.PROVIDER : BankCategorizationSource.UNRESOLVED, rule: null };
  }

  private async autoReconcile(userId: string, transaction: any, rule: any) {
    if (!rule?.active || !rule.autoConfirm || transaction.pending || transaction.expenseId
      || transaction.suggestedInvoiceId || transaction.reconciliationStatus !== BankReconciliationStatus.NEEDS_REVIEW
      || !transaction.restaurantLocationId
      || rule.restaurantLocationId !== transaction.restaurantLocationId
      || rule.matchType !== MerchantRuleMatchType.EXACT) return;
    if (rule.bankAccountId && rule.bankAccountId !== transaction.bankAccountId) return;
    const direction = new Prisma.Decimal(transaction.amount).gt(0) ? BankTransactionDirection.OUTFLOW : BankTransactionDirection.INFLOW;
    if (rule.direction && rule.direction !== direction) return;
    if (rule.providerCategoryId && rule.providerCategoryId !== (transaction.providerCategoryId ?? transaction.providerCategory)) return;
    if (rule.decision === MerchantRuleDecision.PERSONAL_TRANSFER) {
      await this.prisma.bankTransaction.updateMany({ where: { id: transaction.id, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW, expenseId: null, invoiceId: null, suggestedInvoiceId: null }, data: { reconciliationStatus: BankReconciliationStatus.IGNORED, categorizationSource: BankCategorizationSource.USER_RULE } });
      await this.audit.log({ userId, organizationId: transaction.organizationId, action: 'bank.transaction_auto_excluded', entityType: 'BankTransaction', entityId: transaction.id, metadata: { merchantRuleId: rule.id } });
      return;
    }
    if (!rule.vendorId || !rule.expenseCategoryId) return;
    const exceptionText = `${transaction.description ?? ''} ${transaction.providerCategory ?? ''}`.toUpperCase();
    if (/\b(TRANSFER|REFUND|REVERSAL|LOAN|OWNER CONTRIBUTION)\b/.test(exceptionText)) return;
    const amount = new Prisma.Decimal(transaction.amount);
    if (amount.lte(0) || (rule.minimumAmount && amount.lt(rule.minimumAmount))
      || (rule.maximumAmount && amount.gt(rule.maximumAmount))) return;
    await this.prisma.$transaction(async (tx) => {
      const current = await tx.bankTransaction.findUnique({ where: { id: transaction.id } });
      if (!current || current.expenseId || current.pending || current.suggestedInvoiceId
        || current.reconciliationStatus !== BankReconciliationStatus.NEEDS_REVIEW) return;
      const expense = await tx.expense.create({ data: {
        organizationId: current.organizationId,
        restaurantLocationId: current.restaurantLocationId!,
        vendorId: rule.vendorId,
        expenseCategoryId: rule.expenseCategoryId,
        amount: current.amount,
        date: current.postedDate,
        description: current.description,
        source: ExpenseSource.BANK_IMPORT,
        createdByUserId: userId,
      } });
      await tx.bankTransaction.update({ where: { id: current.id }, data: {
        vendorId: rule.vendorId,
        categoryId: rule.expenseCategoryId,
        expenseId: expense.id,
        categorizationSource: BankCategorizationSource.USER_RULE,
        reconciliationStatus: BankReconciliationStatus.MATCHED_EXPENSE,
      } });
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    await this.audit.log({ userId, organizationId: transaction.organizationId, action: 'bank.transaction_auto_reconciled', entityType: 'BankTransaction', entityId: transaction.id, metadata: { merchantRuleId: rule.id } });
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

  async similarTransactions(userId: string, id: string) {
    const transaction = await this.transaction(userId, id);
    if (!transaction.merchantNameNormalized) return [];
    const amount = new Prisma.Decimal(transaction.amount);
    return this.prisma.bankTransaction.findMany({ where: {
      organizationId: transaction.organizationId,
      restaurantLocationId: transaction.restaurantLocationId,
      bankAccountId: transaction.bankAccountId,
      merchantNameNormalized: transaction.merchantNameNormalized,
      providerCategoryId: transaction.providerCategoryId,
      providerCategory: transaction.providerCategory,
      pending: transaction.pending,
      reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW,
      expenseId: null, invoiceId: null, suggestedInvoiceId: null, removedAt: null,
      amount: amount.gt(0) ? { gt: 0 } : { lte: 0 },
    }, include: { category: { select: { id: true, name: true } }, vendor: { select: { id: true, name: true } }, bankAccount: { select: { id: true, name: true, mask: true } } }, orderBy: [{ postedDate: 'desc' }, { id: 'asc' }] });
  }

  async review(userId: string, id: string, data: ReviewBankTransactionDto) {
    const transaction = await this.transaction(userId, id);
    if (data.restaurantLocationId) await this.validateLocation(transaction.organizationId, data.restaurantLocationId);
    if (data.vendorId && !(await this.prisma.vendor.findFirst({ where: { id: data.vendorId, organizationId: transaction.organizationId } }))) throw new ForbiddenException('Vendor is not available');
    if (data.categoryId && !(await this.prisma.expenseCategory.findFirst({ where: { id: data.categoryId, OR: [{ organizationId: null }, { organizationId: transaction.organizationId }] } }))) throw new ForbiddenException('Category is not available');
    if (data.autoConfirmFuture && !data.createMerchantRule) throw new BadRequestException('Automatic confirmation requires an approved merchant rule');
    if (data.autoConfirmFuture && (data.minimumAmount == null || data.maximumAmount == null)) throw new BadRequestException('Automatic confirmation requires an approved amount range');
    if (data.minimumAmount != null && data.maximumAmount != null && data.minimumAmount > data.maximumAmount) throw new BadRequestException('Minimum amount cannot exceed maximum amount');
    const locationId = data.restaurantLocationId ?? transaction.restaurantLocationId;
    const vendorId = data.vendorId === undefined ? transaction.vendorId : data.vendorId;
    const categoryId = data.categoryId === undefined ? transaction.categoryId : data.categoryId;
    const decision = data.decision ?? (data.ignored ? BankReviewDecision.PERSONAL_TRANSFER : BankReviewDecision.EXPENSE);
    if (transaction.expenseId || transaction.invoiceId || transaction.reconciliationStatus === BankReconciliationStatus.MATCHED_EXPENSE || transaction.reconciliationStatus === BankReconciliationStatus.MATCHED_INVOICE) throw new ConflictException('Transaction has already been reviewed');
    let saved;
    if (decision === BankReviewDecision.PERSONAL_TRANSFER) {
      if (transaction.suggestedInvoiceId) throw new BadRequestException('Confirm or reject the suggested invoice match first');
      saved = await this.prisma.bankTransaction.update({ where: { id }, data: { vendorId: null, categoryId: null, restaurantLocationId: locationId, pendingReviewDecision: transaction.pending ? MerchantRuleDecision.PERSONAL_TRANSFER : null, categorizationSource: BankCategorizationSource.MANUAL, reconciliationStatus: transaction.pending ? BankReconciliationStatus.NEEDS_REVIEW : BankReconciliationStatus.IGNORED } });
    } else if (decision === BankReviewDecision.REVIEW_LATER) {
      saved = await this.prisma.bankTransaction.update({ where: { id }, data: { vendorId, categoryId, restaurantLocationId: locationId, pendingReviewDecision: null, categorizationSource: BankCategorizationSource.MANUAL, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW } });
    } else if (transaction.pending) {
      saved = await this.prisma.bankTransaction.update({ where: { id }, data: { vendorId, categoryId, restaurantLocationId: locationId, pendingReviewDecision: MerchantRuleDecision.EXPENSE, categorizationSource: BankCategorizationSource.MANUAL, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW } });
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
    await this.audit.log({ userId, organizationId: transaction.organizationId, action: decision === BankReviewDecision.PERSONAL_TRANSFER ? 'bank.transaction_ignored' : decision === BankReviewDecision.REVIEW_LATER ? 'bank.transaction_review_deferred' : 'bank.transaction_categorized', entityType: 'BankTransaction', entityId: id });
    if (data.createMerchantRule && decision !== BankReviewDecision.REVIEW_LATER && transaction.merchantNameNormalized) {
      const matchValue = cleanMerchant(transaction.merchantNameNormalized);
      const locationId = data.restaurantLocationId ?? transaction.restaurantLocationId;
      const matchType = data.ruleMatchType ?? MerchantRuleMatchType.EXACT;
      const direction = transaction.amount.gt(0) ? BankTransactionDirection.OUTFLOW : BankTransactionDirection.INFLOW;
      const providerCategoryId = transaction.providerCategoryId ?? transaction.providerCategory;
      const ruleDecision = decision === BankReviewDecision.PERSONAL_TRANSFER ? MerchantRuleDecision.PERSONAL_TRANSFER : MerchantRuleDecision.EXPENSE;
      const existing = await this.prisma.merchantRule.findFirst({ where: { organizationId: transaction.organizationId, restaurantLocationId: locationId, bankAccountId: transaction.bankAccountId, direction, providerCategoryId, matchType, matchValue } });
      const rule = existing
        ? await this.prisma.merchantRule.update({ where: { id: existing.id }, data: { active: true, decision: ruleDecision, autoConfirm: ruleDecision === MerchantRuleDecision.PERSONAL_TRANSFER ? true : data.autoConfirmFuture ?? false, minimumAmount: data.minimumAmount, maximumAmount: data.maximumAmount, vendorId: ruleDecision === MerchantRuleDecision.EXPENSE ? data.vendorId ?? transaction.vendorId : null, expenseCategoryId: ruleDecision === MerchantRuleDecision.EXPENSE ? data.categoryId ?? transaction.categoryId : null, normalizedMerchantName: transaction.merchantNameNormalized } })
        : await this.prisma.merchantRule.create({ data: { organizationId: transaction.organizationId, restaurantLocationId: locationId, bankAccountId: transaction.bankAccountId, direction, providerCategoryId, decision: ruleDecision, matchType, matchValue, normalizedMerchantName: transaction.merchantNameNormalized, active: true, autoConfirm: ruleDecision === MerchantRuleDecision.PERSONAL_TRANSFER ? true : data.autoConfirmFuture ?? false, minimumAmount: data.minimumAmount, maximumAmount: data.maximumAmount, vendorId: ruleDecision === MerchantRuleDecision.EXPENSE ? data.vendorId ?? transaction.vendorId : null, expenseCategoryId: ruleDecision === MerchantRuleDecision.EXPENSE ? data.categoryId ?? transaction.categoryId : null, createdByUserId: userId } });
      await this.audit.log({ userId, organizationId: transaction.organizationId, action: 'bank.merchant_rule_created', entityType: 'MerchantRule', entityId: rule.id });
    }
    return saved;
  }

  async bulkReview(userId: string, data: BulkReviewBankTransactionsDto) {
    const uniqueIds = [...new Set(data.ids)];
    const rows = await this.prisma.bankTransaction.findMany({ where: { id: { in: uniqueIds } }, select: { id: true, organizationId: true, restaurantLocationId: true } });
    if (rows.length !== uniqueIds.length) throw new NotFoundException('One or more bank transactions were not found');
    const organizationIds = new Set(rows.map((row) => row.organizationId));
    const locationIds = new Set(rows.map((row) => row.restaurantLocationId));
    if (organizationIds.size !== 1 || locationIds.size !== 1) throw new BadRequestException('Bulk review requires transactions from one restaurant');
    await this.organization(userId, rows[0].organizationId);
    const reviewData: ReviewBankTransactionDto = { ...data };
    delete (reviewData as any).ids;
    const results = [];
    const failures: Array<{ id: string; message: string }> = [];
    let firstError: unknown;
    for (const id of uniqueIds) {
      try {
        results.push(await this.review(userId, id, reviewData));
      } catch (error) {
        firstError ??= error;
        failures.push({
          id,
          message: error instanceof Error ? error.message : 'Unable to review transaction',
        });
      }
    }
    if (!results.length && firstError) throw firstError;
    return {
      requestedCount: uniqueIds.length,
      count: results.length,
      failedCount: failures.length,
      results,
      failures,
    };
  }

  async reverseReconciliation(userId: string, id: string) {
    const transaction = await this.transaction(userId, id);
    if (transaction.reconciliationStatus === BankReconciliationStatus.IGNORED && !transaction.expenseId && !transaction.invoiceId) {
      const restored = await this.prisma.bankTransaction.update({ where: { id }, data: { reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW, pendingReviewDecision: null } });
      await this.audit.log({ userId, organizationId: transaction.organizationId, action: 'bank.transaction_ignore_reversed', entityType: 'BankTransaction', entityId: id });
      return restored;
    }
    if (transaction.reconciliationStatus !== BankReconciliationStatus.MATCHED_EXPENSE || !transaction.expenseId) throw new BadRequestException('Transaction is not reversible');
    const result = await this.prisma.$transaction(async (tx) => {
      const current = await tx.bankTransaction.findUnique({ where: { id } });
      if (!current?.expenseId || current.reconciliationStatus !== BankReconciliationStatus.MATCHED_EXPENSE) throw new ConflictException('Transaction reconciliation changed');
      const expense = await tx.expense.findUnique({ where: { id: current.expenseId } });
      if (!expense || expense.source !== ExpenseSource.BANK_IMPORT) throw new BadRequestException('Only bank-created expenses can be reversed here');
      const links = await tx.bankTransaction.count({ where: { expenseId: expense.id } });
      if (links !== 1) throw new ConflictException('Expense has multiple financial links');
      const reversed = await tx.bankTransaction.update({ where: { id }, data: { expenseId: null, reconciliationStatus: BankReconciliationStatus.NEEDS_REVIEW } });
      await tx.expense.delete({ where: { id: expense.id } });
      return reversed;
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    await this.audit.log({ userId, organizationId: transaction.organizationId, action: 'bank.transaction_reconciliation_reversed', entityType: 'BankTransaction', entityId: id });
    return result;
  }

  async merchantRules(userId: string, organizationId: string, locationId: string) {
    await this.organization(userId, organizationId);
    await this.validateLocation(organizationId, locationId);
    return this.prisma.merchantRule.findMany({ where: { organizationId, restaurantLocationId: locationId }, include: { vendor: { select: { id: true, name: true } }, expenseCategory: { select: { id: true, name: true } } }, orderBy: { updatedAt: 'desc' } });
  }

  async updateMerchantRule(userId: string, id: string, data: UpdateMerchantRuleDto) {
    const rule = await this.prisma.merchantRule.findUnique({ where: { id } });
    if (!rule) throw new NotFoundException('Merchant rule not found');
    await this.organization(userId, rule.organizationId);
    if (data.minimumAmount != null && data.maximumAmount != null && data.minimumAmount > data.maximumAmount) throw new BadRequestException('Minimum amount cannot exceed maximum amount');
    if (data.autoConfirm === true && (data.minimumAmount ?? rule.minimumAmount) == null) throw new BadRequestException('Automatic confirmation requires a minimum amount');
    if (data.autoConfirm === true && (data.maximumAmount ?? rule.maximumAmount) == null) throw new BadRequestException('Automatic confirmation requires a maximum amount');
    if (data.vendorId && !(await this.prisma.vendor.findFirst({ where: { id: data.vendorId, organizationId: rule.organizationId } }))) throw new ForbiddenException('Vendor is not available');
    if (data.categoryId && !(await this.prisma.expenseCategory.findFirst({ where: { id: data.categoryId, OR: [{ organizationId: null }, { organizationId: rule.organizationId }] } }))) throw new ForbiddenException('Category is not available');
    const saved = await this.prisma.merchantRule.update({ where: { id }, data: { active: data.active, autoConfirm: data.autoConfirm, vendorId: data.vendorId, expenseCategoryId: data.categoryId, minimumAmount: data.minimumAmount, maximumAmount: data.maximumAmount } });
    await this.audit.log({ userId, organizationId: rule.organizationId, action: 'bank.merchant_rule_updated', entityType: 'MerchantRule', entityId: id });
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
