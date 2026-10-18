// Server-only identity and admission. Neither caller metadata nor decoded JWT claims establish a user.
export const ADMISSION_OPERATIONS = Object.freeze(['voice_session', 'context_last_seen', 'context_room_structure', 'context_room_anchors']);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export class AdmissionError extends Error {
  constructor(status, code, retryAfter) { super(code); this.status = status; this.code = code; this.retryAfter = retryAfter; }
}
export function readAuthMode(env = process.env) {
  const mode = env.FEEL_VOICE_AUTH_MODE ?? 'demo';
  if (!['demo', 'supabase'].includes(mode)) throw new Error('Invalid FEEL_VOICE_AUTH_MODE');
  return mode;
}
export function readAdmissionConfig(env = process.env) {
  const url = new URL(env.SUPABASE_URL);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/' || url.port) {
    throw new Error('Set a trusted HTTPS SUPABASE_URL origin.');
  }
  const publishableKey = env.SUPABASE_PUBLISHABLE_KEY ?? '';
  const secretKey = env.SUPABASE_SECRET_KEY || env.SUPABASE_SERVICE_ROLE_KEY || '';
  if (!/^[\x21-\x7e]{16,8192}$/.test(publishableKey) || !/^[\x21-\x7e]{16,8192}$/.test(secretKey) || secretKey === publishableKey) {
    throw new Error('Configure separate Supabase public and server admission credentials.');
  }
  // Legacy role inspection only catches configuration mistakes; actual privileges are verified by Supabase.
  let legacy = false;
  if (!secretKey.startsWith('sb_secret_')) {
    try { legacy = JSON.parse(Buffer.from(secretKey.split('.')[1], 'base64url').toString()).role === 'service_role'; } catch {}
    if (!legacy) throw new Error('Admission requires a server secret or legacy service-role key.');
  }
  return { origin: url.origin, publishableKey, secretKey, legacy };
}
export function isBearer(value) { return typeof value === 'string' && /^Bearer [A-Za-z0-9._~-]{16,8192}$/.test(value); }
async function readJSON(response, signal, maxBytes) {
  const reader = response.body?.getReader();
  if (!reader) throw new AdmissionError(503, 'admission_unavailable');
  const chunks = []; let size = 0;
  const cancel = () => { void reader.cancel().catch(() => {}); };
  signal?.addEventListener('abort', cancel, { once: true });
  try {
    signal?.throwIfAborted();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) throw new AdmissionError(503, 'admission_unavailable');
      chunks.push(Buffer.from(value));
    }
    signal?.throwIfAborted();
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } finally { signal?.removeEventListener('abort', cancel); cancel(); }
}
async function requestJSON(url, init, { fetchImpl = fetch, signal }, maxBytes) {
  try {
    signal?.throwIfAborted();
    const response = await fetchImpl(url, { ...init, redirect: 'error', signal });
    if (!response.ok) {
      void response.body?.cancel().catch(() => {});
      if (url.endsWith('/auth/v1/user') && [401, 403].includes(response.status)) throw new AdmissionError(401, 'unauthorized');
      throw new AdmissionError(503, 'admission_unavailable');
    }
    return await readJSON(response, signal, maxBytes);
  } catch (error) {
    if (error instanceof AdmissionError || signal?.aborted) throw error;
    throw new AdmissionError(503, 'admission_unavailable');
  }
}
export async function verifyUser(authorization, config, transport = {}) {
  if (!isBearer(authorization)) throw new AdmissionError(401, 'unauthorized');
  const user = await requestJSON(`${config.origin}/auth/v1/user`, {
    method: 'GET', headers: { Authorization: authorization, apikey: config.publishableKey, Accept: 'application/json' },
  }, transport, 32768);
  if (typeof user?.id !== 'string' || !UUID.test(user.id) || user.id === '00000000-0000-0000-0000-000000000000') {
    throw new AdmissionError(401, 'unauthorized');
  }
  // Missing/unknown anonymous status is not silently promoted to a paying account.
  if (user.is_anonymous !== false) throw new AdmissionError(403, 'account_required');
  return user.id.toLowerCase();
}
export async function reserveAdmission(userID, operation, config, transport = {}) {
  if (typeof userID !== 'string' || !UUID.test(userID) || !ADMISSION_OPERATIONS.includes(operation)) {
    throw new AdmissionError(503, 'admission_unavailable');
  }
  const headers = { apikey: config.secretKey, 'Content-Type': 'application/json', Accept: 'application/json' };
  // Modern secret keys are not JWTs; only the legacy service-role JWT goes in Authorization.
  if (config.legacy) headers.Authorization = `Bearer ${config.secretKey}`;
  const result = await requestJSON(`${config.origin}/rest/v1/rpc/feel_reserve_admission`, {
    method: 'POST', headers, body: JSON.stringify({ p_user_id: userID, p_operation: operation }),
  }, transport, 4096);
  if (!result || Array.isArray(result) || typeof result !== 'object' ||
      Object.keys(result).sort().join(',') !== 'allowed,reason,retry_after_seconds' ||
      typeof result.allowed !== 'boolean' || !Number.isSafeInteger(result.retry_after_seconds) ||
      result.retry_after_seconds < 0 || result.retry_after_seconds > 86400) throw new AdmissionError(503, 'admission_unavailable');
  if (result.allowed && result.reason === 'allowed' && result.retry_after_seconds === 0) return;
  if (!result.allowed && result.reason === 'quota_exceeded' && result.retry_after_seconds > 0) {
    throw new AdmissionError(429, 'rate_limited', result.retry_after_seconds);
  }
  throw new AdmissionError(503, 'admission_unavailable');
}
