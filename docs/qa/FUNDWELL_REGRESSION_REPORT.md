# FundWell Regression Audit

Date: 2026-10-11  
Scope: read-only regression audit; no deployment, seeding, or production writes.

## Results

- Backend: **225 passed**, 0 failed, 22 suites; `npm run build` passed.
- Prisma: `prisma validate` and `prisma generate` passed (Prisma 6.19.3; only the existing Prisma 7 config deprecation warning).
- Flutter: `flutter analyze` passed; **144 passed**, 0 failed, 0 skipped.
- No code defect was confirmed or fixed during this audit. No regression tests were added.

## Feature coverage matrix

| Feature | Existing evidence | Status | Remaining gap |
|---|---|---|---|
| Authentication, shared beta, refresh, sign-out, account security | `auth.service`, `auth-email`, `auth-rate-limiter`; Flutter lifecycle/shared-mode/account-security/auth-link tests | PASS | Live email delivery still blocked by missing Resend variables |
| Organizations, roles, locations, selected-location state | `organization-access`, `locations`, `onboarding`; Flutter location-management and more tests | PASS | No live destructive cross-tenant test (appropriately not run) |
| Dashboard and date/location filtering | `dashboard.service`; Flutter home dashboard tests | PASS | Dedicated DST/month-end reporting fixtures are limited |
| Invoices: upload, formats, HEIC, private storage, extraction, review | `invoices`, `invoice-extraction`, `invoice-recovery`; Flutter invoice upload/screens/email tests | PASS (mocked) / BLOCKED (live) | Real object-storage/Gemini and physical-iPhone upload remain unverified |
| Invoice recovery and retries | `invoice-recovery` and extraction tests | PASS | Backend restart and real queue/storage interruption need live validation |
| Expenses and revenue | `finance`; Flutter expenses/revenue tests | PASS | No live write test run in production |
| Vendors and purchasing | `price-intelligence`, product matches; Flutter vendors/price/product tests | PASS | None critical in local suite |
| Financial intelligence and alert lifecycle | `needs-attention`, `price-intelligence`, `savings-intelligence`; Flutter attention/price/savings tests | PASS | Time-zone boundary coverage is a gap |
| Banking/Plaid | `bank.provider`, `bank.service`; Flutter banking tests | PASS (mocked) / BLOCKED (live) | No real Plaid production institution is connected |
| Square/POS | `pos`; Flutter POS tests | PASS (mocked) / BLOCKED (live) | Live Square credentials/sync not configured |
| Resend/Mailgun/Firebase/notifications | email, inbound-email, notifications tests | PASS (mocked) / BLOCKED (live) | Railway email variables absent; live delivery/push not tested |
| Flutter navigation, loading/error states, deep links | 22 Flutter suites including navigation, auth links, screen state tests | PASS | Simulator service unavailable in this environment |
| Billing/Stripe | No current implementation identified in audited test inventory | NOT IMPLEMENTED | Outside this audit’s scope |

## Read-only Railway verification

Shared-test session succeeded. Organization `Bangkok Cuisine` and both locations were returned:

- Bangkok Cuisine: 10 invoice records (9 `FAILED`, 1 `PROCESSING`); dashboard for the checked period reports no available financial sources.
- FundWell Test Restaurant: 31 invoices (30 `COMPLETED`, 1 `FAILED`); dashboard reports reviewed invoices, revenue, expenses, and `profitability=false` for the checked period.

No production records were written or deleted. The Bangkok `PROCESSING` record is an existing operational item and was not modified; it requires separate recovery triage before any cleanup. Needs Attention endpoints responded without cross-location data; response-shape details were not mutated.

## Simulator and live-service limitations

`xcrun simctl` could not connect to CoreSimulatorService (`connection refused`), so no simulator smoke pass is claimed. The following remain manual/live checks: physical iPhone camera/photo-library and HEIC uploads, real private-storage PUT, live Gemini extraction, Plaid Production Trial, Resend delivery, Square sync, Mailgun ingestion, Firebase push, and TestFlight Universal Links.

## Defects

No confirmed P0–P2 defect was found in the executed suites or read-only checks. The main operational observation is the pre-existing Bangkok `PROCESSING` invoice noted above; it is not safe to delete without targeted investigation.

## Highest-risk coverage gaps

1. Real iPhone upload matrix (JPEG, PNG, HEIC, PDF, interruption/retry) and private-storage verification — highest customer/data-integrity risk.
2. America/Detroit month-end, year-end, midnight, and DST fixtures across dashboard, revenue, expenses, and POS — financial reporting risk.
3. Live authentication email/deep-link delivery and TestFlight Universal Links — onboarding and account-recovery risk.

## Physical-iPhone checklist

- Camera photo upload and photo-library upload (JPEG/PNG/HEIC conversion).
- PDF upload, Gemini extraction, review/correction, and approval.
- Background the app during upload and retry a failed upload.
- Plaid OAuth and reauthentication.
- Universal Links for verification/reset and Plaid callbacks.
- Restart the app and install a TestFlight update; verify session and selected location.

## Recommended next actions

1. Run the physical-iPhone/TestFlight upload matrix, including HEIC and interrupted uploads. Why: validates the only previously observed production upload failure. Model: **Sol Medium**. Complexity: **Medium**.
2. Add deterministic America/Detroit DST and month/year-boundary integration fixtures. Why: protects reporting-period correctness. Model: **Luna**. Complexity: **Low–Medium**.
3. Configure Resend sender/base URL and validate verification/reset links in TestFlight. Why: production account recovery is currently not live-testable. Model: **Sol Medium**. Complexity: **Medium**.

