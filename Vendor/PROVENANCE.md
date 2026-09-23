# Procedência — Vendor/

## mediaremote-adapter (framework + script perl)

- **Origem:** <https://github.com/ungive/mediaremote-adapter>
- **Tag:** `v0.7.6` · commit `3ac3d4bdf862c7b5399b4fba4df5689f5c38609a`
- **Licença:** BSD 3-Clause
- **Data do build:** 2026-07-21
- **Por quê vendorado:** os releases do GitHub não publicam binário; build
  local a partir do source pinado mantém a cadeia de suprimento limpa.
- **Build (reproduzir):**

  ```bash
  git clone --depth 1 --branch v0.7.6 https://github.com/ungive/mediaremote-adapter
  cd mediaremote-adapter && mkdir build && cd build
  cmake .. -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" && cmake --build . --config Release
  # → build/MediaRemoteAdapter.framework (universal) + bin/mediaremote-adapter.pl
  ```

- **Uso:** o framework NÃO é linkado pelo app — é carregado pelo
  `/usr/bin/perl` (binário da Apple com o entitlement do MediaRemote), que o
  `MediaRemoteSource.swift` invoca. Ver `project.yml` (embed sem link) e o
  design/research em `docs/superpowers/specs/2026-07-21-now-playing-universal-*`.

## MonitorControl 4.4.0

- **Origem:** cópia fornecida em `MonitorControl-4.4.0/`, projeto
  <https://github.com/MonitorControl/MonitorControl>, versão declarada 4.4.0.
  A cópia local inclui o substituto `KeyboardShortcuts.swift`; não presumimos
  que seu conteúdo corresponde byte a byte à tag pública.
- **Licença:** MIT; texto integral em `MonitorControl/License.txt` e avisos
  de copyright preservados nos arquivos.
- **Transportes reutilizados:** `Arm64DDC.swift`, `IntelDDC.swift`, `Command.swift`,
  declarações privadas necessárias de `MonitorControl.h`. Identificação IOKit
  e pontuação de correspondência ARM preservadas.
- **Adaptações:** `Display.swift` reúne os caminhos necessários de `Display`,
  `AppleDisplay`, `OtherDisplay` e gamma/overlay de `DisplayManager`. Mantém
  curvas, calibração, escala combinada configurável (padrão 0,5), piso de
  software 0,15, suavização em passos /6 e 20 ms, remapeamento e tentativas.
  A fila serial e invalidação por geração/revisão pertencem ao serviço
  `Monitores.swift`; menus, sliders, OSD e delegado upstream foram removidos.
  Falhas de escrita não entram no cache; leitura ARM malsucedida não herda
  sucesso da escrita do pedido. A validação compartilhada `MonitorDDCReply`
  verifica tipo, status, comando e checksum; converte os bytes altos antes
  do deslocamento de 16 bits (corrigindo truncamento no caminho Intel).
  Portas IOKit são liberadas também em Release, sem efeito colateral dentro
  de `assert`; interfaces I2C são liberadas ao terminar cada tentativa.
  Preferências e atalhos usam prefixo
  `monitores.` no domínio Knobler, sem importar valores do aplicativo original.
  `KeyboardShortcuts.swift` preserva registro Carbon e gravador; textos pt-BR,
  navegação por teclado e remoção do handler ao desativar foram adaptados.
  2026-09-23 — `removeHandlers(for:)` adicionado pelo Knobler; Monitores deixou
  de usar `removeAllHandlers`.
- **Bindings:** frameworks privados Apple `DisplayServices` e `CoreDisplay`,
  além de IOKit/CoreGraphics/CoreAudio. Não se inclui updater, login helper,
  preferências ou capturador de teclas de mídia upstream.
- **Compilação:** somente `Vendor/MonitorControl/` é fonte do alvo. A pasta
  importada não é dependência de build. Compatibilidade física de monitores,
  adaptadores, Intel e Apple Silicon deve ser validada separadamente.
