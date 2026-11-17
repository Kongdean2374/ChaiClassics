# ChaiClassics v0.2.0 development evidence

Stable baseline: `53411e7d6fbd90832037e85156340288fab652fa`. Work takes place on `develop/0.2.0`; no incomplete candidate may be uploaded to TestFlight.

## Stages 1–4: implemented, device verification pending

- Structured catalog: 21 logical games, 17 home cards, 5 solitaire children, 8 playable routes and 13 clearly marked upcoming games. Home cards contain no saved-progress summary.
- New games: complete Tic-tac-toe, Connect Four, exact-rational 24 Game, Memory Match and seeded Maze rules, native SwiftUI menus/play/result/replay flows, separate schema-1 save namespaces and bilingual text.
- Legacy Sudoku/minesweeper/sliding envelopes, namespaces, rules, 150-puzzle resource and immutable puzzle manifest are unchanged. New game IDs do not include upcoming catalog entries.
- Recovery preserves unreadable files in a per-game local archive only after confirmation; unsupported future versions remain protected.
- Local official Swift 6.1.2/Linux run: **95 XCTest cases, zero failures**. Includes exhaustive Tic-tac-toe positions and hard-AI continuations, Connect Four rules/AI bounds, 1,362 independently solvable 24 Game multisets, 1,000 Memory seeds, 3,075 Maze seeds, and genuine v0.1.0 save upgrade/isolation checks.
- Local SwiftUI/XCTest syntax checks passed. Linux does **not** type-check Apple SwiftUI/XCTest frameworks; actual Xcode compilation and simulator flows remain pending.

## Stages 5–6: release gates

Before integration/release, the exact candidate commit must pass the full Swift/Python/Ruby checks, Xcode Simulator build, every declared iPhone UI test, focused iPhone Visual Smoke and iPad gallery plus all five new game journeys. A separately marked release candidate and complete same-SHA evidence are mandatory. No test failures, missing cases or unexpected skips may be suppressed.

The release uses the existing trusted-main TestFlight workflow and match readonly assets. Upload, Apple processing, internal readiness and external Beta review are separate states. No formal App Store review/submission, public release, Game Center, website change or new server/data-collection service is authorized by this development work.

This document records implementation scope and verified local results. It is not a claim that stages 5–6 or a TestFlight upload have completed. Final run URLs, simulator identities and Apple version/build evidence will be recorded after execution.
