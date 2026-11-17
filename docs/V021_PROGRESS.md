# ChaiClassics 0.2.1

Baseline: released 0.2.0, commit `759e94943d409a6945f84f9b99f9768f6b144fb0`.

## Interaction and art

- Tic-tac-toe and Connect Four use a cancellable minimum 450 ms AI thinking interval. Their reserved turn/status space keeps the board stationary. Connect Four animates each real human/AI token to its legal destination before accepting another turn.
- Memory uses native 3D card flips, a 650 ms mismatch viewing interval that begins after the second flip completes, and immediate next-turn input after both closing animations and persistence complete.
- Maze uses a 360-degree analog joystick and a frame-driven player overlay. Reversal is immediate; walls remain authoritative, and saves commit only at cell centers. Directional controls remain available.
- 24 starts with no selected operator: number, operator, number, apply. Operand roles, the current expression, result-first card ordering, undo and the full calculation breadcrumb make each operation visible.
- App icon and eight playable-game illustrations use a coherent navy/teal, ivory, coral and gold style. The actual boards/cards/tiles use corresponding shared materials. These images are decorative art, never substitute gameplay screenshots.
- Scoped `CADisplayLink` rendering and the iPhone high-refresh opt-in remove the previous 30 fps confetti cap. The system chooses the actual supported cadence; Low Power Mode caps the requested rate at 60. Quality changes particle count, not a deliberate animation frame limit. Reduce Motion and existing low-power celebration suppression remain respected. Simulator tests cannot certify physical 120 Hz delivery.
- Low/medium/high visual detail is stored with a backward-compatible decoder. Released preferences retain their theme, language, haptics and keep-awake values when the new field is absent.

## Catalog

25 logical games: 8 playable and 17 coming soon. Home has 14 cards, including Board Games and Solitaire folders. Board Games contains 2 playable games and 6 explicitly upcoming games. See [the board-game roadmap](BOARD_GAMES_ROADMAP.md).

No future preview creates a persistent `GameID`. Existing game namespaces, Bundle ID, original puzzle bytes and the signing/upload implementation remain unchanged. No network gaming, advertisements, accounts, subscriptions or website work is added.

## Verification

Verification results must identify the actual commit, workflow run and executed scope. Successful unchanged cases may be carried forward only through dependency-checked evidence; changed, failed or unexecuted cases remain required. UI test success does not establish measured device frame rate. Final Simulator evidence and TestFlight processing status are recorded separately when available.
