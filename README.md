# Restaurant Profit App — Phases 1–2 foundation

Monorepo for a restaurant-owner financial visibility product. Phase 1 delivers secure onboarding and the tenant-safe foundation for future financial data.

Phase 2 adds the tenant-safe financial data model, seeded expense classifications, manual revenue/expense/vendor API endpoints, and a deterministic dashboard endpoint. CSV examples are in `examples/`; import staging is represented by `Import` and `ImportRow` so invalid data can be retained for review rather than silently accepted.

## Structure

```
apps/api       NestJS REST API, Prisma schema, auth, organizations and locations
apps/mobile    Flutter iOS/Android app
docker-compose.yml  PostgreSQL 16 and Redis 7 for local development
```

## Run locally

1. Copy `.env.example` to `apps/api/.env` and replace both JWT secrets.
2. Start dependencies: `docker compose up -d`.
3. Install API packages: `cd apps/api && npm install`.
4. Create/update the database: `npx prisma migrate dev --name phase2_financial_data && npm run prisma:seed`. For a disposable local database, `npx prisma db push && npm run prisma:seed` is also supported.
5. Run API: `npm run start:dev`; Swagger is at `http://localhost:3000/api/docs`.
6. Run mobile: `cd apps/mobile && flutter pub get && flutter run`.

## Demo restaurant data

`npm run prisma:seed` creates a deterministic 92-day demo dataset for **Demo Restaurant Group**. Sign in with `demo@profitlens.local` and `DemoProfit2026!`. It includes Downtown Grill (higher sales, rising food/labor/delivery costs), Lakeside Grill (lower sales, steadier margin), and Bangkok Cuisine in Rochester, MI (a synthetic Thai-restaurant operating mix; not real business financial data). Re-running the seed replaces only demo financial records, so screenshots and demos remain consistent.

For an iOS simulator, start the API first and then run:

```bash
cd apps/mobile
flutter run --dart-define=API_URL=http://localhost:3000/api/v1
```

For an iOS simulator use `--dart-define=API_URL=http://localhost:3000/api/v1`. Android emulators use the default `10.0.2.2` address.

## API endpoints

- `POST /api/v1/auth/register`, `login`, `refresh`, `logout`; `GET /api/v1/auth/me`
- `GET|POST /api/v1/organizations`; `GET /api/v1/organizations/:id`
- `POST /api/v1/organizations/:id/members`
- `GET|POST /api/v1/organizations/:organizationId/locations`
- `GET|POST /api/v1/revenue` and `GET|POST /api/v1/expenses` require a permitted `restaurantLocationId`.
- `GET /api/v1/expense-categories?organizationId=…`; `GET|POST /api/v1/vendors`
- `GET /api/v1/dashboard?restaurantLocationId=…&startDate=…&endDate=…` returns Decimal-safe revenue, expenses, estimated profit, food/labor percentages, and an expense breakdown.
- `POST /api/v1/invoices/upload-intent`, `POST /api/v1/invoices/:id/upload-complete`, and `GET|PATCH|DELETE /api/v1/invoices/:id` support tenant-safe manual invoice management.

All organization and location endpoints require a Bearer token. The server looks up membership using the authenticated user ID before any tenant data is returned or changed.

## Invoice storage

Invoice PDFs and images use private S3-compatible object storage with 15-minute
presigned upload URLs. Configure the API with `S3_ENDPOINT`, `S3_REGION`,
`S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, and
`S3_FORCE_PATH_STYLE`. Keep the bucket private; Flutter receives only a
short-lived URL scoped to a single tenant/location invoice object.

Supported uploads are PDF, JPEG, and PNG files up to 15 MB. Invoice metadata can
always be entered manually, and no automatic expense creation occurs.

Invoice extraction uses the server-side OpenAI Responses API with PDF/image
inputs and strict Structured Outputs. Set `OPENAI_API_KEY` and optionally
`OPENAI_INVOICE_MODEL` (default `gpt-4.1-mini`) on the API service. The original
file and every raw line-item description are preserved. Extracted values remain
untrusted until a user corrects them and selects **Mark Reviewed**; extraction
never creates an expense automatically.

Extraction endpoints are `POST /api/v1/invoices/:id/extract`,
`GET /api/v1/invoices/:id/extraction-status`,
`GET /api/v1/invoices/:id/line-items`,
`PATCH /api/v1/invoices/:invoiceId/line-items/:lineItemId`, and
`PATCH /api/v1/invoices/:id/review`.

Same-vendor price intelligence is available at
`GET /api/v1/price-intelligence/changes` and
`GET /api/v1/price-intelligence/items/:itemKey/history`. Analytics use only
reviewed invoices from the requested organization/location. Items match by SKU,
then exact normalized name, then a conservatively canonicalized raw description;
unit and pack size must match. The baseline is the immediately previous trusted
purchase. Defaults are a 90-day lookback, a 5% change, and a $0.50 absolute
change, configurable through `PRICE_CHANGE_PERCENT_THRESHOLD` and
`PRICE_CHANGE_ABSOLUTE_THRESHOLD`.

`GET /api/v1/needs-attention` computes location-scoped, explainable issues from
reviewed item-price history and authoritative dashboard, vendor, and expense
data. It compares the selected financial period with the immediately preceding
equal-length period. Detection and severity are deterministic; thresholds for
food/labor percentage-point deterioration, vendor/category increases, and
severity score bands are centralized in the environment variables documented
in `.env.example`. The summary only totals item-level price impact so overlapping
vendor and category changes are not double-counted.

## Data architecture

`User → OrganizationMember → Organization → RestaurantLocation` is the access hierarchy. Financial/domain models are already created with UUIDs, `organizationId`, location keys where applicable, timestamps, money as PostgreSQL `Decimal(14,2)`, and lookup indexes. System expense categories are seeded. Refresh tokens are hashed, persisted, rotated, and revocable; an audit log records organization/location/member mutations.

## Tests and verification

`cd apps/api && npm test` runs authentication and tenant-boundary tests. `flutter test` runs Flutter tests. Before production, add integration tests against a disposable PostgreSQL instance, apply rate limits, implement object storage/virus scanning, and configure Sentry/FCM secrets.

## CSV format

Revenue uses `date,amount,notes`; expenses use `date,vendor,category,amount,description`. See `examples/revenue-import.csv` and `examples/expense-import.csv`. The current schema provides durable `Import` and `ImportRow` staging records for a worker-backed upload processor; production import execution should be added with BullMQ and local/S3 storage rather than processing files in an HTTP request.
# Bank transaction foundation

Bank connections use Plaid's server-created Link token, public-token exchange, and cursor-based Transactions Sync flow. Set `BANK_PROVIDER=demo` for deterministic development data without contacting Plaid. Production credentials remain server-only, and provider access tokens are encrypted with AES-256-GCM using `BANK_TOKEN_ENCRYPTION_KEY`.

Imported transaction amounts follow one convention throughout the API: positive values are debits/spending and negative values are credits/income. Unassigned accounts remain organization-scoped and their transactions require review before they can affect location workflows. Bank imports never create expenses automatically, so an invoice or expense cannot be counted twice.

The initial Plaid request asks for 90 days of transaction history. Incremental synchronization persists Plaid's cursor and applies added, modified, and removed records. Rotate the encryption key by decrypting every stored token with the old key and re-encrypting it with the new key in one controlled maintenance operation; replacing the environment variable alone will make existing connections unreadable.

Plaid webhooks are intentionally deferred in this foundation. Until ES256 JWT signature, timestamp, and raw-body hash verification are added, no public webhook endpoint is exposed or trusted; users can run **Sync now**, and every connection also retains its incremental cursor for scheduled server-side syncing. Do not enable an unauthenticated webhook route.
