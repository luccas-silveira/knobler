// Helper de teste: roda `npm run build` em site/ uma vez por processo e devolve
// a URL do diretório dist/.
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const site = new URL('../', import.meta.url);
let dist;

export function build() {
  if (!dist) {
    execFileSync('npm', ['run', 'build'], { cwd: fileURLToPath(site), stdio: 'pipe' });
    dist = new URL('dist/', site);
  }
  return dist;
}
