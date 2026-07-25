# Solicitações de agentes no NOB — Design

**Status:** aprovado em brainstorming; aguardando revisão escrita antes do plano de implementação.

## Objetivo

Exibir no NOB as perguntas e os pedidos de permissão de Claude Code e Codex,
mantendo o terminal/IDE como superfície paralela. A primeira resposta válida,
seja no NOB ou na superfície original, vence; a outra superfície fecha o
espelho.

## Escopo

- Reutilizar a experiência visual atual de Ask, com card compacto e detalhes
  expansíveis.
- Suportar perguntas estruturadas e permissões.
- Suportar Claude Code por `AskUserQuestion` e pelo hook oficial
  `PermissionRequest`.
- Suportar Codex CLI por um adaptador local.
- Investigar o mecanismo oficial disponível no Codex app/IDE e conectá-lo se
  houver uma integração suportada; sem automação visual como fallback.
- Preservar o endpoint e o fluxo atuais de Ask durante a migração.

O hook `PermissionRequest` do Claude recebe `tool_name`, `tool_input` e
opcionalmente `permission_suggestions`; sua resposta pode permitir ou negar a
execução. Referência: https://code.claude.com/docs/en/hooks.

## Modelo de domínio

Criar um domínio `AgentRequest`, separado do `Ask` legado:

```text
AgentRequest
  id: String
  agent: claude | codex
  kind: question | permission
  title: String
  summary: String
  details: String?
  source: terminal | cli | ide
  actions: [AgentRequestAction]
  state: pending | resolved | dismissed | expired
```

Perguntas podem conter opções e texto livre. Permissões podem conter `allow`,
`deny` e, quando o agente suportar, `allowAlways`.

O store é `@MainActor`, possui fila FIFO e é compartilhado por todos os
monitores. O servidor local conserva os estados pendentes até resolução,
cancelamento, leitura final pelo adaptador ou expiração.

## Transporte

Adicionar um protocolo local independente do agente:

- `POST /agent-requests` — publica uma solicitação;
- `GET /agent-requests/<id>` — consulta estado e resultado;
- `POST /agent-requests/<id>/resolve` — resolve com uma ação;
- `POST /agent-requests/<id>/dismiss` — cancela o espelho;
- `GET /status` — inclui contagens e estado do domínio.

O listener permanece limitado a `127.0.0.1`. Endpoints de resolução exigem um
token efêmero por sessão, armazenado em arquivo com modo `0600`. Payloads têm
limite de tamanho, são tratados apenas como dados e nunca são executados pelo
NOB.

## Adaptadores

### Claude Code

O hook atual de `AskUserQuestion` publica no protocolo novo. Um hook
`PermissionRequest` publica ferramenta, comando/caminho, descrição e sugestões
de permissão. O hook aguarda a decisão do protocolo e devolve `allow` ou
`deny`; se o terminal resolver primeiro, o NOB apenas fecha o espelho.

### Codex CLI

Adicionar um adaptador local reutilizável, exposto pelo CLI do projeto, que
publique a solicitação, aguarde a resolução e devolva a decisão ao processo do
Codex. O adaptador não depende de SwiftUI.

### Codex app/IDE

Verificar primeiro hooks, MCP ou API de aprovação oficialmente disponíveis na
versão instalada. Se houver integração suportada, ela usará o mesmo protocolo.
Se não houver, o suporte fica explicitamente limitado ao CLI; não haverá
automação por coordenadas, OCR ou cliques simulados.

## UI do NOB

- Cabeçalho com ícone e agente (`Claude`/`Codex`);
- selo `Pergunta` ou `Permissão`;
- resumo curto sempre visível;
- `Ver detalhes` para expandir comando, caminho, descrição ou diff;
- ações contextuais na base;
- fechamento automático quando a superfície original responder;
- indicação discreta de resposta externa em corrida;
- apenas um card ativo, com fila compartilhada entre monitores.

Comandos perigosos aparecem truncados no resumo e completos apenas na área
expandida. O NOB não executa comandos nem altera arquivos.

## Falhas e segurança

- Timeout do adaptador resulta em `deny` seguro;
- solicitações órfãs expiram;
- resolução duplicada é no-op;
- NOB fechado não altera o fluxo nativo do agente;
- erro de transporte deixa a solicitação na superfície original;
- payload malformado ou acima do limite retorna erro sem enfileirar;
- nenhum texto recebido é interpretado como shell, URL automática ou código.

## Validação

- reducer puro para fila, corrida, cancelamento e expiração;
- fixtures de `AskUserQuestion` e `PermissionRequest` do Claude;
- teste do adaptador Codex CLI;
- snapshots compacto/expandido para pergunta e permissão;
- E2E terminal-versus-NOB com respostas quase simultâneas;
- fallback com NOB fechado;
- verificação de que o Codex app/IDE só é declarado suportado após evidência da
  integração oficial.

## Decisões

- Protocolo novo em vez de sobrecarregar `/ask`, para não misturar contratos de
  perguntas e permissões.
- Primeira resposta válida vence.
- Resumo por padrão, detalhes sob demanda.
- Sem automação visual do Codex app/IDE.
- O `Ask` atual permanece compatível até a migração completa.
