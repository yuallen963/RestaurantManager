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
    expect(migrations.slice(-3)).toEqual([
      '20261012190000_invoice_field_provenance',
      '20261012230000_bank_rule_auto_confirmation',
      '20261013010000_auth_security_foundation',
    ]);
  });
});
