# FEEL voice token service

Small Node 22 service for the V1 demo phone. No packages or database. The iPhone
requests an ephemeral Grok Voice credential here, then streams audio directly to
xAI. This service never receives camera frames or conversation audio.

## Run

```sh
cd services/voice-token
cp .env.example .env
# Fill .env locally using your secret manager. Never commit credentials.
npm test
npm start
```

Set `XAI_API_KEY` only on this server. Set `FEEL_VOICE_ACCESS_TOKEN` to a separate,
cryptographically random token, for example 32 random bytes encoded as hex. Enter
that demo access token in the phone's Voice setup; the app stores it in Keychain.
Do not put the xAI key in the phone. The example contains no usable credentials.

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

Configure `XAI_API_KEY` and `FEEL_VOICE_ACCESS_TOKEN` as sensitive Vercel environment
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
per minute is not a deployment-wide or account-wide limit. Use this adapter only
for the provisioned demo phone. Add a shared atomic quota and authenticated user
identity before a public release; a provider budget must bound account spending.
No deployment or live provider validation is implied by the presence of this
configuration. Local adapter tests do not test Vercel's routing or infrastructure.

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
`GET /health` returns `{ "status": "ok" }`; it does not test xAI connectivity.

Each handler instance permits six authenticated mint attempts per minute and two
concurrent provider requests. Failed attempts count. Limits use constant memory
and reset when the process restarts. This is a single-phone demo boundary,
not user authentication. Do not use the same provisioning token across a public
app. Rotate it in the server and phone to revoke mint access. Previously issued
credentials and active sessions may remain usable. A public release needs user
authentication, per-user quotas and shared rate limits before adding replicas.
Set a provider account budget separately; the mint limit cannot bound audio spend.

## Provider contract and verification

The server sends only `{"expires_after":{"seconds":300}}` to
`POST https://api.x.ai/v1/realtime/client_secrets`. Clients cannot change the URL,
expiration or request body. The native socket uses
`wss://api.x.ai/v1/realtime?model=grok-voice-latest`.

Verified against the official [ephemeral token guide](https://docs.x.ai/developers/model-capabilities/audio/ephemeral-tokens)
and [Voice REST response schema](https://docs.x.ai/developers/rest-api-reference/inference/voice)
on October 17, 2026. `session` and `expires_after.anchor` are not supported for
this endpoint. Unit tests mock xAI and exercise the actual local HTTP server.
Passing tests do not prove a paid key, deployed HTTPS endpoint or voice session
works. Live provider validation remains pending until those are configured.

Vercel setup follows its [Node runtime documentation](https://vercel.com/docs/functions/runtimes/node-js)
and [function and rewrite configuration](https://vercel.com/docs/project-configuration/vercel-json).
