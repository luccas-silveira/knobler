import { existsSync, readFileSync } from 'node:fs';
import { RECURSOS_SLUGS } from '../data/recursos-slugs.mjs';

export const DOCS = ['local-api', 'webhooks', 'plugins', 'troubleshooting'];
const GH = 'https://github.com/luccas-silveira/knobler/blob/master/docs/';

// Reescreve destinos de `](...)`, mesmo com quebra de linha entre `]` e `(`.
export function reescreverLinks(markdown) {
  const imagens = [];
  const saida = markdown.replace(/\](\s*)\(([^)\s]+)\)/g, (tudo, esp, destino) => {
    if (/^([a-z][a-z0-9+.-]*:|\/|#)/i.test(destino)) return tudo;
    const [arq, ancora] = destino.split(/(?=#)/);
    const suf = ancora ?? '';
    let novo;
    if (arq.startsWith('images/')) {
      imagens.push(arq);
      novo = `/docs/${arq}${suf}`;
    } else if (DOCS.includes(arq.replace(/\.md$/, '')) && arq.endsWith('.md')) {
      novo = `/docs/${arq.slice(0, -3)}${suf}`;
    } else if (RECURSOS_SLUGS[arq]) {
      novo = `/recursos/${RECURSOS_SLUGS[arq]}${suf}`;
    } else {
      novo = `${GH}${destino}`;
    }
    return `]${esp}(${novo})`;
  });
  return { markdown: saida, imagens };
}

export function carregarDocs(docsDir) {
  const base = new URL(String(docsDir).replace(/\/?$/, '/'), 'file:///');
  return DOCS.map((slug) => {
    const arq = new URL(`${slug}.md`, base);
    if (!existsSync(arq)) throw new Error(`Doc técnico ausente: ${slug}.md`);
    return { slug, ...reescreverLinks(readFileSync(arq, 'utf8')) };
  });
}
