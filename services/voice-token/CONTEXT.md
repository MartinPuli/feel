# Authenticated Chalk context proxy

`api/context.mjs` adds a separate Vercel endpoint. The existing `/session` voice
service and its demo credential contract are unchanged. This source is not proof
of a configured or deployed production endpoint.

## Phone contract

`POST /api/context`, over HTTPS, with `Content-Type: application/json` and
`Authorization: Bearer <Supabase user access token>`. `/context` is also accepted
by the handler when the deployment supplies that rewrite.

Accepted request bodies have exactly these keys:

```json
{"operation":"last_seen","object":"keys"}
{"operation":"room_structure","venue_id":"venue-slug","tag_id":"tag-slug"}
{"operation":"room_anchors","venue_id":"venue-slug","tag_id":"tag-slug"}
```

Successful responses contain only `{"values":{...}}` with these fixed features:

| Operation | Features |
|---|---|
| `last_seen` | `object_history.spoken` |
| `room_structure` | `room_memory.structure`, `room_memory.structure_visits` |
| `room_anchors` | `room_memory.targets` |

Structure and target values remain JSON strings, matching the existing Chalk
feature contract. Structure may be null; visits is a nonnegative integer. The
phone must still validate map geometry, anchor records, freshness and tracking
before use. A remembered place is not proof that a path is clear.

No request can supply a user ID, arbitrary feature, query, token, engine URL,
coordinates or output list. The proxy calls the configured Supabase project's
`/auth/v1/user` endpoint for every request and uses only its verified `id` to form
`<user UUID>:<normalized object>`. User metadata and unverified JWT claims are not
used for identity or authorization. Supabase anonymous sign-in sessions are
accepted if Supabase validates them; a publishable API key alone is not a session.

Room data is shared only for exact `venue:tag` keys explicitly enabled by the
server operator. Authentication alone never grants arbitrary room access. Keep
private rooms out of the allowlist until membership authorization exists.

## Server configuration

Set these only in the server's deployment environment:

- `SUPABASE_URL`: HTTPS project origin.
- `SUPABASE_PUBLISHABLE_KEY`: publishable/anon project API key used with Auth.
- `CHALK_CLIENT_ID`, `CHALK_CLIENT_SECRET`, `CHALK_ENV_ID`: existing server-side
  context credentials for the intended environment. A Model Gateway key cannot
  replace the context OAuth client credentials.
- `CHALK_CONTEXT_ENGINE_ORIGIN`: exact trusted HTTPS engine origin for that
  environment, confirmed from the Chalk token grant. The grant must match it.
- `CHALK_CONTEXT_ROOMS`: optional comma-separated `venue:tag` keys. Empty by
  default. Both components use lowercase letters, digits, hyphens or underscores.

Chalk credentials are exchanged server-side at `https://api.chalk.ai/v1/oauth/token`.
They are never sent to the phone. Token grants are not cached or returned.
Redirects are rejected for Auth, token exchange and the engine query. No raw
upstream error text, response bodies, user tokens or credentials are logged.

Stable errors use `{"error":"code"}`: 400 `invalid_request`, 401 `unauthorized`,
403 `room_not_enabled`, 413 `request_too_large`, 415 `json_required`,
426 `https_required`, 429 `rate_limited`, 502 `context_unavailable`,
503 `context_not_configured`, 504 `context_timeout`. All responses are non-cacheable.

## Bounds and production gates

The request body is limited to 2 KiB. Auth and OAuth replies are limited to 32 KiB,
and query replies to 128 KiB; only fixed features are returned. One absolute
10-second deadline covers body parsing, authentication, token exchange and query
response reading. No automatic retries occur. Eight requests may be active on
one warm function instance; its rate limits are 120 attempts per minute and
12 authenticated queries per user per minute.

These memory-local limits reset on cold starts and do not coordinate multiple
instances. They are **not** an account-wide cost limit. Before public production
use, configure and verify distributed rate limits/budgets, scope the Chalk service
credential to the necessary read features, and enable only reviewed shared rooms.
The original demo voice session also retains its existing authentication and
quota limitations. Adding this endpoint does not migrate or secure that route.

The app must have a valid, refreshed Supabase session and explicit cloud opt-in.
Existing rows written under a device-generated demo ID do not automatically
belong to a newly verified Supabase UUID; do not map or expose them through a
caller-provided ID. Review data ownership/migration separately. Supabase RLS on
writes and Chalk source/resolver ownership must also be independently verified.

Validation: `node --test` in `services/voice-token` runs mocked network tests,
including identity spoofing, rejected credentials, unavailable services, unknown
rooms, unexpected outputs, oversize data, redirects, deadlines and rate limits.
No live auth or Chalk operation is claimed by those tests. Deploy only after
configuration review; then validate with a real user session and a known owned
synthetic record. The endpoint is deployed to the existing FEEL Vercel project, but intentionally returns `context_not_configured` until the correct FEEL Supabase and scoped Chalk credentials are configured. No new server credentials were installed. See `docs/PRODUCTION-READINESS.md` for the current gate.

References checked for this implementation:
[Supabase getUser](https://supabase.com/docs/reference/javascript/auth-getuser),
[Supabase Auth REST schema](https://github.com/supabase/auth/blob/master/openapi.yaml),
and [Chalk feature permissions](https://docs.chalk.ai/docs/user-permissions-rbac).
The Supabase changelog index fetch was unavailable in this environment; no SDK
or database migration was introduced.
