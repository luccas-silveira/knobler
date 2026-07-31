# Anotação de tela

O Knobler pode desenhar sobre a tela inteira, como o DemoPro, sem capturar nem
gravar o conteúdo que está por baixo.

## Uso

O atalho padrão é o **Control direito**. No modo padrão, segure a tecla para
ativar o overlay e solte para sair. O modo **Alternar** pode ser escolhido em
Ajustes › Notch: uma pressão entra e outra sai.

O menu do Knobler permite escolher desenho livre, linha, seta, retângulo,
elipse, texto, laser, holofote e borracha. Também há comandos para desfazer,
refazer, apagar tudo e escolher a cor. O overlay cobre cada monitor e mantém
as anotações separadas por display.

## Quadro e persistência

O fundo pode ser transparente, branco ou negro. As anotações são salvas em
`~/Library/Application Support/Knobler/annotations/`, um arquivo JSON por
monitor, e restauradas na próxima execução. O auto-fade é opcional e pode ser
configurado em Ajustes; laser e holofote desaparecem automaticamente.

O recurso depende da permissão de Acessibilidade porque o atalho é detectado
por `CGEventTap`. Sem ela, o restante do app continua funcionando, mas o
Control direito não ativa a anotação.

## Limites

O overlay não faz captura, gravação, OCR, colaboração ou edição de slides.
Essas funções devem continuar fora desta feature.
