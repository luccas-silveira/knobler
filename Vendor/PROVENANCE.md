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
