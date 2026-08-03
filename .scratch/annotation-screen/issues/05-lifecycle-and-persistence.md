Type: grilling
Blocked by: 01, 03
Status: resolved

## Question

O que permanece enquanto o modo está ativo, quando as anotações desaparecem, se auto-fade é configurável, se o quadro branco é persistido entre sessões e como funcionam limpar, desfazer e recuperação após encerramento inesperado?

## Answer

Anotações persistem por monitor em `Application Support/Knobler/annotations`. O fundo transparente/branco/negro fica em `UserDefaults`; auto-fade é opcional e laser/holofote expiram automaticamente. Limpar é reversível por undo; gravação usa escrita atômica e não captura a tela.
