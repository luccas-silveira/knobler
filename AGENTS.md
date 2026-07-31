# Repository Guidelines

## Project Structure

- `Knobler/` contains the macOS app, built with AppKit and SwiftUI.
- `project.yml` is the XcodeGen source of truth; `Knobler.xcodeproj` is generated.
- `tools/` contains self-checks, the snapshot harness, and release scripts.
- `relay/` is the Node.js notification relay; its tests live in `relay/test/`.
- `docs/` contains architecture, development, feature, and design documentation.
- `Snapshots/` is local visual QA output and is not a source of truth.

## Build and Development

```bash
xcodegen generate
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
./tools/check.sh
./tools/snapshot.sh
```

Run `xcodegen generate` after adding/removing Swift files or changing `project.yml`; never edit the generated project by hand. `check.sh` runs the canonical standalone Swift self-checks used by CI. The snapshot script renders UI states to `Snapshots/*.png`; inspect changed images visually. For relay changes, run `cd relay && npm test`.

## Coding Style and Naming

Use standard Swift formatting with four-space indentation, `PascalCase` for types, and `camelCase` for properties and functions. Keep UI strings and comments in pt-BR, and preserve existing AppKit/SwiftUI state-ownership boundaries. JavaScript in `relay/` follows the existing ESLint-free Node style and uses descriptive camelCase names. Mark deliberate simplifications with a `// ponytail:` comment describing the limitation.

## Testing Guidelines

The app has no XCTest target: add focused `tools/*check*.swift` self-checks using `assert(...)`, then register new checks in `tools/check.sh`. UI changes require regenerated snapshots and image inspection; views needing real AppKit windows may require manual screenshots. Relay tests use Node’s built-in test runner and follow `*.test.js` naming.

## Commits and Pull Requests

Use short, imperative Conventional Commits, such as `feat: add link preview` or `fix: preserve notification history`. PRs should explain the problem and solution, list validation commands and results, include screenshots for UI changes, and call out permission, data, network, or API compatibility effects. Update `CHANGELOG.md` and relevant docs when public behavior changes. Do not manually bump versions or create release tags; use `tools/release.sh`.

## Security

Never commit tokens, private keys, personal captures, audio dumps, webhook payloads, or local credentials. Review `SECURITY.md` before changing API listeners, Keychain access, relay authentication, or stored data.
