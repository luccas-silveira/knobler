Type: research
Blocked by: 01
Status: resolved

## Question

Como mapear cursor, eventos e coordenadas entre displays, incluindo monitores Retina, Sidecar, telas com notch e mudança/desconexão de monitores, sem duplicar estado ou perder anotações?

## Answer

O controller cria uma janela e um `AnnotationOverlayState` por `CGDirectDisplayID`, usando `NSScreen.frame` e coordenadas locais do canvas. Mudanças de configuração de telas recriam/removem apenas o display afetado. O estado é separado por display e salvo em JSON, evitando misturar coordenadas entre Retina, Sidecar e monitor principal.
