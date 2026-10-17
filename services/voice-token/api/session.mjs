import { createVercelHandler } from '../vercel-handler.mjs';

// Reuse the same handler and limiter for every request on this warm instance.
export default createVercelHandler();
