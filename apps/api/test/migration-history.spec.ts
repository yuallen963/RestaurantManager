import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

describe('Prisma migration history', () => {
  const migrationsRoot = join(__dirname, '..', 'prisma', 'migrations');
  const migrations = readdirSync(migrationsRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();

  it('starts with the historical schema baseline before incremental migrations', () => {
    expect(migrations[0]).toBe('20261007000000_initial_baseline');
    expect(migrations[1]).toBe('20261008000000_invoice_uploads');

    const baseline = readFileSync(
      join(migrationsRoot, migrations[0], 'migration.sql'),
      'utf8',
    );
    for (const table of [
      'User',
      'Organization',
      'RestaurantLocation',
      'Invoice',
      'InvoiceLineItem',
      'Expense',
      'RevenueEntry',
      'Vendor',
    ]) {
      expect(baseline).toContain(`CREATE TABLE "${table}"`);
    }
  });

  it('keeps provenance, bank automation, and auth security as ordered forward migrations', () => {
    expect(migrations.slice(-7)).toEqual([
      '20261012190000_invoice_field_provenance',
      '20261012230000_bank_rule_auto_confirmation',
      '20261013010000_auth_security_foundation',
      '20261014120000_smart_bank_transaction_rules',
      '20261016190000_manual_revenue_type',
      '20261017190000_banking_financial_integrity',
      '20261022160000_private_beta_invitations',
    ]);
  });

  it('enforces bank reconciliation links and one active payment per invoice', () => {
    const sql = readFileSync(
      join(
        migrationsRoot,
        '20261017190000_banking_financial_integrity',
        'migration.sql',
      ),
      'utf8',
    );
    expect(sql).toContain('BankTransaction_reconciliation_links_check');
    expect(sql).toContain('BankTransaction_active_matched_invoice_key');
    expect(sql).toContain('BankTransaction_active_matched_expense_key');
    expect(sql).toContain('CREATE UNIQUE INDEX');
    expect(sql).toContain('RAISE EXCEPTION');
    expect(sql).toContain('WHERE "invoiceId" IS NOT NULL');
    expect(sql).toContain('AND "removedAt" IS NULL');
    expect(sql).toContain('expense link crosses an organization or restaurant location');
    expect(sql).toContain('invoice link crosses an organization or restaurant location');
    expect(sql).not.toMatch(/\bUPDATE\s+"BankTransaction"/i);
    expect(sql).not.toMatch(/\bDELETE\s+FROM\s+"BankTransaction"/i);
  });
});
