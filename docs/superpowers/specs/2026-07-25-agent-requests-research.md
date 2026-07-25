# Pesquisa — solicitações de agentes no NOB

**Data:** 2026-07-25  
**Escopo:** Claude Code 2.1.220, Codex CLI 0.145.0, Codex app/IDE e bridge local do Knobler.

## Resumo executivo

O Claude possui um caminho oficial e estável: o evento de hook `PermissionRequest`, além do `AskUserQuestion` já integrado.

O Codex CLI possui hooks, mas os hooks instalados localmente cobrem ciclo de vida e ferramentas (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`); não há evento de aprovação nesses hooks.

A versão local do Codex, porém, expõe no `app-server` experimental pedidos RPC de aprovação para comandos, alterações de arquivos e permissões. Esse é o caminho técnico mais promissor para atender CLI e app/IDE com um adaptador único, mas a integração de uma sessão já aberta ainda precisa ser validada.

## Claude Code

### Evidência local

- Executável: `claude 2.1.220`.
- `~/.claude/settings.json` já possui o hook global `AskUserQuestion` apontando para `~/.claude/hooks/knobler-ask.sh`.
- Não existe ainda um hook `PermissionRequest` configurado.

### Contrato oficial

O hook `PermissionRequest` é disparado quando o diálogo de permissão seria exibido. Recebe `tool_name`, `tool_input` e, opcionalmente, `permission_suggestions`.

A resposta usa:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": { "behavior": "allow" }
  }
}
```

Para negar, usa `"behavior": "deny"` e uma mensagem. Permissões persistentes podem ser aplicadas via `updatedPermissions`, mas isso deve ser uma ação explícita no NOB, não um efeito colateral de `Allow`.

Fonte primária: [Claude Code Hooks](https://code.claude.com/docs/en/hooks).

### Implicação

O adaptador Claude pode compartilhar o transporte do card, mas deve manter os contratos de `AskUserQuestion` e `PermissionRequest` separados na entrada e traduzir ambos para `AgentRequest`.

## Codex CLI

### Evidência local

- Executável: `/opt/homebrew/bin/codex`.
- Versão: `codex-cli 0.145.0`.
- `codex --help` expõe `app-server`, `remote-control`, `mcp-server` e `--ask-for-approval`.
- `~/.codex/hooks.json` contém apenas `SessionStart`, `UserPromptSubmit` e `Stop`; os hooks de plugins adicionam `PreToolUse`/`PostToolUse`, mas não um evento de aprovação.

### O que os hooks cobrem

Os hooks existentes podem publicar atividade ou observar ferramentas, mas não conseguem esperar a decisão do prompt nativo e resolvê-lo. Um wrapper que apenas inicie `codex` também não tem contrato para interceptar a aprovação do TUI.

Conclusão: **não usar hook de ciclo de vida como mecanismo de aprovação do Codex**.

## Codex app-server

### Descoberta no protocolo instalado

O comando abaixo gerou o schema experimental da versão instalada:

```bash
codex app-server generate-json-schema --experimental --out <diretório>
```

O schema contém estes pedidos servidor → cliente:

- `item/commandExecution/requestApproval`;
- `item/fileChange/requestApproval`;
- `item/permissions/requestApproval`.

Os payloads carregam dados suficientes para o card: comando, diretório de trabalho, motivo, ações parseadas, `itemId`, `threadId`, `turnId`, alterações de arquivo/diff e permissões de filesystem/rede.

As respostas incluem, conforme o tipo:

- comando: `accept`, `acceptForSession`, `decline`, `cancel`;
- alteração de arquivo: `accept`, `acceptForSession`, `decline`, `cancel`;
- permissões: perfil concedido e escopo (`turn` ou equivalente).

O `app-server` aceita `stdio`, Unix socket ou WebSocket. Para listeners não locais, o CLI documenta autenticação por capability token ou bearer token.

### Risco e limitação

O protocolo está marcado como experimental e a geração de schema é evidência da versão local, não garantia de estabilidade entre releases. Também ainda não foi provado que uma sessão iniciada no TUI ou no app pode ser anexada externamente ao `app-server` sem ser iniciada por ele.

### Implicação

O adaptador Codex deve priorizar `app-server` e tratar a versão do protocolo como capacidade detectável. Se a sessão atual não aceitar conexão externa, o suporte fica explícito como “iniciar via bridge do NOB/app-server”, sem tentar ler ou clicar na interface do terminal/IDE.

## Codex app/IDE

As fontes públicas consultadas confirmam que CLI e extensão IDE compartilham o modelo de aprovação do Codex, mas não documentam um hook externo estável para a UI. A documentação de segurança também descreve aprovações como parte das superfícies locais do CLI e IDE.

Resultado: o app/IDE só deve ser declarado suportado depois de um teste com `app-server` que demonstre recebimento e resposta aos três pedidos RPC. Automação por OCR, coordenadas ou eventos de teclado fica descartada.

Fontes:

- [OpenAI Codex CLI — Getting Started](https://help.openai.com/en/articles/11096431);
- [Running Codex safely at OpenAI](https://openai.com/index/running-codex-safely/).

## Segurança do bridge

- manter transporte em loopback/Unix socket;
- usar capability token por sessão quando houver socket/WebSocket;
- validar `threadId`, `turnId` e identificadores opacos sem interpretá-los como comandos;
- truncar o resumo, mas preservar detalhes no payload expandido;
- nunca executar o comando ou aplicar o diff no NOB;
- mapear `deny`/cancelamento e timeout para a decisão segura do agente;
- não habilitar automaticamente permissões persistentes.

## Decisão de pesquisa

1. Claude: implementar adaptador de `PermissionRequest` ao lado do hook `AskUserQuestion`.
2. Codex: pesquisar e implementar primeiro o bridge baseado em `app-server`, não um wrapper que tenta parsear o TUI.
3. Manter um capability check por versão e uma mensagem de fallback quando o Codex em execução não puder ser conectado.
4. Antes do plano, executar um spike sem mudanças no produto: iniciar um `app-server` controlado, observar um pedido de aprovação e responder pelo protocolo gerado.

## Spike executado

O `app-server` foi iniciado em `stdio://` e aceitou um `initialize` com
`experimentalApi: true`. A resposta identificou corretamente a plataforma
macOS/arm64, a versão `0.145.0` e o diretório `CODEX_HOME`. O servidor também
emitiu `remoteControl/status/changed` com estado `disabled`.

Isso confirma o handshake e o transporte local. Não foi disparado um comando
real para fabricar um prompt de aprovação nesta fase; a criação de uma thread
com execução teria efeitos externos e fica para um harness isolado no plano.

### Limitação validada pelo spike

Na versão instalada (`codex-cli 0.145.0`), o `initialize` experimental é
suficiente para detectar `platformOs`, `platformFamily` e `userAgent`, mas não
existe uma entrada RPC para injetar um pedido de aprovação. O spike usa uma
fixture estática para validar a resposta `accept`, sem criar thread, turno ou
comando. Portanto, ele valida apenas handshake e formato; a ponte definitiva
continua condicionada aos três pedidos de aprovação realmente emitidos pelo
`app-server` em uma sessão controlada e deve ser revalidada após atualizar o
Codex.
