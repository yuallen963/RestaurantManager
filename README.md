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

All organization and location endpoints require a Bearer token. The server looks up membership using the authenticated user ID before any tenant data is returned or changed.

## Data architecture

`User → OrganizationMember → Organization → RestaurantLocation` is the access hierarchy. Financial/domain models are already created with UUIDs, `organizationId`, location keys where applicable, timestamps, money as PostgreSQL `Decimal(14,2)`, and lookup indexes. System expense categories are seeded. Refresh tokens are hashed, persisted, rotated, and revocable; an audit log records organization/location/member mutations.

## Tests and verification

`cd apps/api && npm test` runs authentication and tenant-boundary tests. `flutter test` runs Flutter tests. Before production, add integration tests against a disposable PostgreSQL instance, apply rate limits, implement object storage/virus scanning, and configure Sentry/FCM secrets.

## CSV format

Revenue uses `date,amount,notes`; expenses use `date,vendor,category,amount,description`. See `examples/revenue-import.csv` and `examples/expense-import.csv`. The current schema provides durable `Import` and `ImportRow` staging records for a worker-backed upload processor; production import execution should be added with BullMQ and local/S3 storage rather than processing files in an HTTP request.
