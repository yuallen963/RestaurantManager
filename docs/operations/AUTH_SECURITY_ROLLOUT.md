# FundWell authentication security rollout

The authentication security migration is additive and all new enrollment features are disabled by default. Existing password, verification, reset, shared-beta, refresh-token, and session-revocation behavior remains available.

## Feature flags and secrets

Configure these only after the migration, Resend delivery, and account-recovery flow have been verified in the target environment:

- `AUTH_EMAIL_LOGIN_VERIFICATION_ENABLED=true` permits users to opt into five-minute email login codes.
- `AUTH_MFA_ENABLED=true` permits authenticator-app enrollment.
- `AUTH_DEVICE_RECOGNITION_ENABLED=true` records hashed device identifiers and sends unfamiliar-device alerts.
- `AUTH_MFA_ENCRYPTION_KEY` must be a base64-encoded 32-byte random key. Back it up in the platform secret store; losing it prevents verification of existing TOTP enrollments.
- `AUTH_CHALLENGE_SECRET` should be a separate high-entropy secret used to hash challenges and device identifiers.

Flags control new enrollment only. An account that has already enabled a factor continues to require it even if a rollout flag is later disabled.

Transactional email continues to use the existing variables: `AUTH_EMAIL_PROVIDER=resend`, `RESEND_API_KEY`, `AUTH_FROM_EMAIL`, and an HTTPS `AUTH_PUBLIC_BASE_URL` without query parameters or embedded credentials.

## Resend domain setup

1. Add a sending domain in Resend that the FundWell operator controls.
2. Add the exact DKIM and SPF DNS records shown by Resend at the DNS provider. Do not copy values from another domain or environment.
3. Wait until Resend reports the domain as verified.
4. Set `AUTH_FROM_EMAIL` to a sender on that verified domain, for example `FundWell <security@verified-domain.example>`.
5. Send verification and password-reset messages only to authorized test identities, then verify delivery, expiry, and single-use behavior before enabling either rollout flag.

Security notifications are transactional and independent of marketing preferences. Emails never contain passwords, session tokens, recovery codes, financial details, or raw device identifiers.

## Passkey readiness

Passkeys are intentionally reported unavailable in the API and UI. A secure implementation requires a stable relying-party domain, server-side WebAuthn challenge/credential storage and signature verification, and native platform ceremonies. The current iOS entitlement has `applinks` for Plaid/auth links but no `webcredentials` association.

Before implementing passkeys:

1. Choose a FundWell-controlled relying-party domain and serve a correct `/.well-known/apple-app-site-association` file containing the app ID under `webcredentials`.
2. Add `webcredentials:<domain>` without removing the existing Plaid `applinks` entry.
3. Configure Android Digital Asset Links and Credential Manager for the same relying party.
4. Add bounded, single-use server challenges and standards-compliant WebAuthn verification, credential revocation, and tested recovery.

Apple documents the `webcredentials` associated-domain requirement at <https://developer.apple.com/documentation/authenticationservices/supporting-passkeys>. Android documents its Digital Asset Links and Credential Manager prerequisites at <https://developer.android.com/identity/passkeys/create-passkeys>. WebAuthn requires secure contexts and relying-party scoped credentials: <https://www.w3.org/TR/webauthn-1/>.

Local biometric unlocking is not a server-verified passkey and must not be presented as one.

## Deployment ordering

1. Preserve and coordinate the existing historical baseline, invoice provenance, and merchant automation migration work.
2. Take and verify a recoverable database backup.
3. Apply migrations with `prisma migrate deploy`; never use `db push` or reset production.
4. Deploy the backend with all three new flags false and both new secrets configured.
5. Verify historical users and shared beta access.
6. Release the Flutter client.
7. Verify real Resend delivery and recovery with a disposable account.
8. Enable one enrollment flag at a time for controlled accounts.

The temporary private-account access code remains a transitional risk: it is a shared secret protected by a server-side Argon2 hash and rate limiting, not an independent user password. Private access now honors enrolled MFA, but it should ultimately be replaced by normal per-user authentication. Shared-beta access must remain restricted to the single configured internal account and must never be offered to commercial users.
