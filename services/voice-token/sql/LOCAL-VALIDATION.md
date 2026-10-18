# Admission SQL local validation

On 2026-10-18, unchanged `admission-reference.sql` passed 15 checks in PGlite
0.5.10 (PostgreSQL/WASM). The fixture creates mock Supabase roles in an isolated
in-memory database. It never connects to Supabase, Chalk, or OpenAI.

Run from the repository root:

```sh
npm install --prefix /private/tmp/feel-admission-sql-check --cache /private/tmp/feel-admission-npm-cache --ignore-scripts --no-audit --no-fund @electric-sql/pglite@0.5.10
node services/voice-token/sql/check-admission-pglite.mjs /private/tmp/feel-admission-sql-check/node_modules/@electric-sql/pglite/dist/index.js
```

The dependency stays outside the project. The fixture is intentionally not named
`*.test.mjs`, so normal service tests do not require it.

Verified: anon/authenticated RPC and table denial; explicit role guard after an
accidental RPC grant; missing/disabled policies and invalid inputs fail closed;
service cannot edit policies; user/global minute/day quotas; denied usage unchanged;
minute/day rollovers in a non-UTC timezone; RLS after an accidental SELECT grant;
reapplication preserves counters.

`node --test admission.test.mjs` also passed all 11 JavaScript admission tests
with mocked upstreams from the service directory.

## Limits

This fixture uses one connection. It does **not** prove independent connections
contend correctly on the advisory lock, the selected project's roles/default grants
match the fixture, or PostgREST exposes the RPC correctly. Real multi-connection
quota contention and selected-project ACL, RPC, Auth, and rollback checks remain
deployment gates. No policy was enabled and no SQL was applied to a live project.

Local logs: `/private/tmp/feel-admission-sql-check/results.log` and
`/private/tmp/feel-admission-independent-review.log`.

References: [PGlite API](https://pglite.dev/docs/api),
[Supabase API-key roles](https://supabase.com/docs/guides/getting-started/api-keys),
and [Supabase Auth request verification](https://github.com/supabase/auth/blob/master/internal/api/auth.go).
