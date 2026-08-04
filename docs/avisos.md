# Avisos do desenvolvedor

Um canal só de ida: quem mantém o Knobler publica um recado — uma novidade da
versão, um aviso de manutenção, um problema descoberto — e ele vira card no
notch. Não há resposta, não há telemetria de volta, e o app não manda nada
sobre você em nenhum momento.

## Como funciona

O app baixa um JSON público do repositório uma vez por dia (e uma vez ~45 s
depois de abrir). Cada aviso tem um `id`; o que já apareceu uma vez fica
registrado e nunca volta. O card entra pelo mesmo caminho de qualquer
notificação vinda de fora, então respeita **silenciar durante reuniões**: se
você estiver numa call, o aviso vai direto pro Histórico e você o lê quando a
reunião acabar.

Não há servidor no meio: é um `GET` num arquivo estático do GitHub. Nenhum
identificador do seu Mac é enviado — a requisição não leva nada além do que
qualquer download de arquivo leva.

## Desligar

**Ajustes → Geral → Avisos do desenvolvedor.** Nasce ligado.

Desligado, os avisos normais param. Os marcados como **críticos** continuam
chegando: são reservados a problema de segurança e a falha que perde dado —
coisa que você precisa saber mesmo tendo desligado o resto. Se isso não te
serve, os avisos críticos usam o mesmo caminho de notificação de todo o
resto: desligar **Notificações no notch** (Ajustes → Notch) silencia tudo.

## Permissões

Nenhuma. Usa rede normal, sem entitlement de sistema.

---

## Publicar um aviso (mantenedores)

Editar `avisos.json` na raiz do repo e commitar no `master`. Não há deploy.

```jsonc
{
  "versaoSchema": 1,
  "avisos": [
    {
      "id": "2026-08-relay-manutencao",  // único e definitivo; ver abaixo
      "titulo": "Relay em manutenção às 3h",
      "corpo": "Os webhooks ficam fora do ar por ~10 min.",
      "prioridade": "normal",            // ou "critica"; ausente = normal
      "iconEmoji": "🛠️",                 // opcional
      "som": false,                      // opcional
      "minVersao": "0.19.0",             // opcional, inclusivo
      "maxVersao": "0.20.0",             // opcional, inclusivo
      "acoes": [                         // opcional, no máximo 2
        { "titulo": "Detalhes", "url": "https://github.com/..." }
      ]
    }
  ]
}
```

Limites, todos validados pelo `avisoscheck`: 10 avisos por arquivo, título de
80 e corpo de 400 caracteres, 2 ações, 64 KB de arquivo. Ação **só em https** —
`http`, `file://` e esquema de app são recusados pelo app mesmo que passem no
gate.

`minVersao`/`maxVersao` evitam mandar "atualize, a 0.19 tem um bug" pra quem já
está na 0.20. Faixa com typo (`"0.19"` em vez de `"0.19.0"`) **não vale pra
ninguém** — falha fechada de propósito, e o gate reprova antes do commit.

### ⚠️ Publicar é irreversível

O app que já baixou o aviso não volta a consultar por 24 h, e o `raw` do GitHub
ainda tem cache de CDN. Apagar a linha do JSON **não** desfaz o que já apareceu.
Corrigir significa publicar outro aviso, com `id` novo. Reciclar um `id` é pior:
quem já viu o antigo não recebe o novo.

Por isso o `tools/check.sh` valida o `avisos.json` deste repo — é a única rede
de proteção antes da base inteira.

### Testar antes

```bash
python3 -m http.server 8477                 # servindo um avisos.json de teste
defaults write com.zoi.knobler avisos.feedURL "http://127.0.0.1:8477/avisos.json"
defaults delete com.zoi.knobler avisos.vistos   # faz o aviso poder aparecer de novo
# relance o app; o card vem ~45 s depois
defaults delete com.zoi.knobler avisos.feedURL  # volta ao feed real
```

`avisos.vistos` guarda os últimos 100 ids mostrados.
