# Conta-gotas (color picker)

## O que faz

Amostra qualquer pixel da tela — de qualquer app, do desktop, de um vídeo — e
copia a cor pro clipboard. Usa a lupa nativa do macOS (`NSColorSampler`), a
mesma do Xcode e dos Ajustes do Sistema.

## Como usar

1. Menu da barra (**◐**) → **◉ Selecionar cor…**
2. O cursor vira a lupa; clique no pixel que quiser.
3. O **HEX** (`#1E88E5`) vai pro clipboard, pronto pra colar.
4. O notch mostra um card com a amostra da cor e os outros formatos pra
   consulta: `rgb(30, 136, 229)` e `Color(red: 0.118, green: 0.533, blue: 0.898)`.

`Esc` cancela e não mostra card nenhum.

## Formatos

| Formato | Exemplo | Onde aparece |
|---|---|---|
| HEX | `#1E88E5` | clipboard |
| RGB | `rgb(30, 136, 229)` | card |
| SwiftUI | `Color(red: 0.118, green: 0.533, blue: 0.898)` | card |
| CSS moderno | `rgb(30 136 229)` | só no código (`ColorPicker.Format.css`) |

A cor amostrada é convertida pra **sRGB** antes de virar texto — é o
denominador comum dos quatro formatos, então uma tela P3 não devolve valores que
não existem fora dela.

## Limites conhecidos

- O formato copiado é sempre HEX; não há preferência pra trocar (os outros ficam
  legíveis no card).
- O card some sozinho em 5s, como qualquer notificação.

## Permissões

Nenhuma. A lupa é um serviço do sistema — o app não lê a tela por conta própria,
então nada de Gravação de Tela.
