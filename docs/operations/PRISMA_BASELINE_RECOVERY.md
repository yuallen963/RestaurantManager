# Prisma baseline and recovery

FundWell's initial commit (`79d1812`) contained a complete Prisma schema but no
Prisma migration. The first checked-in migration was therefore incremental and
could not initialize a blank database. The migration
`20261007000000_initial_baseline` is generated from the exact schema in that
initial commit and must remain earlier than every existing migration.

This follows Prisma's documented
[baselining workflow](https://www.prisma.io/docs/orm/prisma-migrate/workflows/baselining),
including recording an already-present baseline with `prisma migrate resolve`.

Do not edit this baseline or any previously applied migration. A checksum change
after deployment is a migration-history integrity failure.

## New empty databases

For a genuinely empty PostgreSQL database, run:

```sh
DATABASE_URL=... npx prisma migrate deploy
DATABASE_URL=... npx prisma migrate status
```

Prisma applies the baseline and every later migration. This creates schema only;
it does not restore application data.

## Existing databases created before the baseline existed

Do not run `migrate deploy` immediately after adding the baseline. First:

1. Verify a recoverable database backup or Railway recovery point.
2. Read `_prisma_migrations` and compare it with the checked-in migration names
   and checksums.
3. Compare the live schema to the historical baseline and all migrations that
   the database claims have run.
4. If and only if the baseline schema objects already exist, record the baseline:

```sh
DATABASE_URL=... npx prisma migrate resolve --applied 20261007000000_initial_baseline
```

5. Run `npx prisma migrate status`. Only genuinely pending forward migrations
   should remain.
6. Apply those migrations with `npx prisma migrate deploy` during a coordinated
   deployment.

If the database has no reliable `_prisma_migrations` ledger, do not mark all
migrations applied in bulk. Verify each migration's database effects in order,
then use `migrate resolve --applied <migration>` only for changes already present.
Stop on any mismatch.

## Backup restoration and failed deployments

A full PostgreSQL backup restores both application data and the
`_prisma_migrations` ledger. After restoration, confirm `migrate status` before
applying anything new. Migration-based initialization only reconstructs schema;
it is not a substitute for a data backup.

For a failed migration, preserve the database and inspect its transaction state.
Use `migrate resolve --rolled-back` only when the failed migration's effects have
actually been rolled back, or `--applied` only when its full intended effects are
verified. Never use `prisma db push`, `migrate reset`, or seed scripts against
production.

## Local validation evidence

The baseline was reconstructed from Git commit `79d1812` with Prisma 6.19.3.
Local PostgreSQL 16 validation confirmed:

- a blank database applies all 16 migrations in order;
- the resulting schema has no difference from `prisma/schema.prisma`;
- an existing pre-baseline database can record the baseline without recreating
  tables;
- historical invoice and line-item records retain null provenance;
- historical merchant rules default to active with automatic confirmation off;
- the three pending forward migrations apply without data loss;
- the upgraded existing database has no schema drift.

Before any production rollout, repeat the ledger, checksum, backup, and drift
checks against production using read-only inspection first.
