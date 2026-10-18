import { reply } from './server.mjs';

const MAX_BODY = 2048;
const MAX_REPLY = 131072;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SLUG = /^[a-z0-9][a-z0-9_-]{0,79}$/;
const OUTPUTS = Object.freeze({
  last_seen: ['object_history.spoken'],
  room_structure: ['room_memory.structure', 'room_memory.structure_visits'],
  room_anchors: ['room_memory.targets'],
});
class ContextError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
function origin(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
      url.pathname !== '/' || url.port) throw new Error('Invalid service origin');
  return url.origin;
}
export function readContextConfig(env = process.env) {
  for (const name of ['SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'CHALK_CLIENT_ID',
    'CHALK_CLIENT_SECRET', 'CHALK_ENV_ID', 'CHALK_CONTEXT_ENGINE_ORIGIN']) {
    if (typeof env[name] !== 'string' || !env[name].trim()) throw new Error('Missing context configuration');
  }
  const rooms = (env.CHALK_CONTEXT_ROOMS || '').split(',').map(x => x.trim()).filter(Boolean);
  if (rooms.length > 100 || rooms.some(x => x.split(':').length !== 2 || !x.split(':').every(p => SLUG.test(p)))) {
    throw new Error('Invalid shared room configuration');
  }
  return {
    supabaseOrigin: origin(env.SUPABASE_URL), publishableKey: env.SUPABASE_PUBLISHABLE_KEY,
    clientID: env.CHALK_CLIENT_ID, clientSecret: env.CHALK_CLIENT_SECRET, environmentID: env.CHALK_ENV_ID,
    engineOrigin: origin(env.CHALK_CONTEXT_ENGINE_ORIGIN), rooms: new Set(rooms),
  };
}
function exactKeys(body, keys) {
  return body && typeof body === 'object' && !Array.isArray(body) &&
    Object.keys(body).length === keys.length && keys.every(k => Object.hasOwn(body, k));
}
function parseRequest(body, rooms) {
  if (body?.operation === 'last_seen' && exactKeys(body, ['operation', 'object'])) {
    // A colon would change the compound ownership key. Formatting controls and
    // oversized or ambiguous input are not forwarded to the context engine.
    if (typeof body.object !== 'string' || body.object.length > 80 ||
        /[:\p{Cc}\p{Cf}]/u.test(body.object)) throw new ContextError(400, 'invalid_request');
    const object = body.object.trim().toLowerCase().replace(/\s+/gu, ' ');
    if (!object) throw new ContextError(400, 'invalid_request');
    return { operation: body.operation, object };
  }
  if (['room_structure', 'room_anchors'].includes(body?.operation) &&
      exactKeys(body, ['operation', 'venue_id', 'tag_id']) &&
      typeof body.venue_id === 'string' && typeof body.tag_id === 'string' &&
      SLUG.test(body.venue_id) && SLUG.test(body.tag_id)) {
    const room = `${body.venue_id}:${body.tag_id}`;
    if (!rooms.has(room)) throw new ContextError(403, 'room_not_enabled');
    return { operation: body.operation, room };
  }
  throw new ContextError(400, 'invalid_request');
}
async function requestBody(req, signal) {
  const length = req.headers['content-length'];
  if (length !== undefined && (!/^\d+$/.test(String(length)) || Number(length) > MAX_BODY)) {
    throw new ContextError(413, 'request_too_large');
  }
  let raw = req.body;
  if (raw === undefined) {
    const chunks = []; let bytes = 0;
    for await (const chunk of req) {
      signal.throwIfAborted(); bytes += Buffer.byteLength(chunk);
      if (bytes > MAX_BODY) throw new ContextError(413, 'request_too_large');
      chunks.push(Buffer.from(chunk));
    }
    raw = Buffer.concat(chunks);
  }
  if (Buffer.isBuffer(raw)) raw = raw.toString('utf8');
  if (typeof raw !== 'string') raw = JSON.stringify(raw);
  if (typeof raw !== 'string' || Buffer.byteLength(raw) > MAX_BODY) throw new ContextError(413, 'request_too_large');
  try { return JSON.parse(raw); } catch { throw new ContextError(400, 'invalid_request'); }
}
async function boundedJSON(response, limit = MAX_REPLY, signal) {
  const reader = response.body?.getReader();
  if (!reader) throw new ContextError(502, 'context_unavailable');
  const chunks = []; let bytes = 0;
  const cancel = () => { void reader.cancel().catch(() => {}); };
  signal?.addEventListener('abort', cancel, { once: true });
  try {
    signal?.throwIfAborted();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > limit) throw new ContextError(502, 'context_unavailable');
      chunks.push(Buffer.from(value));
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } finally { signal?.removeEventListener('abort', cancel); cancel(); }
}
function selectValues(data, outputs) {
  if (!data || (data.errors && (!Array.isArray(data.errors) || data.errors.length)) || !Array.isArray(data.data)) {
    throw new ContextError(502, 'context_unavailable');
  }
  const values = {};
  for (const item of data.data) {
    if (!item || !outputs.includes(item.field)) continue;
    if (item.error || Object.hasOwn(values, item.field) || !Object.hasOwn(item, 'value')) {
      throw new ContextError(502, 'context_unavailable');
    }
    const value = item.value;
    if (item.field.endsWith('.spoken') && (typeof value !== 'string' || !value.trim() || value.length > 2000)) {
      throw new ContextError(502, 'context_unavailable');
    }
    if (item.field.endsWith('.structure_visits') && (!Number.isSafeInteger(value) || value < 0)) {
      throw new ContextError(502, 'context_unavailable');
    }
    if (item.field.endsWith('.targets') || item.field.endsWith('.structure') && value !== null) {
      if (typeof value !== 'string' || Buffer.byteLength(value) > 60000) throw new ContextError(502, 'context_unavailable');
      let parsed;
      try { parsed = JSON.parse(value); } catch { throw new ContextError(502, 'context_unavailable'); }
      if (item.field.endsWith('.targets') ? !Array.isArray(parsed) || parsed.length > 100 :
        !parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new ContextError(502, 'context_unavailable');
    }
    values[item.field] = value;
  }
  if (Object.keys(values).length !== outputs.length) throw new ContextError(502, 'context_unavailable');
  return values;
}

// Per-instance bounds are defense in depth, not a distributed quota or budget.
export function createContextHandler({ loadConfig = readContextConfig, fetchImpl = fetch,
  now = Date.now, timeoutMs = 10000, requestsPerMinute = 12, instanceRequestsPerMinute = 120 } = {}) {
  let config; let active = 0; let windowStart = 0; let attempts = 0;
  const users = new Map();
  return async (req, res) => {
    if (req.headers['x-forwarded-proto'] !== 'https') return reply(res, 426, { error: 'https_required' });
    if (!['/context', '/api/context'].includes(req.url)) return reply(res, 404, { error: 'not_found' });
    if (req.method !== 'POST') return reply(res, 405, { error: 'method_not_allowed' }, { Allow: 'POST' });
    const authorization = req.headers.authorization;
    if (typeof authorization !== 'string' || !/^Bearer [A-Za-z0-9._~-]{16,8192}$/.test(authorization)) {
      return reply(res, 401, { error: 'unauthorized' });
    }
    if (!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type'] || '')) {
      return reply(res, 415, { error: 'json_required' });
    }
    try { config ||= loadConfig(); } catch { return reply(res, 503, { error: 'context_not_configured' }); }
    const time = now();
    if (time - windowStart >= 60000) { windowStart = time; attempts = 0; }
    if (active >= 8 || ++attempts > instanceRequestsPerMinute) return reply(res, 429, { error: 'rate_limited' });
    active++;
    const controller = new AbortController();
    let timer;
    const deadline = new Promise((_, reject) => {
      timer = setTimeout(() => { controller.abort(); reject(new ContextError(504, 'context_timeout')); }, timeoutMs);
    });
    const fetchJSON = async (url, options, limit) => {
      controller.signal.throwIfAborted();
      const response = await fetchImpl(url, { ...options, redirect: 'error', signal: controller.signal });
      if (!response.ok) {
        void response.body?.cancel().catch(() => {});
        if (url.endsWith('/auth/v1/user') && [401, 403].includes(response.status)) throw new ContextError(401, 'unauthorized');
        throw new ContextError(502, 'context_unavailable');
      }
      return boundedJSON(response, limit, controller.signal);
    };
    const execute = async () => {
      const request = parseRequest(await requestBody(req, controller.signal), config.rooms);
      const user = await fetchJSON(`${config.supabaseOrigin}/auth/v1/user`, {
        method: 'GET', headers: { Authorization: authorization, apikey: config.publishableKey, Accept: 'application/json' },
      }, 32768);
      if (!user || typeof user.id !== 'string' || !UUID.test(user.id)) throw new ContextError(401, 'unauthorized');
      const userID = user.id.toLowerCase();
      for (const [id, entry] of users) if (time - entry.start >= 60000) users.delete(id);
      const quota = users.get(userID) || { start: time, count: 0 };
      if (users.size >= 1024 && !users.has(userID) || ++quota.count > requestsPerMinute) throw new ContextError(429, 'rate_limited');
      users.set(userID, quota);
      const grant = await fetchJSON('https://api.chalk.ai/v1/oauth/token', {
        method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ client_id: config.clientID, client_secret: config.clientSecret, grant_type: 'client_credentials' }),
      }, 32768);
      if (typeof grant?.access_token !== 'string' || !/^[A-Za-z0-9._~+-]{16,8192}$/.test(grant.access_token) ||
          typeof grant.engines?.[config.environmentID] !== 'string' ||
          origin(grant.engines[config.environmentID]) !== config.engineOrigin) throw new ContextError(502, 'context_unavailable');
      const outputs = OUTPUTS[request.operation];
      const inputs = request.operation === 'last_seen' ? { 'object_history.id': `${userID}:${request.object}` } : { 'room_memory.id': request.room };
      const data = await fetchJSON(`${config.engineOrigin}/v1/query/online`, {
        method: 'POST', headers: { Authorization: `Bearer ${grant.access_token}`, 'Content-Type': 'application/json',
          'X-Chalk-Env-Id': config.environmentID, 'X-Chalk-Client-Id': config.clientID, 'X-Chalk-Deployment-Type': 'engine' },
        body: JSON.stringify({ inputs, outputs, query_name: request.operation }),
      });
      return { values: selectValues(data, outputs) };
    };
    try { return reply(res, 200, await Promise.race([execute(), deadline])); }
    catch (error) { return reply(res, error instanceof ContextError ? error.status : 502,
      { error: error instanceof ContextError ? error.code : 'context_unavailable' }); }
    finally { clearTimeout(timer); controller.abort(); active--; }
  };
}
