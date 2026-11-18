# ChaiClassics development and release policy

Honor the user's current development stage. Daily work targets a playable TestFlight Beta, not perfect App Store regression on every edit.

- Batch ordinary feature, text and UI changes. Use code review and relevant local/static checks. Do not proactively dispatch Mac, full XCTest, Visual Smoke or iPad runs for every commit.
- For a reported bug, reproduce and verify the smallest affected behavior and essential related paths. Read an existing failure before retrying; do not expand a one-game bug into all 25 games without evidence.
- Ordinary Push/PR CI is Linux-only and preserves the existing three check names. Never bypass or disable branch protection. Manual/reusable full Mac CI remains available when needed.
- Upload one TestFlight build per completed batch, using explicit Beta mode, exact main/tag/commit/version checks, core rules/save tests and the real signed archive/export/upload. Do not require all-game UI regression for Beta. Never upload a known fatal startup, compile or core-play blocker.
- Do not repeat an already valid compile without a relevant change. Signed device archiving remains mandatory; an unsigned Simulator build cannot substitute for it.
- Codex may dispatch TestFlight within existing authorization and inspect Apple receipt/processing for that exact build. Report PROCESSING, VALID, failed or unknown accurately; upload success does not mean external review approval or install readiness.
- Keep unexecuted tests explicitly unexecuted. Never fabricate green results or promote a partial Beta check to full release evidence.
- Cancel superseded non-release checks when appropriate. Never cancel an active signing/upload/release job because of a new Push. Keep `apple-release` concurrency cancellation disabled.
- Preserve full regression for separately authorized App Store preparation. Do not automatically submit/publish to App Store or modify certificates, Secrets, Bundle ID, old saves or Sudoku puzzles.
