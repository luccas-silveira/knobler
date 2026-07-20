// Token bucket em memória por chave (deviceId). Sem dependências externas.
function createRateLimiter({ ratePerMin = 20, burst = 5, now = Date.now } = {}) {
  const refillPerMs = ratePerMin / 60000; // tokens por ms
  const buckets = new Map(); // key -> { tokens, ts }

  return {
    allow(key) {
      const t = now();
      let b = buckets.get(key);
      if (!b) { b = { tokens: burst, ts: t }; buckets.set(key, b); }
      // reabastece proporcional ao tempo passado, com teto no burst
      b.tokens = Math.min(burst, b.tokens + (t - b.ts) * refillPerMs);
      b.ts = t;
      if (b.tokens >= 1) { b.tokens -= 1; return { ok: true, retryAfter: 0 }; }
      const needed = 1 - b.tokens;
      const retryAfter = Math.ceil(needed / refillPerMs / 1000);
      return { ok: false, retryAfter: Math.max(1, retryAfter) };
    },
  };
}

module.exports = { createRateLimiter };
