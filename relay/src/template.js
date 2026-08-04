// Interpolação {{ dot.path }} — pura, sem lógica. Ausente/não-primitivo → vazio.
function resolve(payload, path) {
  let cur = payload;
  for (const part of path.split('.')) {
    if (cur == null || typeof cur !== 'object') return undefined;
    cur = Array.isArray(cur) ? cur[Number(part)] : cur[part];
  }
  return cur;
}

const pad = (n) => String(n).padStart(2, '0');

// Lista FECHADA de filtros (014). Um por token, sem argumentos.
// Todo filtro recebe e devolve string; inaplicável = devolve o valor cru.
const FILTROS = {
  semHifens: (s) => s.replaceAll('-', ''),
  data: (s) => {
    const ms = Number(s);
    if (!Number.isFinite(ms)) return s;
    const d = new Date(ms);
    if (Number.isNaN(d.getTime())) return s;
    return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  },
  quill: (s) => {
    let doc; try { doc = JSON.parse(s); } catch { return s; }
    if (!doc || !Array.isArray(doc.ops)) return s;
    return doc.ops.map((o) => (typeof o.insert === 'string' ? o.insert : '')).join('');
  },
};

function render(tpl, payload) {
  if (typeof tpl !== 'string') return '';
  return tpl.replace(/\{\{\s*([^}]+?)\s*\}\}/g, (_, expr) => {
    const [path, filtro] = expr.split('|').map((s) => s.trim());
    const v = resolve(payload, path);
    // só primitivos viram texto; objeto/array/undefined/null → vazio
    const cru = (v == null || typeof v === 'object') ? '' : String(v);
    const f = FILTROS[filtro];   // filtro desconhecido (ou valor vazio) → valor cru
    return f && cru ? f(cru) : cru;
  });
}

module.exports = { render, resolve, FILTROS };
