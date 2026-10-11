# FundWell Gemini Live Extraction Report

Date: 2026-10-11  
Scope: six real Gemini requests (five provider-level, one production end-to-end) using newly generated non-sensitive synthetic invoices. The photographed files already in `test-fixtures/invoices/` were inspected but not sent externally because their sanitization status was not established in-repository.

## A. Actual Gemini configuration

- Provider: `gemini`
- Model: `gemini-3.5-flash-lite`
- `GEMINI_API_KEY`: configured in Railway (value not read or printed)
- `SHARED_TEST_USER_MODE`: `true`
- SDK/request: `@google/genai` `generateContent`, inline image/PDF bytes, JSON response MIME type, explicit response schema, Zod validation after JSON parsing
- Supported model/API: confirmed both by the current Google model documentation and six successful live structured-output calls
- Retry policy: at most three attempts; exponential 500 ms/1 s delay for 429/500/502/503/504; permanent errors are not retried
- Connectivity: PASS

## B. Live extraction results

| Test | Invoice | Expected lines | Correct lines | Missing / extra | Totals correct | Duration | Tokens (in/out/total) |
|---|---|---:|---:|---:|---|---:|---:|
| A | Difficult camera-style JPEG | 3 | 3 | 0 / 0 | Yes | 2,280 ms | 1,244 / 553 / 1,797 |
| B | Clean PNG | 4 | 4 | 0 / 0 | Yes | 3,039 ms | 1,244 / 695 / 1,939 |
| C | Two-page PDF | 8 | 8 | 0 / 0 | Yes (`$1,411.90`) | 3,443 ms | 1,181 / 1,231 / 2,412 |
| D | Incomplete PNG | 2 | 2 | 0 / 0 | **No: values invented** | 2,337 ms | 1,242 / 385 / 1,627 |
| E | Complex-package PNG | 4 | 4 | 0 / 0 | Yes | 2,707 ms | 1,244 / 682 / 1,926 |
| E2E | Clean PNG through Railway upload/storage/worker | 4 | 4 | 0 / 0 | Yes | 2,613 ms worker time | 1,248 / 700 / 1,948 |

Provider-only totals: 6,155 input, 3,546 output, 9,701 total tokens; average latency 2.76 seconds. All five structured responses parsed successfully, with no observed retry.

## C. Field accuracy

- Tests A, B, C, and E: vendor, invoice number, invoice/due dates, subtotal, tax, total, SKU, quantities, unit prices, extended prices, and descriptions were correct.
- Multi-page test: 8/8 lines were preserved in order; `sourcePage` was correct for all lines; the final total was exactly `$1,411.90`.
- Line descriptions: 21/21 live provider-level lines faithfully matched the printed descriptions; no duplicates or invented lines.
- Packaging: all four required expressions (`30/16 OZ`, `12/2 LB`, `6/12 CT`, `4/10 LB`) were extracted exactly and parsed correctly. Overall, 18/21 package expressions were accepted by the current parser. The three failures were `GAL` expressions (`6/1 GAL`, `4/1 GAL`), which the parser does not currently support.
- Test D correctly extracted the vendor, delivery date, and two lines, but incorrectly treated delivery note `MP-4451` as an invoice number and inferred subtotal/total `$77.75` and currency `USD` although none were printed. It also returned no uncertainty flags. This is a model/prompt limitation with financial significance.

## D. Financial reconciliation

- Correct complete documents reconciled with no discrepancies.
- The pre-fix implementation skipped final-total reconciliation whenever `otherFees` was null. A `$1,411.00` extracted total with calculated `$1,411.90` therefore produced no warning.
- The local fix preserves the raw null but treats absent separately extracted fees as zero only for the final-total calculation when subtotal, tax, and total are present. The same case now produces `TOTAL_MISMATCH`, expected `$1,411.00`, calculated `$1,411.90`.
- Raw extracted values are not rewritten.
- Test D demonstrates that internally consistent invented totals cannot be detected by arithmetic reconciliation alone. Mandatory human review remains necessary.
- Unreviewed invoices remain excluded from trusted price intelligence.

## E. End-to-end FundWell result

- Target: FundWell Test Restaurant (`41043b47-21d0-4927-8179-880322e889f2`), never Bangkok Cuisine
- Created invoice: `75f9b7ea-e88b-486a-8109-d29d87e6aeb3`
- Real storage upload: PASS (actual PNG bytes uploaded through the presigned URL)
- Real Gemini call: PASS
- Actual extraction worker: PASS, one attempt, 2,613 ms
- Persistence: PASS; 4/4 line items and all expected financial fields persisted
- Reconciliation: PASS, no discrepancies for the correct clean fixture
- Review status: PASS (`NOT_REVIEWED`); it was not approved and cannot contribute trusted intelligence
- Duplicate protection: covered by existing deterministic tests; no second production upload was made solely to retest it

## F. Performance and estimated cost

Using Google's published paid standard pricing for Gemini 3.5 Flash-Lite ($0.30/M input tokens and $2.50/M output tokens), the five provider-level calls cost approximately **$0.0107**, and the end-to-end call approximately **$0.0021**, before any free-tier or account-specific adjustments. Total estimated cost was about **$0.0128**. Pricing source: [Gemini Developer API pricing](https://ai.google.dev/gemini-api/docs/pricing).

## G. Issues found

1. **High financial risk / likely on incomplete documents / high user impact / medium fix difficulty:** Gemini inferred missing invoice number, subtotal, total, and currency without uncertainty flags. Human review must remain mandatory; arithmetic reconciliation cannot identify a plausible but invented total.
2. **High financial risk / conditional frequency / high impact / low fix difficulty:** final-total mismatch was skipped when `otherFees=null`. Fixed locally with regression coverage; deployment required.
3. **Medium intelligence risk / common for liquids / medium impact / low difficulty:** deterministic package parsing rejects `GAL`, so otherwise accurate gallon packaging is unusable for normalized comparisons. Documented, not changed in this pass.
4. **High data-integrity risk / partial invoice edits / high impact / low fix difficulty:** omitted numeric fields were converted to null by the partial-update helper. Fixed locally with regression coverage. Approval now also explicitly sets terminal `COMPLETED` status.

## H. Recommendation

1. Gemini is operational in FundWell: real image/PDF requests, structured parsing, production storage, worker execution, and persistence all passed.
2. `gemini-3.5-flash-lite` is accurate enough for the current human-reviewed beta on clear and moderately degraded invoices, but not safe for automatic financial trust.
3. Mandatory review fields: invoice identity, subtotal, tax/fees, total, quantities, units, package sizes, unit prices, and extended prices—especially when source fields are absent.
4. A serious omission/hallucination was observed on the incomplete invoice: three absent financial/identity values plus currency were inferred without uncertainty.
5. Keep the current model for the beta. The evidence does not justify an automatic model switch.
6. Top improvements: enforce source-presence/uncertainty checks for inferred headline values; add volume units such as GAL to deterministic package parsing; deploy the reconciliation and partial-update integrity fixes after review.

## I. Changes and verification

- Added regression coverage for a `$1,411.00` versus `$1,411.90` mismatch when `otherFees=null`.
- Added regression coverage ensuring partial status updates preserve omitted financial fields.
- Added regression coverage ensuring approval sets invoice status to `COMPLETED`.
- Backend: 227 tests passed across 22 suites; build passed; Prisma validate/generate passed.
- No Flutter changes; no TestFlight update is required.
- Railway deployment is required for the local backend fixes, but was not performed automatically.

