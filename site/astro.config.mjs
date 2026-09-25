// @ts-check
import { defineConfig } from 'astro/config';
import { cpSync } from 'node:fs';
import { carregarDocs } from './src/lib/docs.mjs';

// Copia as imagens das novidades do app pra /novidades/midia/ no build
// (inclusive com --outDir, que pula o prebuild do package.json).
const midia = {
  name: 'novidades-midia',
  hooks: {
    'astro:build:done': ({ dir }) =>
    {
      cpSync(new URL('../Knobler/Novidades/midia/', import.meta.url), new URL('novidades/midia/', dir), { recursive: true });
      // Só as imagens citadas pelos docs técnicos, não a pasta inteira.
      for (const { imagens } of carregarDocs(new URL('../docs/', import.meta.url).pathname))
        for (const img of imagens) cpSync(new URL(`../docs/${img}`, import.meta.url), new URL(`docs/${img}`, dir));
    },
  },
};

// https://astro.build/config
export default defineConfig({
  site: "https://knobler.appzoi.com.br",
  integrations: [midia],
});
