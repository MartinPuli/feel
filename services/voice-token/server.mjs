import { createServer } from 'node:http';
import { createHash, timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { AdmissionError, isBearer, readAdmissionConfig, readAuthMode, reserveAdmission, verifyUser } from './admission.mjs';

const UPSTREAM = 'https://api.openai.com/v1/realtime/client_secrets';
const hash = value => createHash('sha256').update(value).digest();

export function readConfig(env = process.env) {
  const authMode = readAuthMode(env);
  const config = {
    authMode,
    apiKey: env.OPENAI_API_KEY ?? '',
    accessToken: env.FEEL_VOICE_ACCESS_TOKEN ?? '',
    port: Number(env.PORT ?? 8081),
    requireHTTPS: authMode === 'supabase' || env.REQUIRE_HTTPS === 'true',
  };
  if (!/^[\x21-\x7e]{1,4096}$/.test(config.apiKey)) {
    throw new Error('Set OPENAI_API_KEY on the server.');
  }
  if (authMode === 'demo' && (!/^[\x21-\x7e]{32,4096}$/.test(config.accessToken)
      || config.accessToken === config.apiKey)) {
    throw new Error('Set a distinct FEEL_VOICE_ACCESS_TOKEN with at least 32 characters.');
  }
  if (!Number.isInteger(config.port) || config.port < 1 || config.port > 65535) {
    throw new Error('PORT must be between 1 and 65535.');
  }
  if (env.REQUIRE_HTTPS !== undefined && !['true', 'false'].includes(env.REQUIRE_HTTPS)) {
    throw new Error('REQUIRE_HTTPS must be true or false.');
  }
  if (authMode === 'supabase') config.admission = readAdmissionConfig(env);
  return config;
}

export function reply(res, status, body, headers = {}) {
  if (res.destroyed) return;
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store',
    'Pragma': 'no-cache',
    'X-Content-Type-Options': 'nosniff',
    'Connection': 'close',
    ...headers,
  });
  res.end(JSON.stringify(body));
}

async function readBoundedJSON(response) {
  const reader = response.body?.getReader();
  if (!reader) throw new Error('Missing body');
  const chunks = [];
  let bytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > 16384) throw new Error('Response too large');
      chunks.push(Buffer.from(value));
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } finally {
    await reader.cancel().catch(() => {});
  }
}

// One token/phone per demo service. Limits are per handler instance, not shared.
export function createTokenHandler(config, {
  fetchImpl = fetch,
  now = Date.now,
  upstreamTimeoutMs = 8000,
  requestsPerMinute = config.authMode === 'supabase' ? 120 : 6,
  sessionPaths = ['/session'],
} = {}) {
  const production = config.authMode === 'supabase';
  const allowedPaths = new Set(sessionPaths);
  const expectedAuth = hash(`Bearer ${config.accessToken}`);
  let windowStart = now();
  let requests = 0;
  let inFlight = 0;

  return async (req, res) => {
    if ((production || config.requireHTTPS) && req.headers['x-forwarded-proto'] !== 'https') {
      return reply(res, 426, { error: 'https_required' });
    }
    if (req.url === '/health' && req.method === 'GET') {
      return reply(res, 200, { status: 'ok' });
    }
    if (!allowedPaths.has(req.url)) return reply(res, 404, { error: 'not_found' });
    if (req.method !== 'POST') {
      return reply(res, 405, { error: 'method_not_allowed' }, { Allow: 'POST' });
    }
    const authorization = req.headers.authorization ?? '';
    if (production ? !isBearer(authorization) : typeof authorization !== 'string' || !timingSafeEqual(hash(authorization), expectedAuth)) {
      return reply(res, 401, { error: 'unauthorized' }, { 'WWW-Authenticate': 'Bearer' });
    }
    // No client-controlled upstream URL, session settings, or expiration.
    if (req.headers['transfer-encoding'] !== undefined
        || (req.headers['content-length'] !== undefined && req.headers['content-length'] !== '0')) {
      return reply(res, 400, { error: 'body_must_be_empty' });
    }
    try {
      // Vercel may expose a parsed body even when a proxy changed framing headers.
      const body = req.body;
      if (body !== undefined && body !== '' && !(Buffer.isBuffer(body) && body.length === 0)) {
        return reply(res, 400, { error: 'body_must_be_empty' });
      }
    } catch {
      return reply(res, 400, { error: 'body_must_be_empty' });
    }
    if (production && !config.admission) return reply(res, 503, { error: 'admission_unavailable' });
    const time = now();
    if (time - windowStart >= 60000) {
      windowStart = time;
      requests = 0;
    }
    if (requests >= requestsPerMinute || inFlight >= 2) {
      const retryAfter = Math.max(1, Math.ceil((60000 - (time - windowStart)) / 1000));
      return reply(res, 429, { error: 'rate_limited' }, { 'Retry-After': String(retryAfter) });
    }
    requests += 1;
    inFlight += 1;
    const controller = new AbortController();
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, upstreamTimeoutMs);
    const cancel = () => { if (!res.writableEnded) controller.abort(); };
    res.on('close', cancel);
    try {
      if (production) {
        const transport = { fetchImpl, signal: controller.signal };
        const userID = await verifyUser(authorization, config.admission, transport);
        await reserveAdmission(userID, 'voice_session', config.admission, transport);
        controller.signal.throwIfAborted();
      }
      const upstream = await fetchImpl(UPSTREAM, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${config.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          expires_after: { anchor: 'created_at', seconds: 300 },
          session: {
            type: 'realtime',
            model: 'gpt-realtime-2.1',
            audio: { output: { voice: 'cedar' } },
          },
        }),
        redirect: 'error',
        signal: controller.signal,
      });
      if (!upstream.ok) {
        await upstream.body?.cancel();
        return reply(res, 502, { error: 'voice_provider_unavailable' });
      }
      const data = await readBoundedJSON(upstream);
      const seconds = Math.floor(now() / 1000);
      if (typeof data?.value !== 'string' || !/^[\x21-\x7e]{1,4096}$/.test(data.value)
          || data.value === config.apiKey || data.value === config.accessToken
          || !Number.isSafeInteger(data.expires_at)
          || data.expires_at <= seconds + 5 || data.expires_at > seconds + 360) {
        return reply(res, 502, { error: 'invalid_voice_session' });
      }
      return reply(res, 200, { value: data.value, expires_at: data.expires_at });
    } catch (error) {
      if (!timedOut && error instanceof AdmissionError) {
        return reply(res, error.status, { error: error.code }, error.retryAfter ? { 'Retry-After': String(error.retryAfter) } : {});
      }
      // Do not return or log provider bodies, errors, tokens, or request headers.
      return reply(res, timedOut ? 504 : 502, {
        error: timedOut ? 'voice_provider_timeout' : 'voice_provider_unavailable',
      });
    } finally {
      clearTimeout(timer);
      res.off('close', cancel);
      inFlight -= 1;
    }
  };
}

export function createTokenServer(config, options) {
  const server = createServer({ maxHeaderSize: 8192 }, createTokenHandler(config, options));
  server.requestTimeout = 10000;
  server.headersTimeout = 10000;
  server.timeout = 15000;
  server.maxConnections = 32;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const config = readConfig();
    const server = createTokenServer(config);
    server.on('error', () => {
      console.error('Voice token service could not listen. Check the local port.');
      process.exitCode = 1;
    });
    // Only a local TLS reverse proxy may expose this service to the phone.
    server.listen(config.port, '127.0.0.1', () => {
      console.log('FEEL voice token service listening on loopback.');
    });
  } catch (error) {
    // readConfig errors contain only fixed configuration names, never values.
    console.error(error.message);
    process.exitCode = 1;
  }
}
