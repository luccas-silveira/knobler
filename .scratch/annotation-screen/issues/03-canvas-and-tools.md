Type: prototype
Blocked by: 01
Status: resolved

## Question

Qual modelo de canvas e ferramentas entrega desenho livre, linha, seta, retângulo, elipse, texto, laser/destaque, borracha, seleção, cores, espessura, opacidade e undo/redo sem criar um editor desnecessariamente complexo?

## Answer

O canvas usa SwiftUI `Canvas` com elementos Codable e pontos em coordenadas locais. Foram implementados desenho livre, linha, seta, retângulo, elipse, texto, laser, holofote e borracha, com cor, espessura, opacidade, undo/redo e limpeza. A edição é deliberadamente direta: sem seleção/movimentação de objetos ou editor de slides.
