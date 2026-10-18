# FEEL voice token service

Small Node 22 service with a demo mode and an opt-in authenticated mode. No npm dependencies. The iPhone
requests an ephemeral OpenAI Realtime credential here, then streams audio directly
to OpenAI. This service never receives camera frames or conversation audio.

## Authentication modes

The current demo voice and provisioned Chalk Model Gateway flow work without a
Supabase connection. Leave the mode unset or `demo` to keep that behavior. The
account/RPC integration below is optional, disabled by default, and has not been
activated. It does not make ordinary app startup depend on Supabase. Private
shared-context reads remain an optional separately configured feature.

`FEEL_VOICE_AUTH_MODE=demo` is the default and preserves the existing provisioned
phone's access-code flow. It is not public user authentication.

`FEEL_VOICE_AUTH_MODE=supabase` makes the existing bodyless `POST /session` require
the current Supabase user access token. The server verifies it with `/auth/v1/user`
on every request, requires a non-anonymous account, and derives the UUID from that
response. It then reserves a durable admission through a fixed server-only RPC
before requesting an OpenAI ephemeral credential. Caller identity, quotas and
operation names are never accepted in the request. The response shape is unchanged.

In this mode configure `OPENAI_API_KEY`, `SUPABASE_URL`,
`SUPABASE_PUBLISHABLE_KEY` and `SUPABASE_SECRET_KEY` (or the legacy
`SUPABASE_SERVICE_ROLE_KEY`) on the server. `FEEL_VOICE_ACCESS_TOKEN` is not used.
HTTPS is mandatory even if the local `REQUIRE_HTTPS` setting says otherwise.
Missing server credentials fail configuration; missing/disabled policies,
malformed quota responses or database outages return 503 `admission_unavailable`
without a provider request. Invalid sessions return 401, anonymous/unknown account
status returns 403 `account_required`, and exhausted quota returns 429 with
`Retry-After`. Auth and admission failures consume no provider call. A committed
reservation followed by a provider failure remains consumed; no retries/refunds
are attempted.

The same explicit production mode adds durable admission and anonymous-account
rejection to `/context`; demo mode preserves that endpoint's existing behavior.
The operation names are fixed: `voice_session`, `context_last_seen`,
`context_room_structure`, `context_room_anchors`.

See [SQL setup and verification](sql/README.md). The reference has not been applied
or runtime-verified here. No enabled quota policies are supplied. Until the selected
FEEL project, RPC grants, reviewed limits and real account flow are verified, this
is source implementation, not activated production authentication. Match the app's
`FEEL_VOICE_AUTH_MODE=supabase` build setting before changing the server mode.

## Run the default demo mode

```sh
cd services/voice-token
cp .env.example .env
# Fill .env locally using your secret manager. Never commit credentials.
npm test
npm start
```

Set `OPENAI_API_KEY` only on this server. Set `FEEL_VOICE_ACCESS_TOKEN` to a separate,
cryptographically random token, for example 32 random bytes encoded as hex. Enter
that demo access token in the phone's Voice setup; the app stores it in Keychain.
Do not put the OpenAI key in the phone. The example contains no usable credentials.

The server binds **127.0.0.1 only**, port 8081 by default. Expose it to the phone
through an HTTPS reverse proxy with a trusted certificate. Set `REQUIRE_HTTPS=true`
and configure that local proxy to **overwrite** `X-Forwarded-Proto` with `https`,
not forward a caller-supplied value. Never expose the loopback service via a raw
TCP tunnel or unencrypted LAN port. The iPhone must use the HTTPS URL, not the
Mac's localhost URL. Configure the proxy to omit Authorization and response
bodies from logs, disable caching and enforce request limits. Local HTTP is only
for development tests.

## Vercel deployment setup

The native Node function in `api/session.mjs` shares the same request handler as
the local HTTP server. Set the Vercel project's Root Directory to
`services/voice-token`, Framework Preset to Other, and Node version to 22.x.
`vercel.json` supplies the empty build/install commands, a 15-second function
limit, and the `/session` rewrite. No framework or external runtime dependency
is required. `public/` is intentionally empty; server source is not a static site.

For demo mode, configure `OPENAI_API_KEY` and `FEEL_VOICE_ACCESS_TOKEN` as sensitive Vercel environment
variables for the intended deployment environment. Do not upload `.env`, pass
secret values as command arguments, or add them to `vercel.json`. The deployment
allowlist in `.vercelignore` excludes environment files and local project metadata.
The function always requires the platform's HTTPS marker, regardless of the local
`REQUIRE_HTTPS` value. Use the full URL `https://<deployment-host>/session` in the
phone. `/api/session` is also supported; both paths share one warm-instance limit.

Configure deployment access so the native app can reach the endpoint with its
FEEL bearer token. A browser login wall or Vercel deployment-protection challenge
is separate from this token and cannot be answered by the app. Review deployment
logs without enabling request-body, response-body or authorization-header capture.
After environment changes, redeploy so each function instance loads the new values.
An incomplete configuration returns 503 `voice_service_not_configured` without
provider calls. `/health` is a local-server route, not a deployed function route.

**The in-memory limits are per warm function instance.** Vercel can start multiple
instances and replace them at any time. Cold starts reset counters, so six mints
per minute is not a deployment-wide or account-wide limit. In demo mode, use it only
for the provisioned phone. Supabase mode additionally requires the durable atomic
RPC before minting. A provider budget must still bound account spending.
No deployment or live provider validation is implied by the presence of this
configuration. Local adapter tests do not test Vercel's routing or infrastructure.

This version switches `/session` to OpenAI; it does not keep a second provider
route. Deploy it together with the OpenAI-compatible phone update. An older Grok
client cannot use this credential with its former WebSocket endpoint. Keep the
existing deployment in place until the matching phone build is ready, then update
the provider environment variable and deploy this source. No local `.env` migration
or cloud environment update happens automatically.

## Phone contract

`POST /session`, no body, `Authorization: Bearer <FEEL_VOICE_ACCESS_TOKEN>`.

Successful HTTP 200 response:

```json
{"value":"<short-lived credential>","expires_at":1800000300}
```

`expires_at` is Unix time in seconds. Keep the returned value in memory, use it
immediately for the native WebSocket Authorization Bearer header, and discard it
on disconnect. Every connection requests a fresh credential. Never persist or log
the ephemeral value. The credential expires after the requested five minutes;
this is not an enforced maximum conversation duration or spending limit.

Responses use `Cache-Control: no-store`. Errors contain only a fixed `error` code.
401 means the demo access token did not match, 429 means wait for `Retry-After`,
502 means the provider failed or returned an invalid session, and 504 means its
request timed out. The provider's response and error text never leave the server.
`GET /health` returns `{ "status": "ok" }`; it does not test OpenAI connectivity.

In demo mode each handler instance permits six authenticated mint attempts per minute and two
concurrent provider requests. Failed attempts count. Limits use constant memory
and reset when the process restarts. This is a single-phone demo boundary,
not user authentication. Do not use the same provisioning token across a public
app. Rotate it in the server and phone to revoke mint access. Previously issued
credentials and active sessions may remain usable. A public release needs user
authentication, per-user quotas and shared rate limits before adding replicas.
In Supabase mode an instance admits at most 120 syntactically valid requests per
minute and two in flight, in addition to the database quotas. These local bounds
protect resources but cannot replace shared enforcement. Set a provider account
budget separately; mint limits cannot bound audio spend.

## Provider contract and verification

The server sends this fixed body to
`POST https://api.openai.com/v1/realtime/client_secrets`:

```json
{
  "expires_after": { "anchor": "created_at", "seconds": 300 },
  "session": {
    "type": "realtime",
    "model": "gpt-realtime-2.1",
    "audio": { "output": { "voice": "cedar" } }
  }
}
```

Clients cannot change this mint request. The provider permits session settings
to be overridden on the subsequent connection, so these defaults are not a
spending or authorization boundary. The native socket uses
`wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1`.

Verified against the official [Realtime client secret API](https://developers.openai.com/api/reference/resources/realtime/subresources/client_secrets/methods/create)
on October 17, 2026. OpenAI returns `value`, `expires_at` and an effective `session`;
the service returns only the first two fields. Unit tests mock OpenAI and exercise
the actual local HTTP server.
Passing tests do not prove a paid key, deployed HTTPS endpoint or voice session
works. Live provider validation remains pending until those are configured.

Vercel setup follows its [Node runtime documentation](https://vercel.com/docs/functions/runtimes/node-js)
and [function and rewrite configuration](https://vercel.com/docs/project-configuration/vercel-json).
