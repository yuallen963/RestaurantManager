# FundWell web release requirements

The Flutter web build must not be published until an HTTPS application origin
has been selected and the following configuration is verified in that
environment.

## Authentication

- Set `CORS_ORIGIN` on the API to the exact HTTPS FundWell web origin. Multiple
  origins must be comma-separated; wildcards are not supported for credentialed
  requests.
- Prefer serving the web app and API on same-site hostnames. Browser refresh
  sessions use a `Secure`, `HttpOnly` refresh cookie. If the Railway API remains
  cross-site, browser third-party-cookie policies can prevent session
  restoration even when CORS is correct.
- Route all Flutter application paths to `index.html` so browser reload and
  authentication return navigation reach the app.
- Set `AUTH_PUBLIC_BASE_URL` to the verified HTTPS authentication-link origin.
  Keep the backend fallback pages available until the web routes have been
  tested from real verification and password-reset emails.
- Configure production security headers at the web host, including a narrowly
  scoped Content Security Policy. Include only the Plaid resources required by
  the deployed Plaid Link version; do not use a blanket wildcard policy.

The web build ignores `SHARED_TEST_USER_MODE`, and the API rejects marked web
requests to the shared-test-session endpoint. Internal native iOS builds must
receive the same high-entropy `SHARED_TEST_CLIENT_TOKEN` Dart define configured
on the API. The endpoint fails closed when that token is missing or incorrect;
rotate it if an internal build is distributed outside the intended testers.

## Invoice uploads

- Add the exact HTTPS FundWell web origin to the invoice object store's CORS
  policy for presigned `PUT` requests and the response headers used by that
  provider.
- Allow `Content-Type` for `application/pdf`, `image/jpeg`, and `image/png`.
- Verify the 15 MB limit through the deployed proxy/CDN as well as in the app.
- Confirm that a browser reload can return to the invoice list while extraction
  continues on the backend. Deep-link preservation for a specific invoice must
  be tested against the selected hosting rewrite rules.

## Plaid Link

- Register the final HTTPS web return URI in the appropriate Plaid environment.
- Use Plaid Sandbox for the first deployed browser test. Do not reuse a
  production banking connection for release verification.
- Verify the return URI exactly, including scheme, host, port, and path. No
  placeholder production domain is assumed by the application.
