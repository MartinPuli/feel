# FEEL voice token service

Small Node 22+ service for the V1 demo phone. No packages or database. The iPhone
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
for development tests. This directory does not deploy a proxy or cloud service.

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

The service permits six authenticated mint attempts per minute and two concurrent
provider requests. Failed attempts count. Limits use constant memory and reset
when the process restarts. This is a single-instance, single-phone demo boundary,
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
