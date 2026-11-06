# WhatsApp no notch

O Knobler é cliente de uma ponte local de WhatsApp. Ele não fala com o WhatsApp
direto: tudo passa pela ponte, cujo contrato (rotas, objetos, canal ao vivo,
chave) está em `docs/whatsapp-ponte.md`.

## O que é

Duas contas de WhatsApp (as do dono) ligadas ao notch: seção larga com a lista
de conversas e a conversa aberta, card de chegada com resposta, áudio, mídia,
reação e citação. A ponte mora em `~/Code/whatsapp-mcp/whatsapp-bridge` e é a
fonte da verdade; o Knobler guarda só um cache em memória (`WhatsAppStore.shared`).

Quem não tem a ponte não vê nada: a peça não aparece na vitrine, a seção não
existe e nenhuma notificação muda.

## Pré-requisitos

- Ponte do contrato 1 (`docs/whatsapp-ponte.md`) rodando como serviço
  `com.whatsapp-mcp.bridge` (launchd).
- A ponte respondendo em `127.0.0.1` na porta configurada (padrão 8099).

## Chave e porta

- Chave: `~/Library/Application Support/whatsapp-bridge/api-key` (modo `0600`,
  pasta `0700`). Quem cria é a ponte; o Knobler só lê e manda como
  `Authorization: Bearer <chave>`.
- Porta: `whatsappPortaDaPonte` no `UserDefaults` (padrão 8099; valor fora de
  1...65535 volta ao padrão). Serve pra testar contra uma segunda ponte
  apontada pra uma cópia do `store/`, sem tocar na que está em uso:

```bash
defaults write com.zoi.knobler whatsappPortaDaPonte -int 8199
defaults delete com.zoi.knobler whatsappPortaDaPonte   # volta pra 8099
```

## Instalar a peça

A peça WhatsApp só aparece na vitrine de peças quando a sonda identifica a
ponte (`GET /v1/ponte`). Instalar a peça liga o `WhatsAppStore`, que nasce
inerte; desinstalar desliga o canal e some com a seção.

## Parear uma conta

Conta sem pareamento mostra o QR dentro do próprio notch (`POST /v1/pareamento`).
Leia com o WhatsApp do celular em Aparelhos conectados. O código vale cerca de
160 s; expirado, o notch oferece "Gerar outro".

## Estados

| Estado | O que o notch mostra | O que fazer |
|---|---|---|
| Ponte fora do ar | "A ponte do WhatsApp não está respondendo." e o comando pra religar | o Knobler tenta de novo sozinho; pra religar já, `~/Code/whatsapp-mcp/whatsapp-bridge/servico.sh`. Enquanto isso, os cards voltam a vir do WhatsApp Desktop |
| Sem chave | "A chave da ponte não confere." com o caminho do `api-key` | conferir se a ponte está rodando (é ela que cria o arquivo) |
| Chave não confere (`401`) | "A chave da ponte não confere." | os dois têm que ler o mesmo arquivo de chave; conferir e tentar de novo |
| Ponte incompatível | "A ponte do WhatsApp é de outra versão." | atualizar a ponte ou o Knobler pra mesma versão do contrato |
| Carregando | nada | esperar |
| Sem pareamento | QR | parear (seção acima) |
| QR expirado | "QR expirado" e "Gerar outro" | gerar outro e escanear de novo (vale ~160 s) |
| Sem conversa | "Nenhuma conversa ainda" | escolher ou começar uma conversa |
| Conversa | lista e conversa | — |

## Testes

- `./tools/check.sh` roda os gates `tools/whatsapp*check.{swift,sh}` (modelos,
  cliente, canal, store, telas, ligações e esta doc, em `whatsappdocscheck`).
- `./tools/snapshot.sh` gera `Snapshots/whatsapp-*.png` (exige sessão gráfica).
- Ponta a ponta é manual: com a ponte de pé, instalar a peça, parear, mandar e
  receber texto, áudio e mídia nas duas contas.
