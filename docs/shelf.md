# Prateleira de arquivos (Shelf)

![Notch expandido com a prateleira](images/expanded-shelf.png)

## O que faz

Uma prateleira de arquivos temporários no notch: arraste um arquivo pro notch
e ele expande sozinho; o item fica guardado no card aberto até você arrastar
de volta pro Finder (ou pra outro app). Screenshots novos também podem cair
direto na prateleira automaticamente (observados via Spotlight, sem polling),
prontos pra arrastar em vez de precisar ir até a área de trabalho.

## Como usar

- Arraste qualquer arquivo em direção ao notch — ele expande e aceita o drop.
- Arraste um item da prateleira de volta pra fora (Finder, outro app) pra
  "tirar" ele de lá.
- Screenshots caírem automaticamente na prateleira: Ajustes → Notch
  (`screenshotsToShelf`).
- **Botão direito** (ou Control+clique) na miniatura abre o menu:

```
Converter     ▸ …                       (só quando o tipo tem conversão)
Compartilhar  ▸ Enviar por AirDrop
                Compartilhar…           (menu nativo: Mensagens, Mail, Notas…)
                Enviar tudo por AirDrop (N)   ← a partir de 2 itens
──────────────
Mostrar no Finder
Remover do shelf
```

### Converter

Os destinos dependem do tipo do arquivo:

| Arquivo | Vira |
|---|---|
| imagem (PNG, JPEG, HEIC…) | PNG · JPEG · HEIC · PDF |
| PDF | PNG — uma imagem por página, em 2x |
| vídeo | MP4 · MOV |
| Markdown (`.md`, `.markdown`) | PDF |

O formato atual nunca aparece na lista. O arquivo novo nasce **ao lado do
original**, com nome livre (`foto-1.png` se `foto.png` já existir), e entra na
prateleira; o original nunca é tocado. Conversão de vídeo mostra o progresso na
faixa de atividade do notch — as outras são instantâneas.

O Markdown é renderizado pelo próprio app (parser do Foundation + CoreText):
cabeçalhos, negrito/itálico, código, listas e citação, paginado em Letter.
Tabela, imagem embutida e regra horizontal ainda não desenham.

## Permissões

Nenhuma permissão especial. (O app roda sem sandbox — os caminhos dos
arquivos da prateleira ficam em UserDefaults, não em bookmarks
security-scoped.)
