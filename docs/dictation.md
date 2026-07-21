# Ditado

![Gravando ditado](../Snapshots/dictation-recording.png)

*Gravando (⌥ direita segurada).*

![Transcrevendo](../Snapshots/dictation-transcribing.png)

*Transcrevendo.*

## O que faz

Ditado estilo Superwhisper: segurar a tecla ⌥ (Option) direita grava o
microfone; soltar transcreve com Parakeet v3 rodando local (via FluidAudio) —
ou Deepgram na nuvem, se configurado — e cola o texto no app ativo (via
pasteboard + ⌘V sintético) onde o cursor estiver. Opcionalmente, um segundo
passo local via IA (Ollama/LM Studio, modelo `gemma3:4b` por padrão) limpa o
transcript bruto: tira fillers e falsos começos, arruma pontuação, acento e
capitalização — sem inventar conteúdo. Se a formatação falhar por qualquer
motivo, cai de volta pro transcript bruto (nunca perde o ditado).

## Como usar

- Segure ⌥ direita, fale, solte — o texto aparece onde o cursor estiver.
- Ligar/desligar ditado, escolher nuvem (Deepgram) vs. local (Parakeet), e
  ligar/configurar a limpeza por IA local: Ajustes → Ditado.
- Formatação por IA local exige um servidor OpenAI-compatible rodando
  (Ollama ou LM Studio) no endpoint configurado.
- `Knobler --download-model` (chamado automaticamente pelo `brew install`)
  baixa o modelo Parakeet (~461MB) sem precisar abrir o app primeiro.

## Permissões

- **Microfone** — *"Knobler grava sua voz enquanto você segura a tecla de
  ditado, para transcrever onde o cursor estiver."*
- **Acessibilidade** — necessária pro ⌘V sintético colar o texto no app ativo.
