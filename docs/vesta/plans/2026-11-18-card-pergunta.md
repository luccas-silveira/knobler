# Plano — redesenho do card de pergunta do Claude

Objetivo: responder o `AskUserQuestion` do Claude Code no notch só pelo teclado, com abas para várias perguntas, visual acabado, texto e preview sempre inteiros, sem a pergunta nunca roubar o teclado.

Spec: `docs/vesta/specs/2026-11-18-card-pergunta-redesenho-design.md`
Dossiê: `docs/vesta/research/2026-11-18-card-pergunta-redesenho-research.md`
Comando de teste (da raiz do repo): `./tools/check.sh`
Pastas de tela: `Knobler`
Mockup: `docs/vesta/mockups/2026-11-18-card-pergunta/index.html` (aprovado; uma direção, estilo atual do notch; medidas em px = pt)

Como o comando de teste cita o arquivo que falhou: `tools/check.sh` imprime `<nome>  FALHOU` com a saída inteira e termina com saída 1. Todo gate novo deste plano entra por `swift_teste tools/<arquivo>.swift …` (`tools/check.sh:66`), que tira o nome do gate do próprio arquivo; o `precondition` do Swift também imprime o caminho do arquivo.

Prova visual das etapas com tela: `./tools/snapshot.sh` gera `Snapshots/ask-*.png`, comparados ao quadro indicado do mockup. O snapshot não faz parte do `check.sh`; o que entra no `check.sh` por tela é o typecheck das fontes (`notchfontescheck`) e os modelos puros.

Avisos que valem para todas as etapas:

- Arquivo `.swift` novo em `Knobler/` pede `xcodegen generate` e uma linha em `tools/notchview-fontes.txt` (lista manual lida por `snapshot.sh`, `cortecheck.sh` e `notchfontescheck.sh`). Nunca edite `Knobler.xcodeproj` à mão.
- Rodar um `Knobler.app` de build **encerra** o instalado em `/Applications`. Reabra-o depois de qualquer teste ao vivo.
- Comentários e strings em pt-BR. Log com `os.Logger`, nunca `NSLog`. Simplificação deliberada leva `// ponytail:`.
- O contrato de `/ask` não muda: `AskModels.swift` e `docs/local-api.md` ficam como estão.
- Estilo do notch (`DESIGN.md`): fundo preto puro, só branco em opacidades, SF Pro, raio 8. Nenhuma cor de destaque, nenhum vidro.

---

### Etapa 1

- **Título:** Reducer do Ask com abas, próxima pendente, destaque e escolha por número.
- **Tela:** não.
- **Arquivos:** mudar `Knobler/AskFeature.swift`; mudar `tools/askcheck.swift`.
- **O que prova a etapa:** (casos novos em `tools/askcheck.swift`, cada um uma `static func` chamada em `main()`, com os helpers `send`, `check`, `request`, `question`, `option` de `tools/askcheck.swift:37-75`)
  - Três perguntas simples: responder a 1ª leva à página 1 (o teste antigo `testPagedSubmissionPreservesPreviousAnswers` continua passando); `goTo(page: 0)` volta, sem efeito, com `answers` intacto.
  - Voltar a uma simples já respondida: `highlight` aponta a opção respondida; `selected` vazio; `text` vazio.
  - Voltar a uma múltipla já respondida com `["A","B"]`: `selected == ["A","B"]`.
  - Voltar a uma respondida com texto livre: `text` traz o texto de volta.
  - Responder de novo substitui a resposta anterior daquela pergunta.
  - Próxima pendente com volta ao início: três perguntas, responde a 1ª, `goTo(2)`, responde a 3ª: vai para a página 1 (a única pendente), sem resolver. Responde a 2ª: efeito `.resolve` com as três respostas.
  - Fora de ordem: com 2ª e 3ª respondidas e a 1ª pendente, responder a 1ª resolve na hora.
  - Duas perguntas com o **mesmo texto**: responder uma resolve a rodada (a conta é por texto de pergunta, não por número de respostas).
  - `goTo` fora do intervalo (−1, `count`) e `goTo` sem pergunta ativa são no-op com estado idêntico.
  - Seleção múltipla não confirmada e texto não enviado somem ao trocar de aba para uma pergunta sem resposta.
  - `moveHighlight(by: 1)` a partir de `nil` vai para 0; `by: -1` a partir de `nil` vai para a última; nas pontas não passa (fica em 0 e em `count-1`).
  - `setHighlight(5)` com 2 opções é no-op; `setHighlight(nil)` limpa.
  - `choose(index:)`: fora do intervalo é no-op sem efeito; em pergunta simples equivale a `submit(labels: [rótulo])`; em múltipla marca/desmarca e deixa `highlight` no índice.
  - Destaque na troca de página: se havia destaque antes de responder, a página seguinte nasce com `highlight == 0`; se não havia (`nil`), nasce `nil`.
  - Pergunta nova promovida da fila nasce com `page 0`, `highlight nil`, `selected` e `text` vazios.
- **Como fazer:**
  - Em `AskState` (`Knobler/AskFeature.swift:8-19`) acrescentar `var highlight: Int?`. Em `resetInputs` (`:169-174`) zerar também `highlight`.
  - Em `AskAction` (`:21-32`) acrescentar `case goTo(page: Int)`, `case moveHighlight(by: Int)`, `case setHighlight(Int?)`, `case choose(index: Int)`.
  - Criar a função privada `entrar(pagina:in:mantendoDestaque:)`: grava `state.page`; lê `answers[pergunta.question]`; se houver resposta, `selected = pergunta.multiSelect ? Set(labels) : []`, `text = resposta.text ?? ""`, e `highlight` = índice da opção respondida quando a pergunta é simples e a resposta tem um rótulo; sem resposta, `selected` e `text` vazios e `highlight = mantendoDestaque ? 0 : nil`. Quando há resposta sem índice (múltipla ou texto), `highlight = mantendoDestaque ? 0 : nil`.
  - `goTo(page:)`: guarda `active` e intervalo; chama `entrar(pagina:mantendoDestaque: state.highlight != nil)`; devolve `[]`.
  - No `submit` (`:73-111`), trocar o bloco `if state.page + 1 < active.questions.count { state.page += 1; return [] }` por: para `passo` de 1 até `count`, `p = (page + passo) % count`; a primeira página cujo `questions[p].question` não está em `answers` recebe `entrar(pagina: p, mantendoDestaque: tinhaDestaque)` e a função devolve `[]`. `tinhaDestaque` é lido **antes** de limpar os campos. Sem página pendente, o código existente de resolver (`:108-111`) segue igual.
  - `moveHighlight(by:)`: sem pergunta atual é no-op; `nil` vira `by > 0 ? 0 : count - 1`; senão `min(max(atual + by, 0), count - 1)`.
  - `setHighlight`: aceita `nil` ou índice dentro de `options.indices`.
  - `choose(index:)`: valida o índice; pergunta simples chama o mesmo caminho do `submit` com `[label]` (extraia o corpo do `submit` para uma função privada para não duplicar); múltipla faz o mesmo que `toggle` e grava `highlight = index`.

---

### Etapa 2

- **Título:** Modelo puro do card: rótulo recomendado, resumo da resposta, legenda de teclas e tamanho do preview.
- **Tela:** não.
- **Arquivos:** criar `Knobler/AskCard/AskCardModelo.swift`; criar `tools/askcardmodelocheck.swift`; mudar `tools/check.sh` (linha `swift_teste tools/askcardmodelocheck.swift Knobler/AskModels.swift Knobler/AskCard/AskCardModelo.swift` logo depois do `askcheck`, `tools/check.sh:71`); mudar `tools/notchview-fontes.txt` (acrescentar `Knobler/AskCard/AskCardModelo.swift` depois da linha 31).
- **O que prova a etapa:**
  - Rótulo: `"Atalho global (Recomendado)"` vira texto `"Atalho global"` e recomendada; `"X (Recommended)"` idem; maiúsculas diferentes e espaço sobrando no fim também; `"Recomendado para todos"` e `"(Recomendado) X"` (sufixo fora do fim) ficam inteiros e não recomendados; rótulo vazio devolve vazio.
  - Resumo: sem resposta devolve `""`; texto livre devolve o texto sem espaços nas pontas; um rótulo devolve o rótulo sem o sufixo de recomendado; três rótulos devolvem `"3 marcadas"`.
  - Legenda sem teclado e com atalho `"⌃⌥K"`: um item, teclas `["⌃⌥K"]`, texto `"responder pelo teclado"`. Sem teclado e atalho `nil`: lista vazia.
  - Legenda com teclado, pergunta simples, uma pergunta só: `↑ ↓ escolher`, `⏎ responder`, `esc soltar`. Múltipla: `↑ ↓ escolher`, `espaço marcar`, `⏎ confirmar`, `esc soltar`. Com mais de uma pergunta entra `← → pergunta` antes de `esc soltar`.
  - Legenda no campo de texto: `⏎ enviar`, `esc voltar à lista`, e um item sem tecla `"⌥ direita dita"`.
  - Preview, com avanço 6,6 e linha 13 a 11 pt, largura máxima 836 e altura máxima 600: lista vazia devolve `nil`; preview de 44 colunas × 9 linhas fica **ao lado**, letra 11, card com 236 + 10 + 44×6,6 + 20 + 40 de largura (arredondado para cima), quadro com 44×6,6 + 20 de largura; o quadro usa o **maior** preview (dois previews de 44×9 e 20×3 dão o mesmo quadro que só o de 44×9); preview de 10 colunas não deixa o card abaixo de 460; preview de 102 colunas não cabe ao lado, vai **embaixo**, letra 11, card com 102×6,6 + 20 + 40; preview de 150 colunas vai embaixo com letra menor que 11 e maior ou igual a 8, card com 836, texto cabendo exato; preview de 300 colunas fica com letra 8 e `rola == true`; preview de 80 linhas com altura máxima 300 encolhe a letra até caber na altura ou até 8 (e então `rola == true`).
- **Como fazer:**
  - Arquivo só com `Foundation` e `CoreGraphics` (sem SwiftUI nem AppKit), para compilar no gate ao lado de `AskModels.swift`.
  - `enum AskRotulo { static func separar(_ label: String) -> (texto: String, recomendada: Bool) }`: tira espaços das pontas; se termina (sem diferenciar maiúsculas) em `(Recomendado)` ou `(Recommended)`, devolve o que vem antes, sem espaços, e `true`.
  - `enum AskResumo { static func texto(_ answer: AskAnswer?) -> String }` (`AskAnswer` em `Knobler/AskModels.swift:36`).
  - `struct AskLegendaItem: Equatable { var teclas: [String]; var texto: String }` e `enum AskLegenda { static func itens(teclado: Bool, campo: Bool, multipla: Bool, abas: Bool, atalho: String?) -> [AskLegendaItem] }`. `campo == true` vence os outros.
  - `struct AskPreviewLayout: Equatable { var lado: Bool; var fonte: CGFloat; var larguraDoCard: CGFloat; var quadro: CGSize; var rola: Bool }` com `static func calcular(previews: [String], avanco: CGFloat, linha: CGFloat, larguraMaxima: CGFloat, alturaMaxima: CGFloat) -> AskPreviewLayout?`. `avanco` e `linha` são a largura de um caractere e a altura de uma linha da fonte monoespaçada a 11 pt; escalam linearmente com a letra. Constantes nomeadas no próprio tipo: `larguraMinima 460`, `margem 40` (os 20 de cada lado que o `NotchView` tira), `lista 236`, `vao 10`, `dentro 20` (padding horizontal do quadro), `vertical 16` (padding vertical), `entreLinhas 2`, `base 11`, `piso 8`.
    - `colunas` = maior número de caracteres numa linha entre todos os previews; `linhas` = maior número de linhas. `// ponytail:` conta `Character`, então caractere de largura dupla (CJK, emoji) sai mais largo que o previsto; o piso com rolagem cobre.
    - `texto = colunas × avanco`. Cabe ao lado se `lista + vao + texto + dentro + margem ≤ larguraMaxima`.
    - Letra: ao lado, 11. Embaixo, `11 × (larguraMaxima − margem − dentro) / texto`, limitada entre 8 e 11.
    - Altura do quadro = `linhas × (linha × fonte/11 + entreLinhas) + vertical`. Se passa de `alturaMaxima`, a letra encolhe na proporção que faz caber, limitada a 8, e a altura é recalculada.
    - `rola` = com a letra final, a largura ou a altura ainda não cabem.
    - `larguraDoCard`: ao lado, `max(460, lista + vao + larguraDoQuadro + margem)`; embaixo, `min(larguraMaxima, max(460, larguraDoQuadro + margem))`; onde `larguraDoQuadro = colunas × avanco × fonte/11 + dentro`. Arredonde para cima.
  - Harness `tools/askcardmodelocheck.swift`: `@main enum`, `precondition` com mensagem, termina com `print("askcardmodelocheck: OK")`. Não é `main.swift`, então compila com `-parse-as-library` (o `swift_check` decide sozinho, `tools/check.sh:55-63`).
  - Rode `xcodegen generate` depois de criar a pasta `Knobler/AskCard/` (o `project.yml:15-17` pega a subpasta sozinho).

---

### Etapa 3

- **Título:** Card redesenhado: três faixas, abas, opções com selo e estados, botão Confirmar com contagem, campo e legenda em repouso.
- **Tela:** sim — quadros "Uma pergunta: em repouso", "Múltipla escolha" e "Várias perguntas: abas" do mockup.
- **Arquivos:** criar `Knobler/AskCard/AskCardView.swift`, `Knobler/AskCard/AskAbasView.swift`, `Knobler/AskCard/AskOpcaoView.swift`, `Knobler/AskCard/AskRodapeView.swift`; apagar `Knobler/Ask.swift` (o conteúdo migra); mudar `Knobler/NotchView.swift` (`:81`, `:325-347`, `:610-617`), `Knobler/NotchViewModel.swift`, `Knobler/KnoblerApp.swift` (onde a `NotchViewModel` de cada tela é montada, perto de `:1265`), `tools/main.swift` (`:1246-1303` e `:1521-1523`), `tools/notchview-fontes.txt` (trocar `Knobler/Ask.swift` pelos quatro arquivos novos).
- **O que prova a etapa:**
  - `./tools/check.sh` verde (o `notchfontescheck` faz o typecheck das fontes do snapshot; o `askcheck` e o `askcardmodelocheck` seguem verdes).
  - `./tools/snapshot.sh` gera, e cada PNG bate com o quadro do mockup:
    - `ask-simple.png` ("Em repouso"): chip do cabeçalho à esquerda, `◐ origem` e ✕ à direita; pergunta em linha própria, inteira, maior que o resto; três opções com selo `1` `2` `3`, a primeira com o selo "Recomendada" e **sem** o texto "(Recomendado)" no rótulo; todas as descrições inteiras; campo "Outra resposta…" **desenhado** (sem a faixa amarela de hoje); legenda `⌃⌥K responder pelo teclado`.
    - `ask-multi-vazio.png` ("Nada marcado"): caixas vazias na ponta direita, botão "Confirmar" apagado.
    - `ask-multiselect.png` ("Duas marcadas"): duas linhas com fundo mais claro e caixa preenchida com visto, botão "Confirmar 2" aceso.
    - `ask-paged.png` ("Segunda pergunta, primeira já respondida"): três abas — a primeira com visto, rótulo e a resposta resumida truncada; a segunda preenchida; a terceira apagada com ponto vazado.
    - `ask-revisita.png` ("De volta à primeira"): a opção respondida com fundo mais claro e visto à direita; a segunda aba mostra "2 marcadas".
  - Nenhum PNG `ask-*` tem área preta sólida no lugar do conteúdo nem a faixa amarela de "proibido".
  - Com uma pergunta só não aparece aba; com `source` vazio não aparece `◐`.
  - Trocar de aba não dispara a animação de card inteiro: `contentID` não contém mais a página.
- **Como fazer:**
  - Ponto de partida: o card atual é `Knobler/Ask.swift:16-214` (`AskCardView`) e a chave de medida `AlturaDoAskKey` (`:221-226`). Leve tudo para `Knobler/AskCard/AskCardView.swift` e quebre em peças que recebem valores prontos: `AskAbasView` (perguntas, respostas, página, ação de ir), `AskOpcaoView` (uma linha), `AskRodapeView` (campo + legenda). A chave `AlturaDoAskKey` vai junto, com `reduce` trocado para `value = nextValue()` (o "maior valor visto" impede o card de encolher).
  - Constantes de estilo num `enum AskEstilo` em `AskCardView.swift`, usadas por todas as peças: fundo da linha `0.06`, em destaque `0.15`, marcada `0.25`, campo e selo `0.08`; tinta secundária `0.62`, apagada `0.5`, desabilitada `0.3`; anel `0.5`; raio 8, raio do selo 4. Letras: pergunta 15 semibold, rótulo 12 semibold, descrição 11 regular, selo/aba/legenda/origem 10.
  - Faixa de topo (altura 22, espaçamento 8): com mais de uma pergunta, `AskAbasView`; com uma, o chip do `header` (cápsula `0.15`, 10 semibold; some se o header for vazio). À direita `◐ source` (10 medium, `0.5`, uma linha) e o ✕ (círculo de 18, fundo `0.15`, `.help("Responder no terminal")`, envia `.cancelActive`).
  - Aba: cápsula de altura 22, padding horizontal 8, 10 semibold, espaço 4 entre abas. Atual: fundo `0.15`, texto branco. Respondida e não atual: ícone de visto, `header`, e o `AskResumo.texto` em peso regular, uma linha, largura máxima 92, truncado. Pendente: ponto vazado de 5 pt e texto `0.5`. Aba atual já respondida mostra o visto em vez do ponto cheio. Se o `header` for vazio, use o número da pergunta. Clique envia `.goTo(page:)`.
  - Pergunta: `Text` 15 semibold, sem `lineLimit`, `.fixedSize(horizontal: false, vertical: true)`.
  - Linha de opção (`AskOpcaoView`): `HStack(alignment: .top, spacing: 8)` com selo do número (quadrado mínimo 16×16, raio 4, fundo `0.08`, texto `0.62`, dígitos tabulares; índices de 9 em diante sem selo, com o espaço reservado), coluna com rótulo (via `AskRotulo.separar`; se recomendada, selo em cápsula de altura 15 com contorno de 1 pt `0.5`, texto "Recomendada" 10 semibold `0.85`) e descrição **sempre inteira** (11 regular, `0.62`; na linha marcada, `0.85`), e a ponta direita de 16: visto na pergunta simples respondida; na múltipla, caixa de 13 com raio 4 e contorno 1,5 `0.5`, e marcada vira preenchida de branco com visto preto. Padding 8 horizontal e 6 vertical, raio 8. Fundo: `0.06` normal, `0.15` em destaque, `0.25` marcada. A linha recebe também `teclado: Bool` (nesta etapa sempre `false`; com `true`, o destaque ganha contorno interno de 1 pt `0.5` e o selo passa a fundo `0.15` com texto branco).
  - Destaque: sai do estado, não de `@State`. Apague o `hovered` (`Ask.swift:20`) e o `.lineLimit(hovered == … ? nil : 2)` (`:144`). `.onHover` da linha envia `.setHighlight(indice)` ao entrar e, ao sair, `.setHighlight(nil)` se o destaque ainda for aquela linha. Clique: múltipla envia `.toggle(label:)`; simples envia `.choose(index:)`.
  - Botão Confirmar (só na múltipla): altura 30, raio 8, "Confirmar" ou "Confirmar N" (N = marcadas) seguido do selo `⏎`; fundo `0.25` aceso, `0.08` e texto `0.3` apagado; envia `.submit(labels:)` com os rótulos **na ordem das opções** (hoje `Array(Set)` sai em ordem qualquer, `Ask.swift:107`).
  - Campo (`AskRodapeView`): altura 30, fundo `0.08`, raio 8, placeholder `"Outra resposta…"`. O indicador de ditado (`Ask.swift:180-185`) fica dentro do campo, à esquerda. O `onSubmit` segue como em `Ask.swift:190-195`.
  - Legenda: `AskLegenda.itens(teclado: false, campo: textFocused, multipla:, abas:, atalho: vm.glifoDoAtalho())`, itens lado a lado com espaço 8, 10 pt, texto `0.62`; cada tecla no mesmo selo da opção.
  - Atalho exibido: acrescente em `NotchViewModel` `var glifoDoAtalho: () -> String? = { nil }`. Em `KnoblerApp.swift`, ao criar a view model de cada tela, atribua `{ KeyboardShortcuts.getShortcut(for: .abrirNotch)?.shortcutGlyph }` (`Vendor/MonitorControl/KeyboardShortcuts.swift:194, 791-795`; o nome `.abrirNotch` está em `Knobler/SettingsView.swift:16-18`). É um fecho lido a cada desenho porque a biblioteca não avisa quando o atalho muda. No harness (`tools/main.swift`), atribua `{ "⌃⌥K" }`.
  - Troca de aba: o bloco pergunta + corpo + rodapé ganha `.id(page)` e transição de opacidade com deslocamento horizontal de 8 pt, `easeOut` de 0,22 s. Com `@Environment(\.accessibilityReduceMotion)` ligado, só opacidade em 0,15 s.
  - `Knobler/NotchView.swift:81`: tire `/\(askStore.state.page)` do `contentID`. `:610-617` (`questionCard`) segue chamando `AskCardView`. `:340-341`: atualize a estimativa de primeiro frame para 58 por opção.
  - Harness: em `tools/main.swift:1521-1522`, acrescente `|| scenario.name.hasPrefix("ask-")` à condição que manda o cenário para a janela real (é ali que campo de texto e rolagem desenham; hoje os `ask-*` vão para o `ImageRenderer` e saem com "proibido"). Reescreva os cenários `ask-simple`, `ask-multiselect` e `ask-paged` (`:1246-1303`) com os dados do mockup (constantes `RODADA` no `<script>` de `docs/vesta/mockups/2026-11-18-card-pergunta/index.html`) e crie `ask-multi-vazio` e `ask-revisita`, sempre por ações reais do reducer (`.enqueue`, `.toggle`, `.submit`, `.goTo`). Ajuste `frameHeight` para o card caber inteiro.
  - Rode `xcodegen generate` (arquivos criados e um apagado).

---

### Etapa 4

- **Título:** Preview sempre inteiro: o card alarga, depois o preview desce, depois a letra encolhe.
- **Tela:** sim — quadros "Opções com preview: sempre inteiro" e "Preview largo demais para ficar ao lado" do mockup.
- **Arquivos:** criar `Knobler/AskCard/AskPreviewView.swift`; mudar `Knobler/AskCard/AskCardView.swift`, `Knobler/NotchView.swift` (`:325-347`), `tools/main.swift` (cenário `ask-preview`, `:1273-1287`, e um novo), `tools/notchview-fontes.txt`.
- **O que prova a etapa:**
  - `./tools/check.sh` verde.
  - `Snapshots/ask-preview.png`: preview de 44 colunas × 9 linhas **ao lado** das opções, inteiro (a moldura de texto fecha nos quatro cantos, nenhuma linha cortada), letra visivelmente maior que a de hoje; o preview mostrado é o da opção em destaque.
  - `Snapshots/ask-preview-largo.png`: tabela de ~100 colunas **embaixo** das opções, na largura toda do card, inteira.
  - Pergunta em que só algumas opções têm preview: com o destaque numa opção sem preview, o quadro fica vazio e do mesmo tamanho (o card não muda de largura nem de altura).
  - Sem destaque nenhum, o quadro mostra o primeiro preview da pergunta.
- **Como fazer:**
  - Hoje: preview em `ScrollView` de 9 pt numa coluna fixa (`Ask.swift:165-176`), lista com 250 de largura (`:47`) e card com 540 fixos (`Knobler/NotchView.swift:346`).
  - Uma função única, usada pelo card e pelo `NotchView`, para os dois nunca divergirem: `AskCardView.layoutDoPreview(question:disponivel:topo:) -> AskPreviewLayout?`, que chama `AskPreviewLayout.calcular` (etapa 2, `Knobler/AskCard/AskCardModelo.swift`) com `previews` = os `preview` não nulos das opções, `avanco` e `linha` medidos de `NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)` (`maximumAdvancement.width`; `ascender − descender + leading`), `larguraMaxima = disponivel.width − 64` (o mesmo limite de `Knobler/NotchPresentation.swift:196`) e `alturaMaxima = max(120, disponivel.height − 24 − topo − 150)` (150 = topo, pergunta, campo e legenda).
  - `AskPreviewView`: `Text` em `.system(size: layout.fonte, design: .monospaced)`, `.lineSpacing(2)`, `.fixedSize()`, cor `0.85`, dentro de um quadro de `layout.quadro` alinhado em cima à esquerda, padding 10 horizontal e 8 vertical, fundo `0.06`, raio 8. Só com `layout.rola == true` o texto vai dentro de um `ScrollView([.vertical, .horizontal])`.
  - `AskCardView`: com layout `lado`, `HStack(alignment: .top, spacing: 10)` com a lista em largura 236 e o preview; sem `lado`, `VStack(spacing: 8)` com a lista na largura toda e o preview embaixo. Texto do preview: o da opção `state.highlight`; sem destaque, o primeiro não nulo; opção em destaque sem preview, texto vazio.
  - `Knobler/NotchView.swift:346`: largura = `layout?.larguraDoCard ?? 460`. A altura continua vindo da medida do card (`:345`); só a estimativa de primeiro frame soma `layout.quadro.height` quando o preview vai embaixo.
  - Cenários: `ask-preview` com três opções e previews de 44 colunas (função `ABA` do `<script>` do mockup) e destaque na segunda (`.setHighlight(1)`); `ask-preview-largo` com a tabela `LARGA` do mockup. Os dois precisam de `frameWidth` 900.

---

### Etapa 5

- **Título:** Teto de 60% da tela com rolagem só na lista de opções.
- **Tela:** sim — quadro "Texto longo" do mockup.
- **Arquivos:** mudar `Knobler/AskCard/AskCardView.swift`, `Knobler/NotchView.swift` (`:610-617`), `Knobler/KnoblerApp.swift` (`handleScroll`, `:1037` e `:1083-1106`), `tools/main.swift` (cenário novo).
- **O que prova a etapa:**
  - `./tools/check.sh` verde.
  - `tools/askcardmodelocheck.swift`, `AskTeto`: `doCard(disponivel: 900, topo: 38)` dá 484; lista de 300 num card de 420 com teto 484 não rola (`nil`); lista natural de 500, desenhada com 500 num card medido em 650 e teto 484, rola com área de 334; a mesma lista já rolando (desenhada com 334, card medido em 484) continua com 334 (a conta é estável, não oscila); sobra maior que o teto (card 700, lista atual 100, teto 484) devolve o mínimo 96 para uma lista natural de 300; sem medida (`natural 0` ou `card 0`) devolve `nil`.
  - `Snapshots/ask-longo.png` (quatro opções com descrições de três linhas, numa tela baixa): topo, pergunta inteira, campo e legenda visíveis e inteiros; a lista cortada embaixo com a rolagem; o card não passa de 60% da altura disponível.
  - Preview embaixo e alto: com um preview de 16 linhas e 100 colunas (largo demais para ficar ao lado), numa tela de 520 de altura, o preview aparece inteiro (a letra encolhe se preciso) e quem cede espaço é a lista, que rola; o card não passa da tela.
  - `Snapshots/ask-simple.png` e `ask-multiselect.png` saem idênticos aos da etapa 3 (com espaço sobrando não existe área rolável).
  - Trocar de uma aba alta para uma aba baixa encolhe o card (a medida aceita diminuir).
  - Ao vivo, com `POST /ask` da pergunta longa: rolar com dois dedos sobre a lista move a lista; deslizar de lado sobre o card **não** troca de música. Rolagem só se testa com evento real na fila do sistema e a janela na tela — o roteiro está em `~/.claude/projects/-Users-luccassilveira-Desktop-Projetos-knobler/memory/testar-rolagem-de-verdade.md`. Reabra o Knobler de `/Applications` depois.
- **Como fazer:**
  - A conta do teto é pura e mora em `Knobler/AskCard/AskCardModelo.swift`, com casos no `tools/askcardmodelocheck.swift`: `enum AskTeto { static let minimoDaLista: CGFloat = 96; static func doCard(disponivel: CGFloat, topo: CGFloat) -> CGFloat; static func daLista(natural: CGFloat, card: CGFloat, listaAtual: CGFloat, tetoDoCard: CGFloat) -> CGFloat? }`. `doCard` = `0.6 × disponivel − (topo + 18)`. `daLista` devolve `nil` quando a lista não precisa rolar e, quando precisa, a altura da área rolável: com `natural ≤ 0` ou `card ≤ 0` (ainda sem medida) é `nil`; `sobra = card − listaAtual`; `teto = max(96, tetoDoCard − sobra)`; `natural > teto` devolve `teto`, senão `nil`.
  - `AskCardView` ganha o parâmetro `alturaMaxima: CGFloat`. Em `Knobler/NotchView.swift:612`, passe `0.6 * vm.availableSize.height − (topInset + 18)` (18 são os paddings de `:614-615`).
  - A lista (opções + botão Confirmar) mede a própria altura natural por um `GeometryReader` no `.background` do conteúdo, com uma `PreferenceKey` nova (`AlturaDaListaDoAskKey`); o conteúdo de uma área rolável é sempre desenhado na altura natural, então a medida vale com ou sem rolagem. Guarde em `@State listaNatural`.
  - O que não é lista (topo, pergunta, preview embaixo, campo, legenda) = `alturaDoCard − alturaAtualDaLista`, onde `alturaDoCard` é a medida que o card já faz (`AlturaDoAskKey`). Teto da lista = `max(96, alturaMaxima − essaSobra)`.
  - Com `listaNatural > tetoDaLista`: a lista vai dentro de `ScrollView(.vertical)` com `.frame(height: tetoDaLista)`. Caso contrário, a lista é desenhada direto, sem `ScrollView` e sem `frame`. Antes da primeira medida (`listaNatural == 0`), desenhe direto.
  - Pendência da etapa 4: em `AskCardView.layoutDoPreview`, quando o preview vai embaixo (`lado == false`), a `alturaMaxima` passada ao cálculo desconta também o mínimo da lista (96): `max(120, disponivel.height − 24 − topo − 150 − 96)`. Assim o preview encolhe a letra antes de empurrar o card para fora da tela, e a lista rola no espaço que sobra. Ao lado, a conta fica como está.
  - Não use `maxHeight: .infinity` em nada do card: é o que travava a auto-medição (comentário em `Ask.swift:172-174`).
  - `handleScroll` (`Knobler/KnoblerApp.swift:1037` trata o card como fechado quando `vm.mode != .music`): no ramo do gesto horizontal (`:1083-1106`), saia cedo quando `vm.mode == .question`. A rolagem vertical já é repassada ao conteúdo.
  - Cenário `ask-longo`: a pergunta `LONGA` do `<script>` do mockup, com a altura disponível da view model do cenário fixada em 520 (veja como o harness preenche `vm.availableSize` e sobrescreva dentro do `configure` do cenário).

---

### Etapa 6

- **Título:** Teclado no card: posse própria pelo atalho global, teclas pelo vigia do app, Esc solta em vez de cancelar.
- **Tela:** sim — quadros "Com o teclado no card" e "Outra resposta" do mockup, e o comportamento do quadro "Experimente".
- **Arquivos:** criar `Knobler/AskCard/AskTeclado.swift`, `tools/asktecladocheck.swift`; mudar `Knobler/NotchViewModel.swift` (`:644-648`), `Knobler/KnoblerApp.swift` (`:997-1014`, `:1271-1276`, `:1289-1292`, e onde as perguntas chegam, `:903`), `Knobler/AskCard/AskCardView.swift`, `Knobler/AskCard/AskRodapeView.swift`, `Knobler/LinkPreviewView.swift` (`:39`, comentário), `tools/check.sh` (`swift_teste tools/asktecladocheck.swift Knobler/AskModels.swift Knobler/AskFeature.swift Knobler/AskCard/AskTeclado.swift` depois do `askcardmodelocheck`), `tools/notchview-fontes.txt`, `tools/main.swift`.
- **O que prova a etapa:**
  - `tools/asktecladocheck.swift` (função pura `AskTeclado.comando`), com uma rodada de 3 perguntas (simples de 3 opções, múltipla de 4, simples de 3):
    - `↓` e `↑` viram `moveHighlight(by: 1)` e `(by: -1)`, também com repetição de tecla.
    - `"2"` vira `choose(index: 1)`; `"7"` com 3 opções não vira nada; número com repetição de tecla não vira nada; `"2"` vindo do teclado numérico (mesmo caractere, outro código de tecla) vira `choose(index: 1)`.
    - Enter em pergunta simples com destaque 1 vira `choose(index: 1)`; sem destaque, `choose(index: 0)`; Enter do teclado numérico idem; Enter com repetição não vira nada.
    - Enter em múltipla sem marcadas não vira nada; com "C" e "A" marcadas vira `submit(labels: ["A", "C"], text: nil)` (ordem das opções).
    - Espaço em múltipla vira `choose(index: destaque ou 0)`; espaço em simples não vira nada.
    - `→` na página 0 vira `goTo(page: 1)`; `→` na última e `←` na primeira não viram nada; com uma pergunta só, nenhuma das duas vira nada.
    - Tab vira "focar o campo"; Esc vira "soltar o teclado"; `⌘.` vira "cancelar" na lista **e** no campo.
    - No campo de texto: Esc e ⇧Tab viram "voltar à lista"; letras, números, Enter, setas e Tab simples não viram nada (o campo trata).
    - Qualquer tecla com ⌘, ⌃ ou ⌥ (fora o `⌘.`) não vira nada.
    - Sem pergunta ativa, nada vira nada.
  - `./tools/check.sh` verde.
  - `Snapshots/ask-teclado.png` ("Com o teclado no card"): segunda opção com contorno, selos dos números acesos, selo `⇥` no fim do campo, legenda `↑ ↓ escolher · ⏎ responder · esc soltar`. `Snapshots/ask-texto.png` ("Escrevendo"): legenda `⏎ enviar · esc voltar à lista · ⌥ direita dita`.
  - Ao vivo, com o build rodando e três perguntas publicadas por `POST /ask` (formato em `docs/local-api.md`; simples, múltipla, com preview), teclas postadas como eventos de sistema (`CGEvent` em `.cghidEventTap`; `keystroke` do AppleScript **não** serve, vai para o app da frente):
    1. A pergunta aparece e o painel **não** é a janela-chave: uma tecla digitada vai para o app da frente.
    2. `⌃⌥K` dá o teclado; `1` responde a primeira e abre a segunda; `1`, `3`, Enter confirmam; `←` volta à primeira com a resposta marcada; `2` troca a resposta; a terceira é respondida com Enter e o card some. `GET /ask/<id>` devolve as três respostas, a primeira já trocada.
    3. Outra rodada: `⌃⌥K`, Esc — o card continua na tela e a tecla seguinte vai para o app da frente. `⌃⌥K` duas vezes faz o mesmo.
    4. `⌃⌥K`, Tab, texto, Enter: a resposta é o texto. Tab, Esc: o cursor sai do campo e as setas voltam a mover o destaque.
    5. `⌃⌥K`, `⌘.`: `GET /ask/<id>` devolve `{"cancelled":true}`.
    6. Com o card de música aberto por `⌃⌥K` e uma pergunta chegando: o painel larga a chave; `←` `→` não trocam a seção de música por trás; depois de respondida a pergunta por clique, o card de música **não** abre sozinho.
    7. `⌃⌥K` com o card de aprovação do Codex na tela (sem pergunta do Claude) se comporta como hoje.
    Reabra o Knobler de `/Applications` ao terminar.
- **Como fazer:**
  - Por que estado próprio: o `abertoPorTeclado` não serve. `alternarPeloTeclado` (`Knobler/NotchViewModel.swift:644-648`) chama `setExpandedDirect(true)`, que com pergunta na tela não muda a apresentação (o painel não vira chave) e deixa o card de música armado por trás; tirar o mouse do card zera a flag (`Knobler/NotchView.swift:290` → `NotchViewModel.swift:670-671`); e o vigia de teclas (`Knobler/KnoblerApp.swift:1001-1014`) engole ← → Tab e Esc quando ela está ligada.
  - `AskTeclado.swift` (só `Foundation`): `struct AskTecla: Equatable { var codigo: Int; var caracteres: String; var shift = false; var command = false; var outros = false; var repeticao = false }` (`outros` = ⌃ ou ⌥); `enum AskComando: Equatable { case acao(AskAction); case focarCampo; case voltarALista; case soltarTeclado; case cancelar }`; `enum AskTeclado { static func comando(_ tecla: AskTecla, campo: Bool, estado: AskState) -> AskComando? }`. Códigos de tecla como constantes nomeadas no arquivo: Esc 53, Return 36, Enter numérico 76, Tab 48, ← 123, → 124, ↓ 125, ↑ 126. Números e espaço são lidos de `caracteres`, nunca do código (layout AZERTY e teclado numérico). Regras exatamente como nos casos de teste acima.
  - `NotchViewModel`: `@Published var tecladoNaPergunta = false`, `@Published var campoDaPerguntaFocado = false`, `var perguntaDoClaudeAtiva: () -> Bool = { false }`, `var aoMudarTecladoDaPergunta: ((Bool) -> Void)?`, e `func darTecladoAPergunta(_ liga: Bool)` que grava a flag e chama o callback só quando o valor muda. `alternarPeloTeclado` ganha a primeira linha: `if mode == .question, perguntaDoClaudeAtiva() { darTecladoAPergunta(!tecladoNaPergunta); return }` — antes de tocar em `expanded`.
  - `KnoblerApp.swift`, onde cada tela é montada (perto de `:1256-1276`): `viewModel.perguntaDoClaudeAtiva = { askStore.state.active != nil }` (só a pergunta do Claude; o card do Codex divide o mesmo modo, `:1256-1258`, e fica de fora). `viewModel.aoMudarTecladoDaPergunta = { liga in … }`: ligando, `panel.allowsKeyboard = true`, `panel.makeKey()` e, se `askStore.state.highlight == nil`, `askStore.send(.setHighlight(0))`; desligando, `askStore.send(.setHighlight(nil))`, `viewModel.campoDaPerguntaFocado = false` e, se o painel é a janela-chave, `panel.resignKey()` (é o caminho que o app já usa em `:1178` e `:1273`; como o painel nunca ativa o app, o app da frente volta a receber as teclas sozinho).
  - Herança do teclado: em `:1275`, o `makeKey` automático passa a exigir `viewModel?.mode != .question`. Quando uma pergunta do Claude chega (`.enqueue` em `:903`), todo painel que for janela-chave e não estiver em `protegeEdicao` larga a chave.
  - Posse cai sozinha: quando `askStore.state.active?.id` muda (respondida, cancelada, expirada, ou a próxima da fila foi promovida), chame `darTecladoAPergunta(false)` em todas as telas. `aoPerderTeclado` (`:1289-1292`) também chama `darTecladoAPergunta(false)` — clicar em outro app solta.
  - Vigia de teclas (`:1001-1014`): um ramo novo **antes** do `guard` existente. Condição: a janela-chave é uma `NotchWindow`, a view model dela está com `tecladoNaPergunta` e `mode == .question`, e há pergunta do Claude ativa. Monte a `AskTecla` do `NSEvent` (`keyCode`, `charactersIgnoringModifiers`, flags, `isARepeat`), com `campo = window.firstResponder is NSText`, e chame `AskTeclado.comando`. Comando → execute e devolva `nil`: `.acao` vai para `askStore.send`; `.focarCampo` liga `vm.campoDaPerguntaFocado`; `.voltarALista` desliga; `.soltarTeclado` chama `vm.darTecladoAPergunta(false)`; `.cancelar` envia `.cancelActive`. Sem comando: no campo, devolva o evento; na lista, devolva o evento só se houver ⌘ (atalhos do sistema passam), senão `nil` (letra solta não apita). No `guard` antigo, acrescente `vm.mode != .question`.
  - `AskCardView`: `onChange(of: vm.campoDaPerguntaFocado)` grava no `@FocusState` do campo; `onChange` do `@FocusState` grava de volta em `vm.campoDaPerguntaFocado` e, ao ganhar foco (clique no campo), chama `vm.darTecladoAPergunta(true)`. As peças recebem `teclado: vm.tecladoNaPergunta`: contorno do destaque, selos acesos, selo `⇥` no fim do campo quando há teclado e o cursor não está nele, legenda com `teclado: true`.
  - Apague o `.onExitCommand { askStore.send(.cancelActive) }` (`Ask.swift:64`, agora em `AskCardView.swift`): Esc passa a soltar. Em `Knobler/LinkPreviewView.swift:39`, o comentário "como no card de pergunta" deixa de ser verdade; reescreva.
  - Cenários: `ask-teclado` (`vm.tecladoNaPergunta = true`, `.setHighlight(1)`) e `ask-texto` (`vm.tecladoNaPergunta = true`, `vm.campoDaPerguntaFocado = true`, `.setText("Atalho, mas só com o notch fechado")`).

---

### Etapa 7

- **Título:** Pergunta espera enquanto o usuário digita no notch, com o selo "Claude perguntou".
- **Tela:** sim — quadro "Pergunta que chega enquanto você digita" do mockup.
- **Arquivos:** criar `Knobler/AskCard/AskSeloView.swift`; mudar `Knobler/NotchPresentation.swift`, `Knobler/NotchViewModel.swift` (`:152`), `Knobler/NotchView.swift` (`:55-83` e o ramo `.music` do corpo), `Knobler/KnoblerApp.swift` (`:1256-1258`), `tools/presentationcheck.swift`, `tools/main.swift`, `tools/notchview-fontes.txt`.
- **O que prova a etapa:**
  - `tools/presentationcheck.swift`, função pura `NotchContentState.perguntaVisivel(ask:agente:digitando:liberada:)`: pergunta do Claude sem digitação aparece; com digitação não aparece; com digitação e liberada aparece; card do Codex aparece sempre, com ou sem digitação; sem pergunta e sem Codex não aparece.
  - `./tools/check.sh` verde.
  - `Snapshots/ask-espera-nota.png`: a nota rápida em edição continua na tela, com uma faixa no topo trazendo o selo `◐ Claude perguntou` e a origem à direita; o card de pergunta **não** aparece. `Snapshots/ask-espera-liberada.png` (mesmo cenário depois do clique no selo): o card de pergunta aparece.
  - No cenário `ask-espera-liberada`, depois de liberar e de dispensar a pergunta (`.externalDismiss`), o texto da nota é o mesmo de antes (`precondition` dentro do `configure` do cenário).
  - Pergunta cancelada ou expirada durante a espera: o selo some (a pergunta ativa virou `nil`).
  - Numa tela que não está em edição, a mesma pergunta aparece na hora.
  - Ao vivo: digitando na nota, `POST /ask` → selo aparece, a digitação segue sem perder tecla; Esc na nota → a pergunta abre e o painel **não** fica com o teclado na pergunta (a legenda mostra o atalho). Reabra o Knobler de `/Applications` ao terminar.
- **Como fazer:**
  - "Digitando no notch" é o `protegeEdicao` (`Knobler/NotchViewModel.swift:152`: nota, agenda, lembretes ou WhatsApp em edição), hoje `private`. Exponha `var digitandoNoNotch: Bool { protegeEdicao }` e acrescente `@Published var perguntaLiberada: String?` (o id da pergunta que o usuário abriu pelo selo).
  - Em `Knobler/NotchPresentation.swift`, `static func perguntaVisivel(ask: Bool, agente: Bool, digitando: Bool, liberada: Bool) -> Bool { agente || (ask && (!digitando || liberada)) }` em `NotchContentState`.
  - `Knobler/NotchView.swift:82-83`: o `question:` passado a `vm.contentState` vira `perguntaVisivel(ask: askStore.state.active != nil, agente: agentRequestStore.state.active != nil, digitando: vm.digitandoNoNotch, liberada: vm.perguntaLiberada == askStore.state.active?.id)`. Use a mesma função em `Knobler/KnoblerApp.swift:1256-1258` (`questionIsActive`), com a view model daquela tela, e em `vm.perguntaDoClaudeAtiva` da etapa 6 (pergunta escondida não recebe o atalho). `KnoblerApp.swift:730` e `:1193` também leem `state.active`: leia o que cada um decide e troque só se decidir a apresentação daquela tela.
  - Selo visível = há pergunta do Claude ativa e ela não está visível nesta tela. Nesse caso, em `NotchView`, depois dos ajustes de `layout.sectionHeight` (`:55-73`), some 28 à altura; e no ramo `.music` do corpo, o conteúdo da seção passa a ser precedido por uma faixa de altura 22 com o selo alinhado à direita (6 de espaço até o conteúdo). O card cresce 28 pt enquanto a pergunta espera — é o aviso, e não cobre nenhum controle da seção.
  - `AskSeloView`: botão em cápsula de altura 22, padding horizontal 8, fundo `0.15` (`0.25` no hover): `◐ Claude perguntou` em 10 semibold e a `source` em 10 regular `0.62`. Clique grava `vm.perguntaLiberada = id`. `.help("Abrir a pergunta")`.
  - Sair do campo (Esc, clique fora) derruba o `protegeEdicao` e a pergunta aparece sozinha, sem teclado. `perguntaLiberada` volta a `nil` quando o id da pergunta ativa muda.
  - Cenários: `ask-espera-nota` (nota rápida em edição nesta tela, como os cenários de nota existentes fazem, mais um `.enqueue`) e `ask-espera-liberada` (o mesmo, mais `vm.perguntaLiberada = id`).

---

### Etapa 8

- **Título:** Documentação, novidade da 0.38.0 e imagens.
- **Tela:** não.
- **Arquivos:** mudar `CHANGELOG.md`, `Knobler/NovidadesCatalogo.swift`, `docs/ask.md`, `docs/images/ask-simple.png`, `docs/images/ask-multiselect.png`, `.claude/skills/snapshot-ui/SKILL.md`, `HANDOFF.md`; criar `Knobler/Novidades/0.38.0.html`.
- **O que prova a etapa:**
  - `./tools/check.sh` verde, incluindo o gate de novidades (`tools/novidadescheck.swift`: `NovidadesCatalogo.versoes` bate com os arquivos de `Knobler/Novidades/`).
  - `./tools/release.sh minor --dry-run` passa pela validação de notas e de novidade (não publica nada).
  - `grep -rn "1/N\|Esc cancela\|Esc manda" docs/ask.md Knobler/AskCard` não acha nada.
  - `docs/ask.md` descreve: atalho para dar o teclado ao card e a tabela de teclas; abas com volta e envio na última pendente; preview sempre inteiro; espera com selo durante a digitação; Esc solta, `⌘.` e ✕ cancelam.
- **Como fazer:**
  - `CHANGELOG.md`, em `## [Unreleased]`: `### Added` (teclado no card pelo atalho do notch; abas com volta; selo "Recomendada"; espera com selo durante a digitação; preview sempre inteiro) e `### Changed` (Esc no card solta o teclado em vez de cancelar — cancelar é `⌘.` ou ✕; descrições sempre inteiras; o card para de crescer em 60% da tela e a lista rola).
  - `Knobler/Novidades/0.38.0.html`: só `<section class="novidade"><h3>…</h3><p>…</p></section>`, sem `<html>` nem `<style>`, no formato de `Knobler/Novidades/0.37.0.html`. Acrescente `"0.38.0"` a `NovidadesCatalogo.versoes`. **Não** edite `MARKETING_VERSION` nem crie tag: só o `tools/release.sh` escreve versão.
  - `docs/ask.md:3-24`: reescreva o que diz "paginadas" e "Clique numa opção"; as duas imagens vêm dos snapshots novos, pela receita de `.claude/skills/snapshot-ui/SKILL.md`.
  - `.claude/skills/snapshot-ui/SKILL.md:41-60`: os cenários `ask-*` saem da lista do que não renderiza e entram na dos que rodam na janela real.
  - `HANDOFF.md`: estado desta entrega, citando a versão de release pretendida (0.38.0), sem "vN de sessão".
  - As specs antigas (`docs/superpowers/specs/2026-07-17-…`, `2026-08-11-…`) são registro histórico e não são reescritas.
