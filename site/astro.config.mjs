// @ts-check
import { defineConfig } from 'astro/config';
import { cpSync } from 'node:fs';

// Copia as imagens das novidades do app pra /novidades/midia/ no build
// (inclusive com --outDir, que pula o prebuild do package.json).
const midia = {
  name: 'novidades-midia',
  hooks: {
    'astro:build:done': ({ dir }) =>
      cpSync(new URL('../Knobler/Novidades/midia/', import.meta.url), new URL('novidades/midia/', dir), { recursive: true }),
  },
};

// https://astro.build/config
export default defineConfig({
  site: "https://knobler.appzoi.com.br",
  integrations: [midia],
});
