# Qual feature é a cobaia

- map: ../map.md
- label: wayfinder:grilling
- status: closed
- assignee: claude (sessão 2026-08-04)
- blocked-by: — (001 e 002 fechados)

## Question

Uma feature só será convertida neste mapa. Escolher qual, com o levantamento de
001 na mão e a lista de 002 (a cobaia tem que ser candidata a plugin — converter
uma feature de fábrica não prova nada, porque ela nunca vai ser desligada).

Critérios em tensão:

- **Poucas amarras** faz o piloto terminar; mas uma cobaia fácil demais não
  descobre problema nenhum e a forma "provada" quebra na segunda conversão.
- **Ocupar mais de uma superfície** é o que dá valor ao teste (uma feature que
  tem seção no notch *e* painel de Ajustes *e* rota da API exercita a declaração
  inteira). Uma que só tem painel de Ajustes prova pouco.
- **Nada crítico**: se o piloto quebrar em produção, tem que ser numa feature
  que a pessoa consegue viver sem por uma versão.

Decidir também: **o que conta como piloto concluído** — a feature liga e desliga
pela preferência, some das três superfícies quando desligada, não acende nada no
sistema quando desligada, e o gate novo em `tools/check.sh` falha se alguém
regredir isso.

## Resolução (2026-08-04)

**A cobaia é o Pomodoro.**

### Por que o Pomodoro

Cruzando os encaixes que a peça tem (`003`: seção, painel, rotas, permissão,
`nascer`, `deps.instalado`) com as 15 features de `research/001-amarras.md`,
sobraram três candidatas de verdade:

| Candidata | Seção | Painel | Rota API | Permissão | Depende de outra peça |
|---|---|---|---|---|---|
| **Pomodoro** | sim | sim | não | não | **sim (Descanso)** |
| Espelho | sim | não | sim (`/mirror`) | sim (câmera) | não |
| Ditado | não | sim | não | sim (mic + AX) | sim (tap do VolumeHUD) |

Três motivos pelo Pomodoro:

1. É a **única** feature com a dependência plugin→plugin do catálogo
   (`KnoblerApp.swift:437-441`, `onPhaseBegin` chamando `DescansoController`).
   Essa é a regra mais escorregadia que 002 fixou ("a opção some, sem avisar") e
   só ela a exercita.
2. O Pomodoro **não tem toggle nenhum hoje** (`research/001-amarras.md` §1: o
   serviço existe sempre, só fica `idle`). Converter prova `nascer`/morrer de
   verdade — em Webhooks e Ditado parte do trabalho seria falsa, porque o toggle
   já desliga o serviço.
3. Nada crítico: é um cronômetro. Se o piloto quebrar em produção, dá pra viver
   uma versão sem ele.

**Preço aceito:** o Pomodoro não exercita `rotas` nem `permissao` da ficha.
Aceito porque acrescentar rota/permissão a uma peça depois é escrever duas
linhas na `struct`; a dependência entre peças, não — ela mexe no desenho.

**Descartado o Espelho** (contra-argumento real: cobre rota + permissão + é um
dos `.shared`, o caso que o `nascer`-closure foi feito pra alcançar): ele tem
três donos abrindo ele (calendário, `POST /mirror`, usuário) e estado espalhado
por todos os VMs. Bagunça no piloto vira dúvida sobre a forma, não sobre a
feature.

### O que conta como piloto concluído

1. **Liga e desliga pela preferência.** Com o Pomodoro desinstalado, o objeto
   `Pomodoro` não é criado (hoje `KnoblerApp.swift:79`).
2. **Some das superfícies.** Sem a peça: a seção não aparece no card nem no
   ordenador, o painel `SettingsPane.pomodoro` some da lista de Ajustes, e o anel
   da faixa fechada (`NotchView.swift:1010-1019`) some.
3. **Não acende nada no sistema.** O `Timer` de 1 s (`Pomodoro.swift:121-131`)
   não existe — é o que sustenta o `~0% CPU parado` do `PRODUCT.md`.
4. **A dependência some sem avisar.** Sem o Descanso instalado, a opção de travar
   a tela na pausa desaparece do painel do Pomodoro: sem alerta, sem item
   acinzentado.
5. **Gate novo em `tools/check.sh`** que falha se alguém regredir 1–4.

**Como o item 4 é provado:** só no harness. Como só o Pomodoro vira peça neste
mapa, o Descanso está sempre presente no app real — o caminho "sem Descanso"
nunca roda de verdade. O check monta um registro fabricado sem o Descanso e
confere que a opção sumiu. Descartado converter o Descanso junto: quebraria o
"uma cobaia só" de 002, que existe justamente pra não pagar retrabalho vezes 14.
