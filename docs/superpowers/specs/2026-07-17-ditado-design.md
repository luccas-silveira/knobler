# Ditado por voz no Knobler (v0.8) — Design

Data: 2026-07-17 · Status: aprovado em conversa

## Objetivo

Ditado estilo Superwhisper: segurar ⌥ direita → falar → soltar → o texto
transcrito é inserido no app ativo, onde o cursor estiver. Local-first,
privado, com cloud opcional.

## Decisões (com o porquê)

| Decisão | Escolha | Porquê |
|---|---|---|
| Escopo | Ditado completo no cursor | É o caso de uso real; clipboard-only seria meio produto |
| Engine primário | **Parakeet TDT v3 local** via FluidAudio (SPM) | 600M params, pt-BR, ~80ms, ~66MB RAM, qualidade ≈ Whisper large-v3; grátis e offline |
| Engine opcional | **Deepgram** (pre-recorded API, `smart_format=true`, `language=multi`) | Escolha do usuário p/ áudio difícil; toggle nos Ajustes |
| Hotkey | ⌥ direita segurada (keycode 61), hold-to-talk | Tecla morta, não conflita; sem UI de configuração no v1 |
| Inserção de texto | Pasteboard + ⌘V simulado, restaura clipboard anterior | Robusto com acentos/pt-BR; método usado pelos apps da categoria |
| Fallback whisper.cpp | Não no v1 | Parakeet cobre qualidade; whisper.cpp é a parte mais cara (C++, 600MB+) — só se Parakeet decepcionar |

## Fluxo

1. `flagsChanged` com keycode 61 (⌥ direita) pressionada → `DictationController`
   entra em `.recording`; notch abre com barras de nível (estilo do visualizador).
2. Soltar a tecla → `.transcribing` (spinner no notch); áudio vai pro engine ativo.
3. Resultado → `.inserting`: salva clipboard atual, escreve o texto, simula ⌘V
   no app frontmost, restaura o clipboard (~200ms depois); notch fecha.
4. **Cancelamento**: Esc durante gravação, ou qualquer outra tecla pressionada
   enquanto ⌥ direita está segurada (usuário estava fazendo ⌥+combo normal) →
   volta a `.idle`, descarta áudio, repassa os eventos sem interferir.
5. Gravação mínima < 0,5s é descartada (toque acidental na tecla).

## Componentes

- **`Dictation.swift`** (novo) — `DictationController` (state machine
  `idle → recording → transcribing → inserting`), captura de mic via
  `AVAudioEngine` (16kHz mono Float32), inserção via pasteboard+⌘V.
  Protocolo `TranscriptionEngine { func transcribe(_ audio: [Float]) async throws -> String }`
  com `ParakeetEngine` (FluidAudio) e `DeepgramEngine` (URLSession multipart).
- **Detecção de tecla** — estende o CGEventTap existente (`VolumeHUD`) com máscara
  `flagsChanged`; reusa health-check e permissão de Acessibilidade já existentes.
- **UI no notch** — estados `gravando` (barras de nível + pontinho vermelho) e
  `transcrevendo` (spinner) no card; download do modelo no 1º uso mostra progresso.
- **Ajustes** — toggle "Ditado", toggle "Usar Deepgram (cloud)", campo API key
  (armazenada no Keychain). Default: ditado ligado, engine local.
- **`GET /status`** — ganha `dictation: {state, engine, modelReady}` p/ diagnóstico.

## Permissões e dependências

- **Microfone**: novo — `NSMicrophoneUsageDescription` no Info.plist; prompt no 1º uso.
- **Acessibilidade**: já concedida (tap + ⌘V sintético usam a mesma).
- **FluidAudio via SPM**: primeira dependência externa do projeto (declarar no
  project.yml/xcodegen). Modelo Parakeet v3 baixado do HuggingFace no 1º uso
  (~600MB em disco, cache em Application Support).

## Tratamento de erro

- Modelo ainda baixando → card mostra progresso; ditado indisponível até concluir.
- Engine falha (rede/Deepgram, modelo corrompido) → card mostra erro curto;
  áudio é descartado (sem fila de retry no v1).
- Sem permissão de mic → card instrui a habilitar em Ajustes do Sistema.

## Fora do escopo (v1)

Modos de formatação com LLM, transcrição de arquivos, streaming ao vivo,
tradução, hotkey configurável, retry/fila de áudio. Parakeet v3 já pontua e
capitaliza — suficiente.

## Validação

- Snapshot harness: novos estados `gravando`, `transcrevendo`, `erro`.
- E2E real: ditar em TextEdit (pt-BR com acentos), conferir texto no cursor e
  clipboard restaurado.
- Cancelamentos: Esc, ⌥+tecla, toque < 0,5s.
- `GET /status` reflete estado e engine.
