# Pesquisa — distribuição via Homebrew (fase que antecede o plano)

Data: 2026-07-20
Alimenta: `2026-07-20-distribuicao-homebrew-design.md`

Duas suposições da 1ª versão da spec foram testadas contra fonte autoritativa +
verificação empírica na máquina (Homebrew 6.0.11, macOS 26). Uma passou, duas
falharam e forçaram correção.

## Achado 1 — `--no-quarantine` (flag CLI) está removida ❌

- **Verificado na máquina:** `brew install --cask --no-quarantine <cask>` é rejeitada
  (cospe o "Usage" em vez de instalar). O parser que sobrou em `env_config.rb:907`
  (`cask_opts_quarantine?`) é do **env var** `HOMEBREW_CASK_OPTS`, não da flag CLI —
  o teste com `HOMEBREW_CASK_OPTS="--no-quarantine"` passou reto pro "cask unavailable".
- **Fonte:** removida no Homebrew 5.1 (Issue #20755, Discussion #6537). Afeta todos os
  taps (é flag do `brew` core, não política de tap).
- **Correção:** não depender da flag. Usar bloco **`postflight`** no cask que roda
  `xattr -dr com.apple.quarantine` no app instalado. Confirmado que `postflight`
  (`cask/dsl.rb`) e o `quarantine.swift` existem no brew local. Amigo passa a rodar
  `brew install --cask knobler` — sem flag.

## Achado 2 — assinar com *Apple Development* é a PIOR opção ❌ (o grande)

O que quebra o plano não é o Homebrew, é a escolha de assinatura.

- **Remover quarantine bypassa o Gatekeeper de primeiro-launch no Sequoia/Tahoe: SIM**
  (confirmado — Howard Oakley, DTS Apple, HackTricks). Sem quarantine, sem diálogo de
  "desenvolvedor não identificado"/"danificado". A mudança do Sequoia (fim do
  botão-direito→Abrir → Ajustes → "Abrir Assim Mesmo") só morde apps **com** quarantine.
- **MAS há um 2º gate independente, o AMFI** (code-signing enforcement, sempre ativo no
  Apple Silicon). Uma assinatura *Apple Development* é válida pro AMFI, porém embute um
  **provisioning profile de desenvolvimento** com **allowlist de dispositivos**
  (`ProvisionedDevices`) + **expiração** (~7 dias no time grátis, ~1 ano no pago).
  Developer ID / Enterprise têm `ProvisionsAllDevices`; Development **não**.
- **Consequência:** o Mac do amigo (não registrado) provavelmente **não abre o app** —
  falha de launch (crash/encerramento silencioso), não a palavra "danificado". E expira
  até no próprio Mac do autor. É o oposto do que se quer pra distribuição.
- **Precedentes reais:** boring.notch (Issue #1106) e TomatoBar (Issue #102) — apps de
  notch/pomodoro — bateram nessa parede e tiveram de remover o `--no-quarantine` do README.

### Correção: distribuir **ad-hoc**, não Apple Development

- `codesign --force --deep --sign - Knobler.app` (ad-hoc) **não tem allowlist de
  dispositivo nem expiração** e é válido pro AMFI no Apple Silicon → roda em qualquer Mac.
  Para determinismo, também remover `Contents/embedded.provisionprofile` se existir antes
  de re-assinar.
- Ad-hoc é *estritamente melhor* que Apple Development pra este caso (free): sem device
  lock, sem expiração, mesma ausência de confiança-de-Gatekeeper (resolvida pelo strip de
  quarantine).
- **Fragilidade residual (honestidade):** ad-hoc + `postflight` abre limpo **via brew**.
  Se o app for re-baixado/AirDropado por fora do brew, re-quarantina → Gatekeeper bloqueia
  app não-notarizado → `xattr` manual (documentado no `caveats`). O único "abre limpo pra
  sempre em qualquer Mac / qualquer via" é Developer ID + notarização ($99/ano) — dispensado.

## Achado 3 — convenções de cask/tap pessoal ✅ (rascunho ~correto, ajustes menores)

- Stanzas mínimas exigidas: `version`, `sha256`, `url`, `name`, `desc`, `homepage` + 1
  artefato (`app`). `depends_on`/`caveats` são opcionais. Ordem do rascunho já correta.
- `app "Knobler.app"` lida certo com zip cuja **raiz** é o `.app` (verificado localmente:
  `ditto -c -k --keepParent` põe `Knobler.app/` no topo).
- `depends_on macos: ">= :sonoma"` = **macOS 14+**. **14.2 minor não é expressável** no DSL
  (só major) → o piso 14.2 fica no `LSMinimumSystemVersion` (já vem do deployment target).
- `brew audit`/`brew style` **não bloqueiam** tap pessoal (checagens gated em
  `tap.official?`). Instala mesmo com nits. `livecheck`/`no_autobump!`/`auto_updates`/
  `deprecate!` **não são obrigatórios**.
- Repo **precisa** se chamar `homebrew-knobler` e ser **público** (amigos tapam sem auth).
  `brew tap luccas-silveira/knobler` → clona `.../homebrew-knobler`. `brew tap-new` scaffolda.
- Polimento: `desc` em inglês e sem artigo/sem a palavra "app" silencia nits do audit
  (ignorável); adicionar `zap trash:` pra uninstall limpo.

## Impacto no design (aplicado na spec)

1. `release.sh`: após build, **strip do provisioning profile + re-sign ad-hoc** (`-s -`),
   com `codesign --verify` de sanidade. Não usar a identidade Apple Development no artefato.
2. Cask: adicionar **`postflight`** (xattr) + **`zap trash:`**; `desc` em inglês; `caveats`
   pt-BR com o fallback manual do `xattr`.
3. Instrução do amigo: `brew install --cask knobler` (**sem** `--no-quarantine`).
4. Sem mudança: versão via `$(MARKETING_VERSION)`, artefato zip via `ditto`, `gh release`,
   auto-bump do tap, Ollama/Parakeet/permissões fora de escopo.

## Fontes-chave

- Homebrew: Issue #20755 e Discussion #6537 (remoção do `--no-quarantine`);
  Cask Cookbook, Taps, How-to-Create-a-Tap, Acceptable-Casks (docs.brew.sh).
- Assinatura: Apple "Distributing your app to registered devices", TN3125; Quinn
  (forums.apple 685723); Xojo "Code Signing Part 3" (2026); Eclectic Light (Oakley) sobre
  notarização só ser checada em apps com quarantine; DTS Apple thread 740680.
- Precedentes: boring.notch #1106, TomatoBar #102.
