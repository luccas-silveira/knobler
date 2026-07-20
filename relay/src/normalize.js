// Parse + sanitização + validação do payload do webhook.
// Aceita JSON, form-encoded e query string; devolve um objeto normalizado.

class ValidationError extends Error {
  constructor(message) { super(message); this.name = 'ValidationError'; this.statusCode = 400; }
}

const TITLE_MAX = 200;
const BODY_MAX = 1000;
const ID_MAX = 200;

/** Remove caracteres de controle (C0/C1) e apara; depois trunca. */
function clean(value, max) {
  if (typeof value !== 'string') return '';
  const stripped = value.replace(/[\x00-\x1f\x7f-\x9f]/g, ' ').trim();
  return stripped.slice(0, max);
}

/** Só aceita os esquemas dados; senão null. */
function safeURL(value, schemes) {
  if (typeof value !== 'string' || value === '') return null;
  try {
    const u = new URL(value);
    return schemes.includes(u.protocol) ? value : null;
  } catch { return null; }
}

function toBool(value) {
  if (value === true) return true;
  if (typeof value === 'string') return value === 'true' || value === '1';
  return false;
}

/** contentType: string; rawBody: string; query: objeto (chaves→valores string). */
function normalizePayload({ contentType = '', rawBody = '', query = {} }) {
  let raw = {};
  const ct = contentType.toLowerCase();
  if (ct.includes('application/json')) {
    try { raw = JSON.parse(rawBody || '{}'); }
    catch { throw new ValidationError('JSON inválido'); }
    if (raw === null || typeof raw !== 'object') throw new ValidationError('JSON não é objeto');
  } else if (ct.includes('application/x-www-form-urlencoded')) {
    raw = Object.fromEntries(new URLSearchParams(rawBody));
  }
  // query string sempre pode preencher o que faltar (corpo tem prioridade)
  raw = { ...query, ...raw };

  const title = clean(raw.title, TITLE_MAX);
  if (!title) throw new ValidationError('title é obrigatório');

  return {
    title,
    body: clean(raw.body, BODY_MAX),
    iconURL: safeURL(raw.icon, ['https:']),
    url: safeURL(raw.url, ['http:', 'https:']),
    sound: toBool(raw.sound),
    id: raw.id != null ? clean(String(raw.id), ID_MAX) || null : null,
  };
}

module.exports = { normalizePayload, ValidationError };
