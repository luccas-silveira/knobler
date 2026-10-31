// Helper de teste: roda o build do site uma vez por processo e devolve a URL do
// diretório de saída. `node --test` roda cada arquivo num processo próprio e em
// paralelo, então cada processo builda numa pasta temporária sua: dois builds no
// mesmo dist/ colidem. A pasta fica dentro de site/ (ignorada no git): fora do cwd
// o Astro volta a usar o .astro/ compartilhado e os builds colidem ali. O cache
// do Vite também é por processo (KNOBLER_VITE_CACHE, lido no astro.config.mjs):
// o padrão node_modules/.vite é um só, e o otimizador de dependências de um
// build apagava o deps_temp que o outro estava renomeando. A pasta (dist e cache,
// uns 5 MB) é apagada quando o processo sai: sem isso cada ./tools/check.sh
// deixava sete delas em site/.test-dist, pra sempre.
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const site = new URL('../', import.meta.url);
let dist;

export function build() {
  if (!dist) {
    const base = join(fileURLToPath(site), '.test-dist');
    mkdirSync(base, { recursive: true });
    const pasta = mkdtempSync(join(base, 'build-'));
    // `exit` é síncrono, e o rmSync também; cada arquivo do node --test roda
    // no próprio processo e só lê o dist enquanto os testes dele correm
    process.on('exit', () => rmSync(pasta, { recursive: true, force: true }));
    const out = join(pasta, 'dist');
    execFileSync('npx', ['astro', 'build', '--outDir', out], {
      cwd: fileURLToPath(site),
      stdio: 'pipe',
      env: { ...process.env, KNOBLER_VITE_CACHE: join(pasta, 'vite') },
    });
    dist = pathToFileURL(out + '/');
  }
  return dist;
}
