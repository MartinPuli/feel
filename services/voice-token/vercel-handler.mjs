import { createTokenHandler, readConfig, reply } from './server.mjs';

export function createVercelHandler({ loadConfig = readConfig, ...options } = {}) {
  let handler;
  return async (req, res) => {
    if (!handler) {
      try {
        // Always require Vercel's HTTPS marker, even if local config disables it.
        handler = createTokenHandler({ ...loadConfig(), requireHTTPS: true }, {
          ...options,
          sessionPaths: ['/session', '/api/session'],
        });
      } catch {
        // An incomplete deployment must not emit environment values or stack traces.
        return reply(res, 503, { error: 'voice_service_not_configured' });
      }
    }
    return handler(req, res);
  };
}
