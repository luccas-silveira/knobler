# Perguntas do Claude Code (Ask)

![Card de pergunta simples](../Snapshots/ask-simple.png)

*Pergunta de escolha única.*

![Card de múltipla escolha](../Snapshots/ask-multiselect.png)

*Múltipla escolha.*

## O que faz

Quando o Claude Code usa a ferramenta `AskUserQuestion` (por exemplo, num hook
`PreToolUse`), a pergunta aparece como um card interativo no notch em vez de
ficar só no terminal — com opções de escolha única ou múltipla, e suporte a
perguntas em sequência (paginadas). Responder no card devolve a resposta pro
Claude via o mesmo hook que publicou a pergunta.

## Como usar

- Não exige ação manual do lado do Knobler: um hook `PreToolUse` do seu
  projeto Claude Code publica a pergunta via `POST /ask` na API local
  (ver `docs/local-api.md`); o card aparece sozinho.
- Clique numa opção (ou marque várias, se for múltipla escolha) e confirme.

## Permissões

Nenhuma permissão especial — só a API local (`127.0.0.1:4477`), que não
exige permissão de sistema.
