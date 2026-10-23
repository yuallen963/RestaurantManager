# Cloudflare Pages private beta

This release uses the neutral temporary Cloudflare Pages project name
`restaurant-finance-beta`. Cloudflare assigns the final HTTPS origin after the
project is created, for example:

`https://restaurant-finance-beta.pages.dev`

No shared-test credential is part of the web build. The browser calls the
same-origin `/api/v1` path, which is handled by the narrowly scoped Pages
Function and forwarded only to the configured Railway API origin.

## Cloudflare Pages project

Connect the existing GitHub repository and use:

- Root directory: `apps/mobile`
- Build command: `flutter build web --release --dart-define=API_BASE_URL=/api/v1`
- Build output directory: `build/web`
- Runtime: a build image with the repository's supported Flutter SDK
- Pages Function variable: `API_ORIGIN=https://restaurantmanager-production-6231.up.railway.app`

Do not define `SHARED_TEST_USER_MODE` or `SHARED_TEST_CLIENT_TOKEN` in
Cloudflare. The Flutter web implementation also refuses shared-test mode, but
omitting both values prevents accidental credential inclusion in build output.

The `_redirects` file supplies the Flutter SPA fallback. `_headers` supplies
the initial CSP, anti-framing, content-type, referrer, permissions, HSTS, and
cache policies. Pages Functions take precedence over the static `/api/*`
fallback and authenticated responses are explicitly marked `no-store`.

If Cloudflare's build image does not contain the required Flutter version,
build `apps/mobile/build/web` in CI and deploy it with Wrangler while keeping
`apps/mobile/functions` in the Pages project. Do not deploy only the static
directory without the Function.

## Railway settings after Cloudflare assigns the URL

Replace `<pages-origin>` below with the exact lowercase HTTPS origin and no
trailing slash:

```text
CORS_ORIGIN=<pages-origin>
AUTH_PUBLIC_BASE_URL=<pages-origin>
PLAID_WEB_REDIRECT_URI=<pages-origin>/plaid/oauth
```

Keep the existing native `PLAID_REDIRECT_URI` unchanged. The proxy preserves
the public Pages `Origin` and `X-FundWell-Client: web`, so the API continues to
enforce its browser-origin and web-session checks. The refresh cookie is
returned by the same-origin proxy and remains HttpOnly, Secure, and scoped to
`/api/v1/auth`. Login, refresh rotation, logout, and revocation therefore do
not depend on a third-party Railway cookie.

The Railway CORS allowlist is still required because the API's web-session
guard validates the forwarded public origin even though the browser talks to
the same-origin proxy.

## Plaid Sandbox callback

Add the exact callback to the Plaid dashboard's allowed redirect URIs:

`<pages-origin>/plaid/oauth`

Use that same value for `PLAID_WEB_REDIRECT_URI`. Test only with Plaid Sandbox
during beta validation. The route restores the browser session, opens Bank
Accounts, and gives Plaid Link the complete returned URL containing
`oauth_state_id`.

## Object-storage browser CORS

Invoice uploads use a presigned object-storage URL directly from the browser,
so the bucket must allow the exact `<pages-origin>` for `PUT` and the
`Content-Type` request header. `GET`/`HEAD` and exposed `ETag` may be enabled
for browser-side verification. Do not use a wildcard origin for credentialed
resources.

## Invitation email limitation

The application continues to use Resend. The current `onboarding@resend.dev`
sender cannot be treated as production delivery for arbitrary restaurant
owners. Before inviting external users, verify a sender domain in Resend and
set `AUTH_FROM_EMAIL` to an address on that domain. This does not require
changing email providers, but it cannot be completed with only a `pages.dev`
application hostname.

## Smoke test

1. Load and hard-refresh `/login`, `/register`, `/verify-email`,
   `/reset-password`, and `/plaid/oauth`.
2. Confirm an uninvited registration is rejected.
3. Sign in, reload, refresh the access token, log out, and verify the refresh
   cookie is removed.
4. Confirm API responses and HTML are not cached by Cloudflare.
5. Upload safe PDF, JPEG, and PNG fixtures and verify bucket CORS.
6. Run a Plaid Sandbox OAuth institution through the full return route.
7. Confirm a web build containing shared-test Dart defines still cannot start
   shared-test login and contains no shared token.
