# Segurança e privacidade

## Reportar uma vulnerabilidade

Não publique credenciais, tokens ou detalhes exploráveis em uma issue pública.
Use o [GitHub Private Vulnerability
Reporting](https://github.com/luccas-silveira/knobler/security/advisories/new)
quando estiver disponível. Se o recurso não estiver habilitado, contate os
maintainers por um canal privado antes de divulgar o problema.

Inclua impacto, versão, passos mínimos de reprodução e uma correção sugerida
quando possível. Dê tempo razoável para triagem e correção antes de divulgação.

## Modelo de confiança

- A API local escuta somente em `127.0.0.1:4477` e não tem autenticação. Ela é
  apropriada para processos confiáveis do mesmo usuário, não para ser exposta
  por proxy, bind em `0.0.0.0` ou port-forward.
- O hook do Claude Code envia perguntas para essa API e faz polling da resposta.
  O script falha aberto para manter o fluxo no terminal quando o app não está
  disponível.
- Webhooks atravessam o relay externo configurado. Tokens são segredos e ficam
  no Keychain; links de perfil devem ser tratados como credenciais.
- Mensagens LAN e Bonjour tornam o dispositivo detectável na rede local quando
  o recurso está ligado. Não envie conteúdo sensível para peers não confiáveis.

## Dados e permissões

O app pode receber acesso a microfone, câmera, calendário, Bluetooth,
Acessibilidade, áudio do sistema e rede local. Cada permissão corresponde a uma
feature; desligar a feature em Ajustes impede seu uso, mas a autorização do
sistema deve ser revogada nos Ajustes do macOS quando necessário.

- Áudio do ditado é processado localmente por padrão; Deepgram é opt-in.
- O formatter local envia o transcript para o endpoint configurado (Ollama ou
  LM Studio). Trate esse endpoint como capaz de ler o texto enviado.
- Avatares remotos de webhook podem expor o IP do Mac ao servidor de origem;
  `loadRemoteImages` é opt-in.
- Chaves e tokens não devem ser gravados em `UserDefaults`, logs ou snapshots.
- O histórico e mídias de Mensagens ficam no armazenamento local do app.

### O que o app grava em disco

Tudo em `~/Library/Application Support/Knobler/`, **sem cifra** — a proteção é a
do FileVault e das permissões do seu usuário:

| Arquivo | Conteúdo | Vida |
|---|---|---|
| `notificationHistory.json` | Título e **corpo em claro** das notificações das últimas 24 h, inclusive as que foram silenciadas durante reunião e nunca viraram card | podado na carga pela janela de 24 h; teto de 300 linhas |
| `messages.json` | Histórico das Mensagens LAN, últimas 20 por peer | até apagar |
| `peerNames.json` | Último nome visto de cada peer | até apagar |
| `media/` | Fotos e GIFs recebidos nas Mensagens | apagado junto com a mensagem podada |
| `avatars/` | Foto de perfil dos peers (`.jpg`) | até apagar |
| `Arrastados/` | `.txt` gerado ao arrastar texto selecionado pro notch | até apagar |

Preferências ficam em `UserDefaults` (domínio `com.zoi.knobler`) — inclui o que
você configurou, **não** segredos.

No Keychain, com ACL presa ao requisito de assinatura do app: os três segredos do
pareamento de webhook (`deviceId`, `deviceSecret`, `publishToken`) e o token de
cada perfil. Trocar a assinatura do app torna os itens ilegíveis — é o estado
"Credenciais inacessíveis" descrito em [`docs/webhooks.md`](docs/webhooks.md).

Para zerar: apagar a pasta acima, `defaults delete com.zoi.knobler` e remover os
itens `com.zoi.knobler.webhook` do Keychain. Um backup do seu disco carrega tudo
isso, incluindo corpos de notificação e conversas.

## Dependências e distribuição

Reveja `Vendor/PROVENANCE.md` antes de atualizar o MediaRemote adapter. Valide
assinatura e origem de qualquer app distribuído antes de instalar. A release
Homebrew e o zip de GitHub são caminhos de distribuição diferentes; não copie
artefatos locais para uma release sem passar por `tools/release.sh`.
