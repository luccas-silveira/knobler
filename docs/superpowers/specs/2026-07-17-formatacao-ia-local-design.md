# Formatação de transcript com IA local — design

**Data:** 2026-07-17
**Origem:** evoluir o ditado do Knobler pra ter a "formatação on-device" que o FluidVoice faz.

## Contexto

O ditado do Knobler (`Dictation.swift`) transcreve com Parakeet TDT v3 (local, via
FluidAudio) e cola o texto cru no app ativo. O Parakeet já pontua, mas deixa passar
fillers ("é", "ééé", "tipo", "sabe"), falsos começos e capitalização inconsistente.

O FluidVoice tem "Fluid Intelligence": pós-processa o transcript com um LLM local. A
investigação do código dele mostrou que o mecanismo é **uma chamada de chat
OpenAI-compatible** (`system prompt` de limpeza + transcript → texto limpo). O modelo
próprio deles ("Fluid-1", MLX 3,77 GB) é fechado e não reaproveitável, mas o mecanismo
é trivial de reproduzir com qualquer servidor local (Ollama/LM Studio).

## Decisão de modelo (benchmark na máquina alvo — M3 Pro, 18 GB)

Latência com modelo quente + qualidade em PT-BR, via Ollama:

| Modelo | Latência quente | Qualidade | Nota |
|---|---|---|---|
| **gemma3:4b** | **~0,9s** | ✅ melhor, sentido intacto | **escolhido** |
| gemma3n:e2b | ~1,2s | ✅ boa | mais lento que o 4B, sem ganho |
| qwen3:1.7b | ~0,7s | ⚠️ deixa fillers | risco de thinking (ver abaixo) |
| gemma3:1b | ~0,3s | ❌ inverte sentido, apaga texto | descartado |
| llama3.2:1b | ~0,5s | ❌ inventa, typos | descartado |
| qwen3:4b | ~120s 💀 | — | `think:false` ignorado nessa versão do Ollama |

Conclusões:
- **Abaixo de ~4B a qualidade colapsa** (1B chega a inverter o sentido ou apagar o texto).
- **Qwen é arriscado**: o modo "thinking" pode explodir a latência (120s no 4B) e o
  `think:false` é inconsistente entre versões. **Gemma 3 não tem modo thinking** → imune.
- **Default = `gemma3:4b`**. Endpoint e modelo ficam editáveis nas config.

## Arquitetura

**`TranscriptFormatter.swift` (novo, ~60 linhas)** — espelha o `DeepgramEngine`:
- `init(endpoint:model:)`
- `format(_ text) async throws -> String` — POST OpenAI-compatible
  `{model, messages:[system,user], temperature:0, stream:false}`, extrai
  `choices[0].message.content`. Timeout curto (15s). String vazia → devolve o cru.
- `prewarm() async` — chamada mínima só pra carregar o modelo na RAM.
- Schema OpenAI puro (sem campos Ollama-específicos) → funciona em Ollama `/v1`,
  LM Studio e qualquer servidor compatível.

**Prompt de sistema** (fixo, multilíngue):
> Você formata transcrições de voz. Faça apenas edições mínimas: remova fillers e falsos
> começos, corrija pontuação, capitalização e acentuação. NÃO adicione nem invente
> conteúdo, NÃO responda perguntas. Preserve sentido, tom e o idioma da entrada. Devolva
> SOMENTE o texto corrigido.

## Config (`AppSettings`)

- `formatTranscript: Bool` — **default `false`** (opt-in; reverte a decisão antiga de não
  formatar e adiciona latência).
- `formatEndpoint: String` — default `http://localhost:11434/v1/chat/completions`.
- `formatModel: String` — default `gemma3:4b`.

## Fluxo (`Dictation.swift`)

- `DictationController.start()`: se `formatTranscript` ligado, `Task { await formatter().prewarm() }`.
- `finish()`, no `Task` de transcrição, **depois** de transcrever e **antes** do branch
  sink/paste: `if formatTranscript { text = (try? await formatter().format(text)) ?? text }`.
  - **Fallback pro cru em qualquer falha** (servidor off, timeout, erro) — nunca perde o ditado.
  - Formata **uma vez** → tanto o card de Ask quanto o paste recebem texto limpo.
  - Pílula continua em `.transcribing` durante a formatação.

## UI (`SettingsView`, seção Ditado)

- Toggle "Formatar com IA (local)".
- Com o toggle on: `TextField` de endpoint e de modelo.

## Teste

- `TranscriptFormatter._selfCheck()` (`#if DEBUG`): assert que o parse extrai o `content`
  de um JSON OpenAI-compatible fixo e que entrada inválida não decodifica (garante o
  caminho de fallback). Roda no launch em debug.

## Cortado (YAGNI)

Prompts por-app (FluidVoice tem), streaming, histórico, seletor de modelo além do campo
de texto, download automático do modelo (o usuário roda `ollama pull` uma vez).
