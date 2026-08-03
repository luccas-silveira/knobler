Type: task
Blocked by: 02, 03, 04, 05, 06
Status: resolved

## Question

Quais cenários reais e automatizados precisam passar para considerar a feature pronta: desenho em cada ferramenta, atalhos, multi-monitor, Retina, auto-fade, persistência, acessibilidade, performance e interação com Zoom/Meet/Keynote/OBS?

## Answer

`tools/annotationcheck.swift` cobre ferramentas, atalho, modo padrão, backgrounds e undo/redo; ele entrou em `tools/check.sh`. `xcodegen generate`, build Debug, `git diff --check` e os 21 gates do `check.sh` passaram. A validação de gesto real com Control direito e leitura visual em Zoom/Meet/Keynote/OBS continua manual, pois exige Acessibilidade e sessão gráfica.
