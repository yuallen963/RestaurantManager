# Railway deployment runbook

## Authoritative source

The production `RestaurantManager` service in Railway project `serene-flow`,
environment `production`, is connected to the GitHub repository
`yuallen963/RestaurantManager` and tracks the `main` branch. Railway builds
the `/apps/api` root with `npm ci && npx prisma generate && npm run build` and
starts it with `npm start`.

Keep `origin/main` synchronized with the intended release before relying on
the automatic GitHub deployment trigger. Local-only commits are not a safe
production source: a later GitHub deployment can replace a newer CLI upload
with the older remote branch.

## Expected workflow

1. Run backend build/tests and Prisma validation locally.
2. Commit the intended backend revision on `main`.
3. Push `main` to `origin`.
4. Wait for Railway's GitHub deployment to finish.
5. Verify the deployment is `SUCCESS` and confirm the deployment metadata
   commit is the pushed commit.
6. Run read-only API smoke checks (shared session, private session when
   configured, and organization/location scope).

For an urgent controlled upload, `railway up --detach` from the repository
root uploads the current working tree. This is temporary; synchronize
`origin/main` afterward so the GitHub trigger cannot roll it back.

## Verify the deployed revision

Use:

```sh
railway status
railway service list --json
railway deployment list --json
```

For a GitHub deployment, inspect `meta.commitHash`, `meta.branch`, and
`meta.repo`. A CLI upload has no Git commit metadata (`cliCaller` is present
instead), so compare its source to the local commit and then push that commit
to `origin/main`.

The API currently has no public health endpoint. Verify readiness with a
non-mutating authenticated request rather than exposing build metadata or
secrets.

## Investigate an unexpected rollback

Compare the production deployment timestamp and metadata with:

```sh
git rev-parse HEAD
git rev-parse origin/main
git log --oneline origin/main..HEAD
```

If Railway reports an older `main` commit, check whether local commits were
never pushed or whether a GitHub deployment followed a CLI upload. Do not
redeploy the old commit and do not reset the database. Push the intended
commit, wait for the automatic deployment, and repeat the read-only smoke
checks.

Never print access-code hashes, API keys, bearer tokens, or financial data in
deployment diagnostics.
