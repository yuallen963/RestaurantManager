# FundWell internal TestFlight releases

This workflow builds the Flutter iOS app and distributes it **only** to the
existing App Store Connect internal testing group. It cannot submit the app for
App Review, enable external testing, or invite external testers.

## One-time Apple and GitHub setup

1. In App Store Connect, create an API key with the least privilege that can
   upload builds and manage internal TestFlight distribution (normally **App
   Manager**). Download the `.p8` file immediately; Apple shows it once.
2. In GitHub, create the protected `testflight-production` environment. Limit
   it to the people allowed to publish internal builds, and add these
   environment secrets:
   - `APP_STORE_CONNECT_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`
   - `APP_STORE_CONNECT_API_KEY_P8_BASE64` — the base64 encoding of the `.p8`
     file, with no extra quote characters.
   - `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` and
     `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` — an exported Apple Distribution
     certificate that is valid for team `4R7CXGD5WK`.
   - `IOS_APP_STORE_PROVISIONING_PROFILE_BASE64` — the base64 encoding of the
     App Store provisioning profile for
     `com.restaurantprofit.restaurantProfitMobile`.
3. Add environment variable `TESTFLIGHT_INTERNAL_GROUP` with the **exact name**
   of the existing internal tester group in App Store Connect. Do not create or
   use an external group.
4. Confirm the API key has access to app `6821509303` and bundle ID
   `com.restaurantprofit.restaurantProfitMobile`.

Never commit a `.p8` file, signing certificate, provisioning profile, any of
their base64 encodings, an API key ID, or an Apple session cookie. The workflow
reads its credentials only from GitHub's protected environment.

## Release

From a clean, pushed `main`, use GitHub Actions → **FundWell Internal
TestFlight** → **Run workflow**. Enter the App Store version already created in
App Store Connect (currently `1.0.0`) and a tester-facing changelog. This is
the preferred one-command release because the protected environment keeps
credentials off developer machines.

For a local authorized release, after setting the same environment variables:

```sh
cd apps/mobile
bundle install
bundle exec fastlane ios testflight_internal
```

The lane asks App Store Connect for the most recent TestFlight build number for
the selected marketing version and uses the next number. It runs `flutter
analyze` and `flutter test` before building, then builds with the fixed
production settings:

- `API_BASE_URL=https://restaurantmanager-production-6231.up.railway.app/api/v1`
- `SHARED_TEST_USER_MODE=true`

It preserves the existing bundle ID, Apple team, associated domains, and iOS
signing configuration. A successful upload may remain in Apple processing for
a few minutes; Fastlane waits for processing and then assigns only the named
internal group. Verify the workflow log shows the computed build number and
then verify that build appears under App Store Connect → TestFlight → Internal
Testing. Do not release the build to the App Store from this workflow.

## Tag-triggered release

Pushing an `ios-v*` tag triggers the same protected workflow. Use this only for
an intentional release; ordinary pushes to `main` never upload a build.

If a release fails after upload, do not reuse that build number. Fix the issue
and rerun: the lane will select the next available App Store Connect build.
