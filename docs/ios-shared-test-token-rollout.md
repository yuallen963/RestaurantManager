# Internal iOS shared-test token rollout

The protected backend in `f528ecad` requires a high-entropy
`SHARED_TEST_CLIENT_TOKEN`. Existing TestFlight builds do not send that token,
so the compatible iOS build must reach testers before `origin/main` advances
and triggers Railway.

## Secret handling

Generate the production token outside the repository with an approved secret
manager. Do not paste it into source, workflow inputs, commit messages,
changelogs, tickets, or terminal transcripts.

Store the same value in:

1. The GitHub `testflight-production` environment as the protected secret
   `SHARED_TEST_CLIENT_TOKEN`.
2. Railway production as `SHARED_TEST_CLIENT_TOKEN`, but only during the
   separately authorized backend release.

The Fastlane lane writes the GitHub secret to a mode `0600` temporary JSON
file and passes only that temporary path to Flutter. Ruby deletes the file
when the block exits. The secret is not present in the logged Flutter command.

Do not define this token for Cloudflare or any Flutter Web build. Web uses its
own platform implementation with an empty shared-test token and rejects shared
test mode.

## Pre-backend compatible build

Railway deploys when `origin/main` advances. A tag push transfers the selected
commit to GitHub without moving `origin/main`, and the existing workflow
supports `ios-v*` tags. Use that path for the compatibility build:

1. Create a focused local commit containing the reviewed TestFlight workflow,
   Fastlane, verification script, and this document. Do not include unrelated
   worktree files.
2. Verify the commit descends from `f528ecad` and includes the native
   `SHARED_TEST_CLIENT_TOKEN` reader.
3. Add the protected GitHub environment secret.
4. Create a unique annotated tag such as `ios-v1.0.0-compat-token-1` at that
   exact commit.
5. Push only that tag. Do not push `main`.
6. Confirm `origin/main` remains at its previous commit and Railway has not
   deployed.
7. Monitor the single TestFlight workflow run and confirm internal-only
   processing and distribution.
8. Install the new build and verify shared automatic login against the old
   backend. The old endpoint ignores the additional header, so this is
   backward-compatible.

Do not use `workflow_dispatch` for an unpushed local commit: GitHub runs the
workflow definition from a GitHub ref, not the local working tree.

## Coordinated backend release

After the compatible iOS build is available and the internal test device has
successfully authenticated:

1. Warn internal testers that older builds must be updated before the cutoff.
2. Record `origin/main`, Railway deployment, migration, and API baselines.
3. Add the exact same token to Railway production without printing it.
4. Apply the three already-reviewed additive migrations before pushing code.
5. Verify all migrations and financial preflights.
6. Push the reviewed release commit chain to `origin/main` once.
7. Monitor Railway's automatic deployment.
8. Verify the new TestFlight build can still obtain a shared session.
9. Verify the public web client receives `404` from the shared-session route
   and contains no token.
10. Keep the old backend available for rollback; the compatible iOS build can
    authenticate against either backend version.

Installed older iOS builds cannot be updated with a token remotely. Once the
new backend enforces the token, those builds will lose shared automatic login
until the tester installs the compatible build. A permanent no-interruption
guarantee would require a temporary backend grace path, which is deliberately
not introduced because it weakens the new protection.

## Rollback

- Before backend deployment: remove the prerelease tag only if the workflow
  has not started; never trigger a second upload to replace a failed run
  without diagnosing it.
- After TestFlight distribution but before backend deployment: no rollback is
  required. The new build remains compatible with the old backend.
- After backend deployment: roll back the backend code while leaving the token
  configured. The old backend ignores the extra request header.
- Never expose or rotate the token merely to debug a build. If compromise is
  suspected, rotate both GitHub and Railway values together and publish a new
  compatible internal build before enforcing the replacement.
