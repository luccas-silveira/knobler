# WhatsApp no notch — duas contas, conversa completa

## Objetivo

Ligar as duas contas de WhatsApp do Luccas (4143, Business, e 8292, pessoal)
ao Knobler, com conversa completa no notch: ler e responder texto, foto, vídeo,
documento, áudio, grupos, reações e citação.

Sucesso: mensagem chegando em qualquer das duas contas vira card no notch em
até 2 segundos, e tudo listado acima funciona sem abrir o celular nem o
WhatsApp Desktop.

## Público e alcance

Só o Luccas. A feature depende de uma ponte local que só ele roda; quem
instala o Knobler pelo brew não vê nada dela (nem na vitrine de plugins).

## Restrições

- Conexão não oficial (whatsmeow, multi-device). Risco de banimento aceito
  pelo dono; nada que pareça automação em massa.
- Deployment target do app segue macOS 14.2.
- O MCP do Claude (`whatsapp-mcp-server`) continua funcionando durante e
  depois da mudança.
- A ponte escuta só em `127.0.0.1`.

## Arquitetura

Duas partes, em dois repositórios.

**Ponte** (`~/Code/whatsapp-mcp/whatsapp-bridge`, Go, serviço do macOS
`com.whatsapp-mcp.bridge`): único ponto que fala com o WhatsApp. É a fonte da
verdade de conversas, mensagens e mídia.

**Knobler**: só cliente da ponte. Não guarda conversa em disco; mantém um
cache em memória e um cache de mídia descartável.

Com a ponte fora do ar, a seção mostra o aviso e as notificações do WhatsApp
Desktop voltam a virar card como hoje.

## Componentes

### Ponte

1. **Cofre multi-conta.** As sessões das duas contas no mesmo processo, cada
   uma com sua identidade de aparelho. Cada mensagem salva ganha a marca da
   conta. Toda rota aceita o parâmetro de conta; sem ele, vale o 4143
   (compatibilidade com o MCP).
2. **Canal ao vivo** (Server-Sent Events). Eventos: mensagem nova, recibo
   (entregue, lido), reação, mensagem editada/apagada, estado da conexão de
   cada conta. Cada evento tem um número sequencial; o cliente pede "o que
   mudou desde N" ao reconectar.
3. **Rotas de leitura.** Contas e estado, conversas (com não lidas e última
   mensagem), mensagens paginadas por conversa, mídia, foto de perfil, dados
   de grupo (nome, participantes).
4. **Rotas de ação.** Texto, mídia (foto, vídeo, documento), áudio de voz,
   reação, responder citando, marcar como lida.
5. **Pareamento.** Rota que inicia o pareamento de conta nova e devolve o QR
   (e o estado dele) até a conta conectar.

Autenticação: a ponte passa a exigir uma chave, guardada no Keychain e
compartilhada com o Knobler e com o MCP. Requisição sem a chave é recusada.

### Knobler

1. **Cliente da ponte.** Chamadas HTTP e o canal ao vivo, com reconexão
   sozinha e recuperação do que mudou durante a queda.
2. **Estado do WhatsApp.** Contas, conversas, mensagens, não lidas. Singleton
   injetado em todas as janelas (como `AskStore`), nunca um por monitor.
3. **Seção WhatsApp do notch.** Seletor de conta (com estado de conexão),
   lista de conversas (individuais e grupos), conversa, campo de envio com
   anexo, gravação de áudio, reação e citação.
4. **Card de chegada.** Conta, quem mandou (e o grupo, se for), prévia
   (texto ou miniatura), resposta rápida.
5. **Peça instalável.** Segue o sistema de plugins (`Plugin.swift`). Só
   aparece na vitrine quando a ponte responde no Mac.

Mais o **filtro no interceptor de notificações**: descarta o banner do
WhatsApp Desktop enquanto a ponte está conectada; deixa passar quando ela cai.

## Fluxo de dados

**Recebimento.** Celular, ponte (salva com a marca da conta), canal ao vivo,
estado do Knobler. Se a conversa não está aberta na frente do usuário, desce o
card.

**Envio.** O Knobler chama a ação na ponte. A bolha aparece na hora como
"enviando", vira "enviada" com a confirmação, e ganha entregue e lido conforme
os recibos chegam pelo canal.

**Mídia.** Fica na ponte. O Knobler pede o arquivo só quando a bolha aparece
na tela e guarda numa pasta de cache que pode ser apagada.

**Áudio.** A conversão de formato (voz do WhatsApp para algo que o macOS toca,
e a gravação de volta para o formato de voz do WhatsApp) mora na ponte. A
pesquisa decide a forma.

**Queda do canal.** Ao reconectar, o Knobler pede à ponte os eventos desde o
último número que viu. Nenhuma mensagem some no buraco.

**Leitura.** O Knobler nunca marca como lida sozinho: nem abrir a conversa,
nem ver o card. Marca quando o usuário pede (botão) ou quando responde
naquela conversa.

## Erros

- **Ponte fora do ar:** aviso na seção com o comando de religar; card volta a
  vir do WhatsApp Desktop; reconexão automática a cada poucos segundos, sem
  travar a UI.
- **Conta deslogada** (o celular removeu o aparelho vinculado): o seletor
  marca a conta como desconectada e oferece o QR para parear de novo no
  próprio notch. A outra conta segue funcionando.
- **Envio que falha:** bolha vermelha com "tentar de novo". Nada é reenviado
  sozinho.
- **Mídia expirada no servidor:** bolha mostra "mídia indisponível" e tenta a
  recuperação pelo celular uma vez.
- **Chave errada ou ausente:** a seção diz que a chave não confere, em vez de
  "ponte fora do ar".

## Testes

**Ponte (Go):** cofre multi-conta, marca de conta nas mensagens, rotas sem
parâmetro de conta respondendo como hoje (o MCP não quebra), recorte "desde o
evento N", recusa sem chave.

**Knobler:** gate novo em `tools/check.sh` cobrindo a lógica pura sem rede:
aplicar eventos ao estado, deduplicar, ordenar conversas, contar não lidas,
transição da bolha (enviando, enviada, entregue, lida, falhou), regra do
filtro do banner do Desktop. Estados visuais (seção vazia, ponte fora, conta
desconectada, card de chegada, QR) no `tools/snapshot.sh`. Lista e conversa
rolam e `ScrollView` não renderiza offscreen: conferidas no app real.

**Ponta a ponta:** 4143 e 8292 um contra o outro. Mandar do 4143 para o 8292
e o card descer em até 2 segundos; responder citando, reagir, mandar foto,
documento e áudio pelo notch; conferir pelo recibo da ponte e pelo histórico
da outra conta. Exige parear o 8292 na ponte por QR uma vez (passo do
usuário).

## Fora do escopo

- Ligação de voz/vídeo, status/stories, comunidades, canais.
- Feature pública para quem instala pelo brew.
- Envio em massa ou automação de mensagens.
