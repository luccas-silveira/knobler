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


<claude-mem-context>
# Memory Context

# [knobler] recent context, 2026-09-11 9:12am GMT-3

Legend: 🎯session 🔴bugfix 🟣feature 🔄refactor ✅change 🔵discovery ⚖️decision 🚨security_alert 🔐security_note
Format: ID TIME TYPE TITLE
Fetch details: get_observations([IDs]) | Search: mem-search skill

Stats: 30 obs (15,015t read) | 158,759t work | 91% savings

### Jul 29, 2026
S3257 Confirm conflict resolution strategy; finalize data sync scope; decide whether message media synchronizes in first version or defers to on-demand later (Jul 29 at 10:18 PM)
S3272 Write implementation plan and commit; then close the session — auditing and documenting LAN sync feature design (Jul 29 at 10:19 PM)
S3290 Release v0.16.0 of Knobler macOS application (Jul 29 at 10:58 PM)
### Jul 30, 2026
S3293 Identify missing documentation in Knobler project that should exist but doesn't (Jul 30 at 9:33 AM)
S3296 Document relay operations procedures and inventory of app storage locations — fill two documentation gaps identified in audit (Jul 30 at 9:48 AM)
S3297 Complete documentation audit (relay operations + app storage inventory) and establish private organization repository mirror (Jul 30 at 10:09 AM)
S3299 Establish private organization repositories for knobler ecosystem: create zoi-tech mirrors, verify repository hygiene, and standardize git tracking (Jul 30 at 10:13 AM)
S3305 Create and scaffold a prompt for updating Knobler website/documentation with v0.16.0 features, then execute website content updates based on CHANGELOG findings (Jul 30 at 10:15 AM)
S3665 Comprehensive code review and testing of Knobler macOS notch application, focusing on shelf management, file conversion, webhook relay, and investigation of reported visual defect (Jul 30 at 10:28 AM)
### Sep 8, 2026
S3666 Comprehensive code review of Knobler with findings documented and archived in the repository (Sep 8 at 11:26 AM)
### Sep 9, 2026
187148 10:31a 🔵 Animation interruption reproduces via rapid setExpandedDirect() calls competing with morphAnimation drivers
187149 10:32a 🔵 NotchWindow frame anchoring and coordinate space mismatches in animation interruption
### Sep 10, 2026
187204 9:09a 🔵 Gesture-close bug confirmed and Plugin.swift struct locations identified
187205 " 🔵 Multiple test failures confirm five of six review bugs with specific error signatures
187206 9:10a 🔵 PluginDeps initialization signature mismatch and ScheduleEngine type inference failures in plugincheck
187207 " 🔴 Implemented fixes for five confirmed bugs: gesture-close editing release, shelf reimport stacking, preview save failure retention, and webhook token management
187208 " ✅ Build detected WebhookClient.swift file modification during compilation; CHANGELOG updated with fix entries
187209 9:11a 🔄 Refactored ShelfStore for dependency injection and integrated preview test suite with isolated UserDefaults
187210 " 🔵 plugincheck confirms reminder snooze erasure bug: Descanso deletes scheduled snooze before app restart
187211 9:12a ✅ All check.sh tests pass after fix implementations; LinkPreview lifecycle and project configuration confirmed
187212 " ✅ Comprehensive bug fix implementation complete: 21 files modified with 409 insertions, all core tests passing
187213 9:13a 🔴 Added regression test scenarios for gesture-close and preview save failures; relay mapping validation prevents null string HTTP 500
187214 " ✅ Fixed npm test runtime compatibility; all relay and Swift test suites pass with Node 20.19.6
187215 9:14a ✅ Comprehensive documentation of fixes completed; 38 of 39 tests pass, conversionpreviewcheck fails during retry scenario
187216 " 🔵 Compilation errors in PluginsSettingsPane.swift block conversionpreviewcheck test; KnoblerMain reference not found
187217 9:15a ✅ Complete implementation of all bug fixes verified via git diff; preview test still fails with file move error
187218 " 🔵 PDF partial conversion test validates retry logic: saves 2 of 3 pages, preserves failed state, allows second attempt
187219 9:17a ✅ Core regression test suite passes; conversionpreviewcheck compilation errors resolved
187220 " ✅ Full test suite verification complete; 39 checks passing with snapshot generation successful
187221 9:18a ✅ Comprehensive fix validation documented; 39 checks, 50 relay tests, build and snapshots all passing
**187231** 9:47a ⚖️ **Interaction contract decision for animation/expansion rewrite**
Animation interruption and frame anchoring bugs will be fixed without changing when NotchWindow opens/closes
Card interrupt priorities and multi-monitor gesture behavior remain unchanged from current implementation
Existing fixes and user experience preserved through implementation-only changes, not behavior redefinition
Recommended approach selected: maintain interaction rules, fix underlying implementation to eliminate inconsistencies

**187233** 9:49a 🔵 **Work-in-progress state shows multi-system modifications across UI, services, persistence, and backend**
Git status shows 27 modified files: NotchViewModel.swift, NotchView.swift, Reminders.swift, Descanso.swift, Plugin.swift, ShelfOrdem.swift, WebhookClient.swift, relay/src and relay/test files, and multiple check.swift tools
5 new untracked files created: ShelfStore.swift (new store), docs/diagnostico-visual.md, docs/revisao-2026-09-08.md, tools/diagnostico-visual.sh, tools/diagnostico-visual.swift
NotchViewModel.swift contains expanded property didSet cleanup that clears mirrorOn, focusLocked, and focoPendente when collapsed—intended to prevent state leakage on relaunch
Modified services include Reminders.swift and Descanso.swift, both related to snooze/reminder state persistence noted in pre-session context
Plugin.swift modified, suggesting changes to service registration or hook integration for reminder/snooze lifecycle
Relay backend database and server code modified (relay/src/db.js, relay/src/server.js), along with test files indicating backend-side fixes

**187234** " 🔵 **NotchViewModel state cleanup on collapse prevents editing state leakage across reopen cycles**
NotchViewModel.swift expanded property has didSet handler that fires when collapsed (!expanded)
Cleanup sets mirrorOn=false to ensure camera never stays active when notch closed
Cleanup clears focusLocked=false to reset manual selection on reopen
Cleanup clears focoPendente=nil to prevent unconsumed focus requests from leaking to next open cycle
Comment notes: "pedido de foco que ninguém consumiu morre aqui" (unconsumed focus request dies here) to prevent promotion of card in unintended section

**187291** 2:24p 🔵 **Geometry and frame-violation detection system mapped for bug-fix planning**
Geometry constants: noteEditorHeight=120pt, sectionStripHeight=22pt, wingWidth=44pt, hudWingWidth=85pt, notificationWidth=380pt, linkCardWidth=780pt
CorteDoKnob frame-violation detector implements: invariant validation, proof capture/logging (50-line rolling file), healing/regeneration with maximum-cure ceiling, cost measurement under 1µs per check
Layout calculation via currentSize property: sums notchSize width/height plus conditional wing offsets; altura calculation via alturaDaSecao() static method varies by section and preview state
cortedetectorcheck.swift validates six invariant paths: no-violation baseline, violation detection/logging, healing cycle with maximum-cure enforcement, proof persistence, and performance cost constraints
Security model: local API on 127.0.0.1:4477 (no auth), Keychain for tokens/secrets, opt-in remote processing (Deepgram, LM Studio), no credential storage in UserDefaults/logs
NotchViewModel state cleanup on collapse (expanded didSet): clears mirrorOn, focusLocked, focoPendente to prevent state leakage across reopen cycles

**187293** 2:26p 🔄 **Refactor Notch expansion/animation control into state machine with centralized cancellation**
NotchPresentation.swift created: pure data structure calculating layout from NotchContentState, decouples presentation from ViewModel mutations
NotchOpening state machine introduced to manage hover delays, cancellation, and generation tracking to prevent race conditions
expanded property changed to private with read-only access; all expansion state flows through setExpandedDirect(), setHover(), and applyExpanded()
applyExpanded() cleanup ensures typingNote editing flag cleared, mirrorOn disabled, focusLocked reset, and focoPendente nil when collapsing
DispatchWorkItem cancellation centralized: openingWork?.cancel() called before all state mutations to eliminate orphaned async tasks
setHover() implements typed delays: 0.18s for open, 0.30s for close, 3.0s for typing-mode close, with cooldown guard preventing rapid reopen within 0.45s
Global regex refactor replaced all direct vm.expanded = true/false mutations in tools with vm.setExpandedDirect(true/false) API calls
questionIsActive callback allows external systems to inform expansion eligibility without coupling to ViewModel internals

**187296** 2:29p 🔵 **blurReplace transition API not found in SwiftUI framework**
NotchView.swift line 135: error type 'AnyTransition' has no member 'blurReplace'
NotchView.swift line 597: error type 'AnyTransition' has no member 'blurReplace'
NotchView.swift line 809: error type 'AnyTransition' has no member 'blurReplace'
NotchView.swift line 1136: error type 'AnyTransition' has no member 'blurReplace'
SwiftUI.swiftmodule interface search found no definition for blurReplace transition type
Build log /tmp/knobler-rewrite-build.log contains 4 errors blocking compilation

**187297** 2:30p 🔵 **BlurReplaceTransition exists but AnyTransition.blurReplace convenience API missing**
SwiftUICore.framework defines BlurReplaceTransition as @MainActor @preconcurrency public struct
BlurReplaceTransition conforms to SwiftUICore.Transition protocol
AnyTransition provides init<T>(_ transition: T) to wrap any Transition type
AnyTransition provides combined(with:) method for chaining transitions
AnyTransition does not expose static member .blurReplace factory method
Transition protocol is defined as @MainActor @preconcurrency protocol

**187299** 2:33p 🔵 **Multiple compilation errors in NotchPresentation and NotchView refactor**
NotchPresentation.swift line 95: type does not conform to Equatable because stored property CGSize lacks Equatable conformance; synthesized conformance blocked
NotchPresentation.swift line 157: Duration type cannot convert to Double argument; geometry calculations need type correction
NotchPresentation.swift line 157: code uses CGRect.width, CGRect.maxY, CGRect.minY properties which do not exist on CGRect in this context
NotchView.swift line 151: missing argument label 'scale:' in function call
NotchView.swift contains 16 instances of AnyTransition(.blurReplace) hardcoded transitions across lines 135, 139, 142, 150, 154, 162, 169, 174, 181, 188, 598, 612, 618, 623, 810, 1137
Self-check presentationcheck FALHOU (FAILED) status in build log

**187300** " 🔵 **Animation interruption test harness validates state mutation race conditions**
Test harness defines three interrupt scenarios: hover-close (vm.fecharPorHoverOut), focus-change (vm.focar), dictation state (vm.dictation)
Each scenario tested with three delays: 0.05s, 0.12s, 0.24s intervals representing typical gesture/notification timing
Test step sequence verifies state after direct-close: expanded=false, mode=music, editing=true (bug confirmation)
Test step sequence verifies state after hover-close: mode=closed, editing=false (expected cleanup behavior)
Animation interruption happens when setExpandedDirect() cancels DispatchWorkItem before morphAnimation completes spring curve
Rapid state mutations executed at 0.04s intervals (40ms) to force animation overlap and interruption

**187303** 2:44p 🔵 **NotchPresentation.swift geometry constants and alturaDaSecao height calculation verified**
NotchPresentation.swift defines NotchMetrics enum with 15 geometry constants: historyHeight=260, sectionStripHeight=22, noteEditorHeight=120, linkCardWidth=780, linkContentWidth=736, linkHeaderHeight=24, shelfCellHeight=75
alturaDaSecao(_ section:preview:pilhaAberta:espelhoLigado:linkAberto:eventoProximo:) function calculates section-specific heights based on NotchSection type and state flags
Section height mappings: musica=118, pomodoro=128-150 (with event), atividade=60; function respects multi-state constraints (preview and pilhaAberta tested in order)
linkCardWidth=780pt fixed for link section, standard width used for other sections via larguraDoCard() function
Derived constants prevent desynchronization: shelfPilhaHeight computed as 18+8+shelfCellHeight*2+8; linkWebHeight derived from linkContentWidth*9/16
check.sh test harness includes relay hermetic tests (template, normalize, ratelimit, tokens via node --test) and environment-dependent codex-integration gate


Access 159k tokens of past work via get_observations([IDs]) or mem-search skill.
</claude-mem-context>