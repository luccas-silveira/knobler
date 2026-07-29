# 🏁 SESSÃO 2026-07-29 (madrugada, 3ª) — adiar lembrete + **v0.11.0 publicada**

Sessão curta de uma feature só. O `[Unreleased]` que a sessão anterior deixou
acumulado **saiu**: `v0.11.0` está no GitHub Releases e no cask.

## O que foi feito

**Adiar lembrete direto no card do notch** (`1a29ef4`). Quando um lembrete
dispara, o card traz **Adiar 5 min** e **30 min**.

O diff é pequeno porque quase tudo já existia — a UI de botão no card
(`actionTitles` / `actionToken`) tinha sido escrita na sessão anterior pro
AirDrop e **só rodava em alerta de Apple ID alheio**. Agora roda todo dia.

| Peça | Onde |
|---|---|
| `snooze(_:minutes:now:)` — empurra o `nextFire` sem tocar na agenda | `Reminders.swift` (engine) |
| `onFire` manda `actionToken: r.id` + os dois títulos | `KnoblerApp.swift:336` |
| Roteamento por token: lembrete → snooze, resto → interceptor | `KnoblerApp.swift:749` |
| `snoozeOptions` (títulos + minutos, fonte única) | `KnoblerApp.swift:66` |

Duas decisões que valem lembrar:

- **O adiamento vence uma vez só.** Ao disparar, o tick recomputa a agenda
  normal — um diário adiado pras 09:05 volta pras 09:00 no dia seguinte.
- **Um `oneShot` precisa ser religado no snooze.** O `onFire` já o desligou
  quando o card apareceu, e o tick pula item desabilitado — sem religar, o
  adiamento nunca venceria. Custou uma linha, mas é invisível na leitura.

## A descoberta que matou a feature que eu ia fazer

A recomendação inicial era **notificações de app com ações** (Responder,
Marcar como lida) — parecia barata, já que a infra de botão existe. Não é.

Acionar a ação exige o `AXUIElement` do banner **vivo**, e o interceptor fecha
o banner justamente pra o notch substituí-lo. Ou o balão do sistema fica na
tela duplicado com o card, ou não há ação — não existe meio-termo via AX.
Anotado com ⚠️ em `docs/IDEIAS.md` pra não custar essa descoberta de novo.

Trocamos pelo snooze, que é a mesma UI sem nenhum AX no caminho.

## Validação

- `./tools/check.sh`: **14 checks** (eram 13). O `reminderscheck` entrou —
  o `-D REMINDERS_SELFCHECK` existia desde sempre no `Reminders.swift` mas
  **nunca rodava no CI**. O novo assert cobre adiar → não dispara antes →
  dispara na hora → não redispara → agenda diária intacta no dia seguinte.
- **Ao vivo, ciclo completo** (lembrete de teste via `defaults write`, removido
  depois): card com os dois botões às 00:14 · clique roteou pro snooze
  (o `enabled` do `oneShot` voltou a `true` no plist, coisa que **só** o snooze
  faz) às 00:16 · card reapareceu às **00:21**, exatos 5 min depois.
- Release: build Release + `satisfies its Designated Requirement` (cert local
  `Knobler Local Signing`, então o TCC não revoga a Acessibilidade).

## Pendências e followups

Novas desta sessão:

- **O adiamento mora na memória.** Reiniciar o Knobler antes de vencer devolve
  o lembrete ao horário original. Registrado no IDEIAS; persistir junto do
  `Reminder` resolveria.

Herdadas e ainda abertas:

- **`Compartilhar…` (menu nativo) não teve confirmação visual** — plano B
  (montar `NSMenu` com `NSSharingService.sharingServices(forItems:)`) segue
  mapeado na sessão abaixo.
- **Aceitar/Recusar espelhado nunca foi exercitado** — precisa de um AirDrop de
  Apple ID diferente.
- **Markdown → PDF ignora tabela, imagem embutida e regra horizontal.**
- **Sem notarização**: `KNOBLER_NOTARY_PROFILE` não estava setado, então a
  0.11.0 saiu com o cert local. Quem instalar fora do cask vê o Gatekeeper.

---

# 🆕 SESSÃO 2026-07-29 (madrugada, 2ª) — três features tiradas do IDEIAS

Sessão de feature, não de manutenção: conta-gotas, conversão de arquivos e
AirDrop saíram do `docs/IDEIAS.md` e entraram no app. `[Unreleased]` acumula as
três — **nada foi publicado**, é `./tools/release.sh minor` → v0.11.0 quando
quiser.

## O que foi feito

| Feature | Onde vive | Como se usa |
|---|---|---|
| Conta-gotas | `ColorPicker.swift` | menu da barra → **◉ Selecionar cor…**; HEX vai pro clipboard, card mostra RGB/SwiftUI e a amostra da cor |
| Conversão de arquivos | `FileConverter.swift` (despachante), `ImageConverter`, `DocumentConverter`, `VideoConverter` | botão direito na miniatura do shelf → **Converter ▸** |
| Compartilhar / AirDrop | `Sharing.swift` | mesmo menu → **Compartilhar ▸ Enviar por AirDrop / Compartilhar… / Enviar tudo** |

Conversões por tipo: imagem → PNG/JPEG/HEIC/PDF · PDF → PNG por página (2x) ·
vídeo → MP4/MOV (passthrough quando o codec cabe, senão recodifica, com
progresso na faixa de atividade) · Markdown → PDF renderizado no app (parser do
Foundation + CoreText, paginado em Letter).

## A descoberta que mudou o desenho do AirDrop

A ideia original dizia "o app impede o recebimento" e a decisão inicial foi
espelhar **Aceitar/Recusar** no notch. `tools/axdump.swift` (criado nesta
sessão, fica no repo) mostrou que **esse par de botões não existe** entre
dispositivos do mesmo Apple ID — o macOS aceita sozinho e o que aparece é:

```
AXGroup [AXNotificationCenterAlert] AXDescription="AirDrop, Recebendo uma foto"
        actions=["AXPress", "Name:Mostrar Detalhes", "Name:Fechar"]
```

A ação `Name:Fechar` casava com `closeActionHints` — o interceptor fechava o
alerta que **acompanha a transferência viva**. Era essa a interferência.

Conserto: `process()` só fecha quando não é AirDrop **e** não há botão de ação.
O alerta do sistema fica de pé e o card do notch virou espelho, não substituto.
O espelhamento de botões foi implementado mesmo assim (aciona o botão real via
`AXUIElementPerformAction`, card dura 30s) — mas **nunca rodou de verdade**:
só entra em cena recebendo de outro Apple ID.

## Validação

- `./tools/check.sh`: **13 checks** (eram 9) — novos: `colorpickercheck`,
  `imageconvertercheck`, `documentconvertercheck`, `sharingcheck`.
- Build Debug ok; `tools/snapshot.sh` regenerando.
- Ao vivo: conta-gotas (`#BC7426` no clipboard), Markdown → PDF conferido em
  imagem rasterizada, AirDrop recebido **e** enviado pelo usuário.

## Pendências e followups

- **`Compartilhar…` (menu nativo) não teve confirmação visual.** Ancora num
  `NSPanel` nonactivating e popover pode não aparecer. Plano B mapeado: montar
  `NSMenu` com `NSSharingService.sharingServices(forItems:)` +
  `popUp(positioning:at:in:nil)`, sem âncora (API depreciada no 13, aceita).
- **Aceitar/Recusar espelhado nunca foi exercitado** — precisa de um envio de
  Apple ID diferente.
- **Publicar a v0.11.0** (`./tools/release.sh minor`).
- Markdown → PDF ignora tabela, imagem embutida e regra horizontal (o alt text
  da imagem vira linha de texto). Registrado no IDEIAS.
- `tools/snapshot.sh` estava quebrado desde a 0.10.0 (faltava
  `Permissions.swift` na lista manual) — consertado de passagem.

## Segurança

O review automático pegou um `file://` que **eu** tinha aberto no allowlist do
`openSourceApp` pro card do AirDrop revelar o Downloads. Era exploitável:
`WebhookClient.swift:237` preenche `openURL` com payload do relay externo, então
um webhook abriria qualquer app do disco. Revertido — o card usa o campo
`revealsDownloads` e o caminho vem de `FileManager.urls(for: .downloadsDirectory)`.

---

# 🆕 SESSÃO 2026-07-29 (madrugada) — as pendências de cobertura, fechadas

Plano: `docs/superpowers/plans/2026-07-28-fechar-pendencias.md`. Quatro
pendências dependiam de nós; três fecharam, a quarta é bloqueio externo.

## A única mudança de código

A decisão **pareado / trancado / nunca pareado** estava inline no
`ensurePairedThenConnect`, junto de `URLSession` e do relay — não havia como
exercitá-la sem rede, e era exatamente a lógica que a pendência do keychain
queria cobrir. Virou `WebhookKeychainStore.PairingState` +
`pairingState(load:exists:)`, pura, com `tools/webhookcheck.swift` cobrindo os
quatro casos (inclusive **meio segredo aberto** → `locked`, que o código antigo
já tratava por acidente da ordem dos `if`). `check.sh` foi de 8 pra 9 checks.
Comportamento do app idêntico — commit `b042507`.

## As três validações ao vivo, contra a 0.10.1

A 0.10.1 foi publicada como veículo: os dois caminhos do updater só podem ser
exercitados contra uma release mais nova que a instalada.

| Pendência | Como foi provada | Desfecho |
|---|---|---|
| Update pelo brew (nunca rodou de ponta a ponta) | card no notch anunciou a 0.10.1 com **Atualizar** (não "Ver release" → `canInstall` verdadeiro), clique instalou por `brew upgrade --cask` | 0.10.1, cask ainda gerenciando, `axTrusted/tapExists/tapEnabled` todos `true` |
| Caminho direto (`.zip` → `replaceItemAt` → relançar) | `brew uninstall`, 0.10.0 instalada por `ditto`, `brew list` passou a falhar → o updater caiu no `installDirect` | 0.10.1 com o binário de 22:19 dentro de um app que o brew não conhecia; permissões intactas; app devolvido ao brew no fim |
| Ramo trancado do keychain | os 3 segredos gravados pelo `security(1)`, cuja ACL o app não abre — `exists == true`, `load == nil`, sem tocar na assinatura | UI mostrou **Credenciais inacessíveis** + **Parear de novo**, os itens falsos ficaram intactos (o app parou em vez de registrar por cima), e o `repair()` trocou o `tokenfalso` por um token real do relay |

O truque do `security(1)` vale registrar: até aqui, reproduzir o keychain
trancado exigia trocar a assinatura do app. Como a ACL pertence a **quem
gravou**, gravar por outro binário produz o mesmo estado — repro barato e
reversível, sem mexer em assinatura nem em TCC.

**Nenhum dos dois updates derrubou a Acessibilidade**, que era o risco herdado
das sessões anteriores: as duas vias assinam com `Knobler Local Signing`, então
o `csreq` guardado pelo TCC continua batendo.

## Grafo

Regenerado em modo incremental (22 arquivos alterados): **2036 nós, 3799
arestas, 161 comunidades** — 95k tokens contra os 639k da passada completa.
`// ponytail:` das 161 comunidades, só as 22 maiores ganharam nome; o resto
ficou `Comunidade N`.

## Pendências

- **Notarização** (`KNOBLER_NOTARY_PROFILE`) — bloqueada por dependência
  externa: o caminho existe no `tools/release.sh` desde a 0.10.0 e espera uma
  conta Apple Developer paga. Enquanto não houver, o cask segue removendo a
  quarentena no install, e os caveats explicam isso ao usuário.

---

# SESSÃO 2026-07-28 (madrugada) — a 0.10.0 instalada e validada ao vivo

A 0.10.0 tinha sido publicada sem nunca ter sido instalada: não existia
`Knobler.app` nesta máquina — nem em `/Applications`, nem em `~/Applications`,
nem no Caskroom (o `brew list --cask knobler` quebrava com "diretório sumiu").
Painel de Permissões, keychain sem prompt de senha e o pedido único de
Acessibilidade tinham ido pro ar só com o build passando. Esta sessão fechou
isso: instalou pelo cask e provou cada uma no app rodando.

A sessão que **produziu** a 0.10.0 não deixou entrada aqui; o que ela entregou
está no `CHANGELOG.md` e nos commits `b8857e1` (painel de Permissões + pedido no
primeiro uso), `12d1f3b` (assinatura honesta, keychain sem prompt, notarização
pronta) e `f6ac5eb` (release).

## Validado ao vivo

| O que | Prova |
|---|---|
| Instalação pelo cask | `brew install --cask knobler` → 0.10.0 em `/Applications`, `codesign` diz `Authority=Knobler Local Signing` |
| Painel de Permissões | as 7 linhas com estado real: Microfone e Calendários *Concedida*, Câmera *Não solicitada*, Rede local/Arquivos/Áudio do sistema *Ainda não usada* |
| Keychain sem senha | app aberto duas vezes, zero diálogos de login keychain — e os itens `com.zoi.knobler.webhook` de instalações antigas estavam lá, então o cenário do bug estava armado |
| Pedido único de Acessibilidade | o diálogo do sistema apareceu no launch (`promptAccessibilityOnce`) |
| Recuperação do tap | depois de remover e re-adicionar o Knobler na lista de Acessibilidade, `GET /status` deu `axTrusted: true, tapExists: true, tapEnabled: true` **sem relançar o app** — o `checkTapHealth` recriou o tap sozinho |
| Badge da barra | `◐⚠` enquanto faltava a permissão, `◐` depois de conceder — ciclo completo do P2 da 0.9.0 |

Detalhe do TCC que vale lembrar: o Knobler **já estava** na lista de
Acessibilidade com o toggle ligado e mesmo assim `AXIsProcessTrusted()` era
`false` — a entrada guardava a assinatura de uma instalação anterior. Ligar/
desligar não basta em todo caso; remover com `−` e deixar o diálogo re-adicionar
resolve.

## Achado: os caveats do cask nunca foram publicados

O CHANGELOG da 0.10.0 afirma que "os caveats do cask foram reescritos", mas o
`brew info --cask knobler` ainda serve o texto velho — "assinado ad-hoc" e
permissões que o app não pede (Automação, Bluetooth).

Causa: os **dois clones do tap** divergiram. O commit `481fd62` ficou parado em
`~/Desktop/Ferramentas/homebrew-knobler` enquanto o `release.sh` bumpou a 0.10.0
pelo clone do `brew` (`/opt/homebrew/Library/Taps/...`). É a mesma pegadinha que
o handoff da 0.9.0 previu — o `pull --ff-only` que o script ganhou protege o
clone que ele usa, não o outro. Rebaseado sobre `origin/main` (`1944b7d` em cima
do bump 0.10.0).

## Pendências

- ~~Push do commit dos caveats~~ — publicado (`1944b7d`); `brew info --cask
  knobler` já serve as seções `ASSINATURA` e `PERMISSÕES` novas.
- ~~Dois clones do tap~~ — resolvido eliminando a possibilidade de divergir, não
  detectando-a: `~/Desktop/Ferramentas/homebrew-knobler` virou **symlink** pro
  clone do `brew`, então o caminho antigo continua funcionando e editar por ali
  edita o clone que o `release.sh` usa. Uma guarda no script não teria pego este
  caso — o clone do Desktop nunca esteve entre os candidatos que ele procura
  (`tools/release.sh:14-29`). O clone canônico agora está documentado em
  [development.md](docs/development.md#release).
- ~~Caminho trancado do keychain~~, ~~caminho direto do updater~~ e ~~teste de
  aceitação do update~~ — fechados na madrugada seguinte, ver a entrada acima.
- **Notarização** (`KNOBLER_NOTARY_PROFILE`) nunca exercitada — precisa de conta
  Apple Developer paga.

---

# SESSÃO 2026-07-28 (noite) — P1 e P2 do ditado + release 0.9.0

As duas pendências que sobraram de 25/07 — a causa (duas identidades de
assinatura) e o sintoma (falha silenciosa) — e, no fim, a publicação da 0.9.0
com tudo que estava parado em `[Unreleased]`.

## O que foi feito

**P1 — uma identidade só.** `project.yml` assinava com
`Apple Development: … (J8UFPJ9AZJ)` e o `tools/release.sh` com
`Knobler Local Signing`. Copiar um build por cima do outro em `/Applications`
trocava a identidade, invalidava o `csreq` guardado pelo TCC e matava o ditado em
silêncio. Agora `CODE_SIGN_IDENTITY: "Knobler Local Signing"` no `project.yml`
(e `DEVELOPMENT_TEAM` removido — cert self-signed não tem team). A CI não
precisa do cert: builda com `CODE_SIGNING_ALLOWED=NO`.

**P2 — o aviso saiu do notch e foi pra barra de menus.** Com o ditado ligado e
`AXIsProcessTrusted() == false`, o ícone vira `◐⚠` e o menu ganha
**⚠ Ditado precisa de Acessibilidade…**, que abre o painel do sistema. A pílula
de 2s do launch continua, mas deixou de ser o único sinal. Descartada a pílula
persistente no notch da proposta original: ela cobriria mídia, HUDs e o resto
enquanto a permissão faltasse.

O badge não abriu timer novo — pegou carona no `checkTapHealth`
(`VolumeHUD.swift`), que já sondava a Acessibilidade a cada 3s. Ele ganhou
`onAXTrust`, disparado só na mudança; o `AppDelegate` reavalia o título ali e no
sink de `AppSettings` (o toggle do ditado também muda a condição).

Arquivos: `project.yml`, `Knobler/KnoblerApp.swift`, `Knobler/VolumeHUD.swift`,
`CHANGELOG.md`, `README.md`, `docs/development.md`, `docs/troubleshooting.md`.

## Validação

- `xcodebuild` Debug ✅; `codesign -dvv` do produto imprime
  `Authority=Knobler Local Signing` — o P1 provado no artefato, não no YAML.
- `./tools/check.sh` → 8/8 ✅ (o gate do Codex segue pulado sem `--com-ambiente`).
- **Badge verificado ao vivo** (no fim da sessão): instalar a 0.9.0 trocou a
  identidade da cópia de `/Applications`, o TCC invalidou a Acessibilidade e o
  ícone da barra virou `◐⚠` — screenshot da barra de menus confirma, com
  `GET /status` lendo `axTrusted: false, tapExists: false`.

## Release 0.9.0 publicada

`./tools/release.sh minor` rodou limpo depois de um `--dry-run` de validação:
tag `v0.9.0`, commit `5b94c3a` (bump de `project.yml` + `CHANGELOG`), `.app`
assinado com `Knobler Local Signing` (`satisfies its Designated Requirement`),
`Knobler-0.9.0.zip` no [release](https://github.com/luccas-silveira/knobler/releases/tag/v0.9.0)
e cask bumpado no tap (`eba0691`). CI verde em todos os commits da sessão.

**Pegadinha achada na hora, já corrigida** (`680e638`): o caminho do tap era fixo
em `../homebrew-knobler` e o clone está em `~/Desktop/Ferramentas/homebrew-knobler`
— o release só passou com `KNOBLER_TAP_DIR=` na frente. Agora o script procura ao
lado do repo e no tap do `brew`, e dá `pull --ff-only` antes de bumpar: existem
**dois clones** do tap nesta máquina e o atrasado falharia no push com o cask já
editado. Os dois estão sincronizados em `0.9.0` agora.

## Instalação da 0.9.0 (feita)

Escolhida a via **Homebrew** em vez do `ditto`: `brew install --cask knobler`,
depois de mover a cópia 0.8.4 pra fora de `/Applications` (o brew recusa
sobrescrever app não gerenciado). Confirmado: `Authority=Knobler Local Signing`,
`CFBundleShortVersionString 0.9.0`, `brew list --cask knobler` responde. O sha256
do zip publicado foi baixado e conferido contra o cask — batem.

Consequência prevista e observada: o TCC invalidou a Acessibilidade na troca de
identidade. **Falta reconceder no painel** (aberto na sessão, mas o clique é
manual). Depois disso o `checkTapHealth` recria o tap sozinho e o badge some.

Efeito colateral útil: com o app gerenciado pelo brew, o updater passa a usar o
caminho `brew upgrade --cask knobler`. O caminho direto (baixar `.zip` → validar
→ `replaceItemAt` → relançar) **continua sem nunca ter sido exercitado**.

## Pendências

- **Publicado**: `f70f427` (assinatura), `980f478` (badge), `5b94c3a` (v0.9.0),
  `680e638` (tap do release).
- **Reconceder a Acessibilidade** — pendência de clique humano, não de código.
  Enquanto não fizer, o ditado não inicia (e o `◐⚠` fica na barra avisando).
- **Teste de aceitação do update real**: na próxima release, o app deve avisar
  sozinho e atualizar por `brew upgrade --cask knobler`. O caminho direto
  (`.zip` → `replaceItemAt` → relançar) segue sem cobertura — para exercitá-lo
  seria preciso uma instalação fora do brew.
- A partir de agora as duas vias assinam igual, então instalar por cima **não**
  derruba mais a Acessibilidade. Esta foi a última vez.
- ~~`CLAUDE.md` afirmava que o `glassEffect`/Liquid Glass estava em uso~~ —
  corrigido nesta sessão (zero ocorrências no código; o target é macOS 14.2).
- ~~`graphify-out/` sem regenerar~~ — regenerado no fim da sessão: 1943 nós,
  3787 arestas, 112 comunidades (1689 nós de AST + 409 semânticos, 639k tokens).
  As 29 imagens de `docs/images/` ficaram de fora da camada semântica — são
  screenshots de UI já referenciados pelos `.md` e cada uma exigiria um agente de
  visão próprio. Snapshots também regenerados: 51/51 cenários ok.


---

Sessões anteriores estão em
[`docs/handoffs/2026-07.md`](docs/handoffs/2026-07.md).
