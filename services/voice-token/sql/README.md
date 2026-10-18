# Durable admission deployment reference

`admission-reference.sql` is a reviewable setup script, **not an applied migration**.
No Supabase CLI migration history was generated. No remote SQL was executed.
PostgreSQL and `psql` were not available for runtime verification on this host.
The JavaScript tests mock RPC responses. A separate [PostgreSQL/WASM check](LOCAL-VALIDATION.md) now verifies syntax, grants and sequential quota behavior; it does not prove independent-connection concurrency. Validate this script on an isolated Supabase-like
PostgreSQL database before enabling the production mode.

The RPC is `public.feel_reserve_admission(p_user_id uuid, p_operation text)`.
Only `service_role` can execute it. It is `SECURITY INVOKER` with an empty search
path and qualified tables. Private tables have RLS enabled and no public, anon or
authenticated grants. The service may read policies and update counters; policy
limits are operator-managed. No privileged definer function or client-writable
policy is introduced. A modern Supabase secret uses `apikey`; a legacy
service-role JWT also uses `Authorization: Bearer`. Neither belongs in the app.

Supported operations are `voice_session`, `context_last_seen`,
`context_room_structure`, `context_room_anchors`. The server derives the user UUID
from a fresh Supabase Auth verification and chooses the operation itself.

No policies are seeded. Missing or disabled policy denies access. After review,
the operator must choose per-user and global limits for each enabled operation,
for both UTC calendar minutes and UTC calendar days. All limits must be positive
integers no greater than 1,000,000; the script supplies no permissive default.
An operation without a reviewed policy remains disabled. Policies can be edited
by the database owner using its normal change process; do not expose those edits
to clients or attach arbitrary quotas to HTTP requests.

A transaction-scoped PostgreSQL advisory lock serializes reservations for each
fixed operation across application instances. Row locks protect the global and
per-user counters. Successful reservations increment both counters atomically
before the server calls the provider. Quota denial increments neither. Failed or
cancelled upstream operations still consume their reservation; there is no refund
or automatic retry. A lost RPC reply may have committed a reservation, so the
server fails closed rather than guessing. Minute and day windows reset using the
database clock. A lock timeout makes admission unavailable rather than bypassing it.

The table stores at most one counter per operation/user plus a global row per
operation. Review retention for these private usage identifiers. An operator may
remove counters only after their stored day window is older than the current UTC
day; deleting an active counter would reset its budget. No automatic cleanup or
scheduler is provisioned by this reference.

## Required isolated-database verification

1. Apply the reference as database owner on an isolated database with the standard
   Supabase roles. Verify `anon` and `authenticated` cannot read the private schema
   or invoke the public RPC. Verify the function is invoker, not definer.
2. As `service_role`, call the RPC with no policy and a disabled policy. Both must
   deny without increments. Invalid operations and the reserved zero UUID must
   fail. No caller-supplied policy or limit parameter exists.
3. Add small test policies as owner. Exercise same-user and different-user calls
   across separate connections. A global limit of N must admit exactly N requests
   even when many requests arrive simultaneously; per-user limits must hold too.
4. Terminate a transaction after reservation but before commit and verify rollback
   leaves no consumed counter. For a committed reservation followed by a simulated
   provider failure, verify the counter stays consumed.
5. Exercise minute/day boundaries using an isolated test clock or by inspecting
   controlled old counter timestamps. Check `Retry-After` against each blocked
   window. Test lock timeout and unavailable database responses.
6. Review Data API function exposure for the chosen project. Grant only the
   documented service-role RPC path, reload its schema cache through the project's
   normal administration process if needed, and run a real server-authenticated
   request. Never grant the RPC to app users to work around an exposure problem.

These reservations bound admitted operations, not currency or audio duration.
Realtime credentials can initiate sessions whose costs vary. Provider account
spending controls and a policy for existing sessions remain necessary.

References consulted October 18, 2026:
[Supabase function security](https://supabase.com/docs/guides/database/functions),
[Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys),
[PostgreSQL locking](https://www.postgresql.org/docs/current/explicit-locking.html).
The current Supabase changelog's Node support change is compatible with this
service's Node 22 runtime. No Supabase SDK dependency was added.
