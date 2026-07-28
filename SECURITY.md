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

## Dependências e distribuição

Reveja `Vendor/PROVENANCE.md` antes de atualizar o MediaRemote adapter. Valide
assinatura e origem de qualquer app distribuído antes de instalar. A release
Homebrew e o zip de GitHub são caminhos de distribuição diferentes; não copie
artefatos locais para uma release sem passar por `tools/release.sh`.
