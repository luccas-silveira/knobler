// Interpolação {{ dot.path }} — pura, sem lógica. Ausente/não-primitivo → vazio.
function resolve(payload, path) {
  let cur = payload;
  for (const part of path.split('.')) {
    if (cur == null || typeof cur !== 'object') return undefined;
    cur = Array.isArray(cur) ? cur[Number(part)] : cur[part];
  }
  return cur;
}

function render(tpl, payload) {
  if (typeof tpl !== 'string') return '';
  return tpl.replace(/\{\{\s*([^}]+?)\s*\}\}/g, (_, path) => {
    const v = resolve(payload, path.trim());
    // só primitivos viram texto; objeto/array/undefined/null → vazio
    return (v == null || typeof v === 'object') ? '' : String(v);
  });
}

module.exports = { render, resolve };
