# 🏁 SESSÃO 2026-07-29 (madrugada, 4ª) — pendências fechadas + **v0.12.0 publicada**

Sessão de pendência, não de feature nova: das cinco abertas no topo do handoff
anterior, **três fecharam** — duas com código, uma só com teste. As duas que
sobraram dependem de coisa que não está nesta mesa.

## O que foi feito

**1. O adiamento do lembrete sobrevive ao restart** (`aa65f8d`). O `ScheduleEngine`
ganhou um `snoozed: [UUID: Date]` espelhado no UserDefaults: `snooze()` grava,
`init` lê, e o primeiro `tick()` depois do restart semeia o `nextFire` a partir
dele. Vencido (ou lembrete apagado), o adiamento some sozinho — continua valendo
uma vez só.

O hash do schedule **não** é persistido junto de propósito: `hashValue` é
randomizado por processo e não sobreviveria ao restart de qualquer jeito. O
preço é editar o horário com um adiamento no ar mantendo o adiamento; está
comentado no código.

**2. Tabela, imagem embutida e regra horizontal no Markdown → PDF** (`151c5c7`).
As três lacunas que o conversor carregava desde que nasceu.

| Peça | Como |
|---|---|
| Paginação | saiu do **CoreText** e foi pro **TextKit** — um `NSTextContainer` por página |
| Tabela | célula da mesma linha vira `\t`, um tab stop por coluna, alinhamento `:---`/`---:` respeitado |
| Imagem | `run.imageURL` resolvido contra a pasta do `.md` → `NSTextAttachment` reduzido pra caber |
| Régua | o "⸻" do parser repetido até a caixa, com `kern` negativo |

A troca de motor foi o nó: era o `CTFramesetter` que ignorava anexo e tab stop.
`NSLayoutManager` dá os dois de graça e custa menos código que a alternativa
(`CTRunDelegate` reservando espaço + desenho manual).

## As duas descobertas que só o olho pegou

Ambas saíram de rasterizar o PDF e **olhar**, não de teste passando.

- **A citação saía invisível.** O cinza vinha de `.secondaryLabelColor` — cor
  dinâmica, que resolve pela aparência do sistema e no modo escuro vira branco.
  Em papel branco, nada. Bug que já existia desde a 0.11.0 e nenhum assert
  pegaria. Agora é tinta fixa (`quoteGray`), com assert de brilho no self-check.
  Foi ele também que escondeu a régua na primeira tentativa e me fez trocar o
  traço por um tab sublinhado antes de achar a causa real.
- **O parser omite célula vazia.** `| Total | | 50,50 |` não gera run pra célula
  do meio, então um tab por run puxava o valor pra coluna errada. O contador de
  coluna virou explícito (`tableCell(intent)`).

**3. `Compartilhar…` (menu nativo)** — fechada sem código: exercitada ao vivo,
o menu abre e envia. O plano B (`NSSharingService.sharingServices(forItems:)`)
não foi preciso.

## Validação

- `./tools/check.sh`: **14 checks**. `reminderscheck` ganhou o caso do restart
  (engine A adia, engine B com `nextFire` zerado dispara na hora certa, engine C
  confirma que o adiamento vencido não ressuscita); `documentconvertercheck`
  ganhou três (tabela + régua + brilho da tinta; imagem com anexo medido e
  caminho quebrado caindo no alt).
- **PDF real rasterizado e conferido a olho** — foi o que achou os dois bugs
  acima. Vale repetir o hábito: `DocumentConverter.pngPages(fromPDF:)` num md de
  exemplo e ler o PNG.
- Release: build Release + `satisfies its Designated Requirement`, v0.12.0 no
  GitHub Releases e no cask.

## Pendências e followups

Sobraram as duas de bloqueio externo — nenhuma depende de código:

- **Aceitar/Recusar espelhado nunca foi exercitado** — precisa de um AirDrop
  vindo de **outro Apple ID**. Entre dispositivos do mesmo ID o macOS aceita
  sozinho e esse par de botões nem aparece.
- **Sem notarização**: `KNOBLER_NOTARY_PROFILE` espera uma conta Apple Developer
  paga. A 0.12.0 saiu com o cert local; o cask remove a quarentena no install e
  os caveats explicam.

Ideias que a sessão deixou registradas em `docs/IDEIAS.md`: preview da conversão
(hoje é às cegas, sem escolher qualidade/resolução).

---

# 🆕 SESSÃO 2026-07-29 (madrugada, 3ª) — adiar lembrete + **v0.11.0 publicada**

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
  `Reminder` resolveria. ✅ **Fechada na sessão de 29/07 (madrugada, 4ª).**

Herdadas e ainda abertas:

- ~~**`Compartilhar…` (menu nativo) não teve confirmação visual**~~ — exercitado
  ao vivo em 29/07: o menu abre e envia. Fechada sem código.
- **Aceitar/Recusar espelhado nunca foi exercitado** — precisa de um AirDrop de
  Apple ID diferente.
- ~~**Markdown → PDF ignora tabela, imagem embutida e regra horizontal.**~~ ✅
  **Fechada na sessão de 29/07 (madrugada, 4ª).**
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

